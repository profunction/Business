// dispatch-notifications：把通知队列里的通知发出去（推送 / WhatsApp）。
// 由 pg_cron（每分钟）和 notifications 的 trigger 用 pg_net 叫：
//   net.http_post(url := <project_url>/functions/v1/dispatch-notifications, headers := {apikey: <secret_key>})
// 身份：只接受 apikey 头等于 secret key（固定时间比较）。config.toml 里 verify_jwt = false。
//
// 流程：claim_notifications(50) → 每条按 channel 发 → complete_notification；推送失效的 token → remove_device_tokens。
// 一直领到没得领（或领到的不满一批），或跑了大约 100 秒。一条出错不会影响其他条。回传 JSON 统计。

import {
  type FcmServiceAccount,
  fcmServiceAccount,
  intEnv,
  serviceKeys,
  type WhatsAppConfig,
  whatsappConfig,
} from "../_shared/env.ts";
import { errorMessage, json, log, mapLimit, matchesAny, runInBackground, UUID_RE } from "../_shared/http.ts";
import { type NotificationItem, pushContent, type PushTarget, whatsappTemplate } from "../_shared/messages.ts";
import { sendFcm } from "../_shared/fcm.ts";
import { sendTemplate } from "../_shared/whatsapp.ts";
import { adminClient, DbError, rpc } from "../_shared/supabase.ts";
import type { SupabaseClient } from "@supabase/supabase-js";

const CLAIM_LIMIT = 50;
const ITEM_CONCURRENCY = 5;
const TARGET_CONCURRENCY = 4;

type Channel = "push" | "whatsapp";

export interface Outcome {
  status: "sent" | "failed" | "skipped";
  channel: Channel | null;
  error: string | null;
  waMessageId: string | null;
  /** failed 时：等一下再试（2、4、8、16 分钟）；false = 不再试 */
  retry: boolean;
  deadTokens: string[];
}

export interface Summary {
  ok: boolean;
  rounds: number;
  claimed: number;
  sent: number;
  failed: number;
  retry_scheduled: number;
  skipped: number;
  tokens_removed: number;
  errors: number;
  duration_ms: number;
  error?: string;
}

interface Services {
  fcm: FcmServiceAccount | null;
  whatsapp: WhatsAppConfig | null;
}

const skipped = (channel: Channel | null, error: string): Outcome => ({
  status: "skipped",
  channel,
  error,
  waMessageId: null,
  retry: false,
  deadTokens: [],
});

const failed = (channel: Channel, error: string, retry: boolean, deadTokens: string[] = []): Outcome => ({
  status: "failed",
  channel,
  error: error.slice(0, 500),
  waMessageId: null,
  retry,
  deadTokens,
});

/** claim_notifications 回传的一条 → 整理好的 NotificationItem（id 不对就 null，没办法 complete） */
export function toItem(raw: unknown): NotificationItem | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;
  if (typeof r.id !== "string" || !UUID_RE.test(r.id)) return null;
  const targets = Array.isArray(r.push_targets)
    ? (r.push_targets as unknown[]).flatMap((t): PushTarget[] => {
      const x = t as Record<string, unknown> | null;
      return x && typeof x.target === "string" && x.target.trim() !== ""
        ? [{ target: x.target.trim(), kind: x.kind === "fid" ? "fid" : "token" }]
        : [];
    })
    : [];
  return {
    id: r.id,
    event_type: typeof r.event_type === "string" ? r.event_type : "",
    payload: r.payload && typeof r.payload === "object" ? r.payload as Record<string, unknown> : {},
    locale: typeof r.locale === "string" ? r.locale : null,
    channel: r.channel === "push" || r.channel === "whatsapp" ? r.channel : null,
    push_targets: targets,
    whatsapp_phone: typeof r.whatsapp_phone === "string" && r.whatsapp_phone.trim() !== "" ? r.whatsapp_phone : null,
    attempts: typeof r.attempts === "number" ? r.attempts : undefined,
    details: r.details && typeof r.details === "object" ? r.details as NotificationItem["details"] : null,
  };
}

async function sendPush(item: NotificationItem, sa: FcmServiceAccount | null): Promise<Outcome> {
  if (item.push_targets.length === 0) return skipped("push", "NO_PUSH_TARGETS");
  if (!sa) return failed("push", "FCM_NOT_CONFIGURED", false);
  const content = pushContent(item);
  const results = await mapLimit(item.push_targets, TARGET_CONCURRENCY, (t) => sendFcm(sa, t, content));
  const dead = item.push_targets.filter((_, i) => {
    const r = results[i];
    return !r.ok && r.dead;
  }).map((t) => t.target);
  const okCount = results.filter((r) => r.ok).length;
  const failures = results.flatMap((r) => (r.ok || r.dead ? [] : [r]));
  if (failures.length > 0) {
    log("warn", "fcm_send_failed", {
      notification_id: item.id,
      errors: failures.map((f) => ({ http: f.httpStatus, status: f.status, code: f.errorCode })),
    });
  }
  if (okCount > 0) {
    return { status: "sent", channel: "push", error: null, waMessageId: null, retry: false, deadTokens: dead };
  }
  if (failures.length === 0) {
    // 全部失效：删掉之后重试，下一次 claim 会重新选渠道（auto 的会改走 WhatsApp）
    return failed("push", "PUSH_TARGETS_UNREGISTERED", true, dead);
  }
  const f = failures[0];
  return failed("push", `FCM_${f.errorCode ?? f.status}: ${f.message}`, failures.some((x) => x.retryable), dead);
}

async function sendWhatsApp(item: NotificationItem, cfg: WhatsAppConfig | null): Promise<Outcome> {
  if (!item.whatsapp_phone) return skipped("whatsapp", "NO_WHATSAPP_PHONE");
  const template = whatsappTemplate(item);
  if (!template) return skipped("whatsapp", "NO_WHATSAPP_TEMPLATE");
  if (!cfg) return failed("whatsapp", "WHATSAPP_NOT_CONFIGURED", false);
  const r = await sendTemplate(cfg, item.whatsapp_phone, template);
  if (r.ok) {
    return { status: "sent", channel: "whatsapp", error: null, waMessageId: r.messageId, retry: false, deadTokens: [] };
  }
  log(r.alert ? "error" : "warn", r.alert ? "whatsapp_alert" : "whatsapp_send_failed", {
    notification_id: item.id,
    template: template.name,
    language: template.languageCode,
    http: r.httpStatus,
    code: r.code,
    retryable: r.retryable,
    message: r.message,
  });
  return failed("whatsapp", `WHATSAPP_${r.code ?? `HTTP_${r.httpStatus}`}: ${r.message}`, r.retryable);
}

/** 发一条。不会丢错（任何意外都变成 failed + 重试）。 */
export async function processItem(item: NotificationItem, services: Services): Promise<Outcome> {
  try {
    if (item.channel === "push") return await sendPush(item, services.fcm);
    if (item.channel === "whatsapp") return await sendWhatsApp(item, services.whatsapp);
    return skipped(null, "NO_CHANNEL"); // 没装 App、也不能发 WhatsApp（或事件不走 WhatsApp）
  } catch (e) {
    log("error", "dispatch_item_error", { notification_id: item.id, error: errorMessage(e) });
    return failed(item.channel ?? "push", `INTERNAL_ERROR: ${errorMessage(e)}`, true);
  }
}

async function complete(admin: SupabaseClient, id: string, o: Outcome): Promise<boolean> {
  const params = {
    p_id: id,
    p_status: o.status,
    p_channel: o.channel,
    p_error: o.error,
    p_wa_message_id: o.waMessageId,
    p_retry: o.retry,
  };
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      await rpc<boolean>(admin, "complete_notification", params);
      return true;
    } catch (e) {
      const transient = e instanceof DbError ? e.transient : true;
      log("error", "complete_notification_failed", { notification_id: id, attempt, error: errorMessage(e) });
      if (!transient) return false;
    }
  }
  return false; // 留在「发送中」，10 分钟后会被重新领（算失败一次）
}

export async function dispatch(): Promise<Summary> {
  const started = Date.now();
  const budgetMs = intEnv("DISPATCH_TIME_BUDGET_MS", 100_000, 1_000, 380_000);
  const s: Summary = {
    ok: true,
    rounds: 0,
    claimed: 0,
    sent: 0,
    failed: 0,
    retry_scheduled: 0,
    skipped: 0,
    tokens_removed: 0,
    errors: 0,
    duration_ms: 0,
  };
  const admin = adminClient();
  const services: Services = { fcm: fcmServiceAccount(), whatsapp: whatsappConfig() };

  while (Date.now() - started < budgetMs) {
    let claimed: unknown;
    try {
      claimed = await rpc<unknown>(admin, "claim_notifications", { p_limit: CLAIM_LIMIT });
    } catch (e) {
      log("error", "claim_notifications_failed", { error: errorMessage(e) });
      s.ok = false;
      s.errors++;
      s.error = "CLAIM_FAILED";
      break;
    }
    const raw = Array.isArray(claimed) ? claimed : [];
    if (raw.length === 0) break;
    s.rounds++;
    s.claimed += raw.length;

    const dead = new Set<string>();
    await mapLimit(raw, ITEM_CONCURRENCY, async (r) => {
      const item = toItem(r);
      if (!item) {
        s.errors++;
        log("error", "invalid_claimed_item", {});
        return;
      }
      const o = await processItem(item, services);
      o.deadTokens.forEach((t) => dead.add(t));
      if (o.status === "sent") s.sent++;
      else if (o.status === "skipped") s.skipped++;
      else if (o.retry) s.retry_scheduled++;
      else s.failed++;
      if (!(await complete(admin, item.id, o))) s.errors++;
    });

    if (dead.size > 0) {
      try {
        const n = await rpc<number>(admin, "remove_device_tokens", { p_tokens: [...dead] });
        s.tokens_removed += typeof n === "number" ? n : 0;
      } catch (e) {
        s.errors++;
        log("error", "remove_device_tokens_failed", { count: dead.size, error: errorMessage(e) });
      }
    }
    // 领到的不满一批 = 能发的都发了。同一个 WhatsApp 号码排着的下一条留给下一次叫（trigger / 每分钟），
    // 不要在这里马上再领，免得同一个人几秒内连收几条（Meta 大约每 6 秒 1 条）。
    if (raw.length < CLAIM_LIMIT) break;
  }
  s.duration_ms = Date.now() - started;
  log("info", "dispatch_done", { ...s });
  return s;
}

export async function handler(req: Request): Promise<Response> {
  if (req.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405, { Allow: "POST" });
  const keys = serviceKeys();
  if (keys.length === 0) {
    log("error", "dispatch_not_configured", { reason: "SUPABASE_SECRET_KEYS missing" });
    return json({ error: "SERVICE_KEY_MISSING" }, 500);
  }
  if (!matchesAny(req.headers.get("apikey"), keys)) return json({ error: "UNAUTHORIZED" }, 401);

  const work = dispatch();
  // pg_net 只等 10 秒：交给 waitUntil 保护，就算 pg_net 先断线也会跑完；这里照样等结果回传统计
  runInBackground(work.catch(() => undefined));
  try {
    const summary = await work;
    return json(summary, summary.ok ? 200 : 502);
  } catch (e) {
    log("error", "dispatch_failed", { error: errorMessage(e) });
    return json({ error: e instanceof Error && e.name === "ConfigError" ? e.message : "INTERNAL_ERROR" }, 500);
  }
}

export default { fetch: handler };
