// dispatch-notifications：把通知队列里的通知发出去（推送 / WhatsApp）。
// 由 pg_cron（每分钟）和 notifications 的 trigger 用 pg_net 叫：
//   net.http_post(url := <project_url>/functions/v1/dispatch-notifications, headers := {apikey: <secret_key>})
// 身份：只接受 apikey 头等于 secret key（固定时间比较）。config.toml 里 verify_jwt = false。
//
// 流程：claim_notifications(50) → 每条按 channel 发 → complete_notification；推送失效的 token → remove_device_tokens。
// 一直领到没得领（或领到的不满一批），或快到时间预算（DISPATCH_TIME_BUDGET_MS，默认 100 秒）。一条出错不会影响其他条。
// 时间预算每条开始之前都看：剩下不到 15 秒（一个请求最多等的时间）就不再开始发，领到但还没发的用
// release_notification 放回队列（不算失败，下一次叫马上再领；不放的话会卡在「发送中」10 分钟、还算失败一次）；
// 放不回去（数据库出错）才退回旧的做法：标 failed + 重试（DISPATCH_TIME_BUDGET，2 分钟后再发）。
// 每个请求最多等到预算用完为止。回传 JSON 统计。
// complete_notification 暂时失败 → 隔 0.5 / 2（已经发出去的再加 5）秒再试：没记到「已发」的话 10 分钟后会重发一次。
// 平台的总时间（免费 150 秒、付费 400 秒，WORKER_WALL_CLOCK_MS）是按 worker 算的，一个 worker 会接很多个请求
// （每分钟的 cron、每个 trigger）：期限也不能超过「worker 开始 + 总时间 - 写结果的宽限」，不然晚进来的请求
// 会在发到一半时被平台杀掉（Meta 已经收下、还没记「已发」的，10 分钟后会再发一次）。
// worker 要被关掉（beforeunload）→ 不再领、不再开始发，领到了还没开始发的马上放回队列（不等正在发的那几条）。

import {
  type FcmServiceAccount,
  fcmServiceAccount,
  intEnv,
  serviceKeys,
  type WhatsAppConfig,
  whatsappConfig,
} from "../_shared/env.ts";
import {
  errorMessage,
  json,
  log,
  mapLimit,
  matchesAny,
  REQUEST_TIMEOUT_MS,
  runInBackground,
  UUID_RE,
} from "../_shared/http.ts";
import { type NotificationItem, pushContent, type PushTarget, whatsappTemplate } from "../_shared/messages.ts";
import { sendFcm } from "../_shared/fcm.ts";
import { sendTemplate } from "../_shared/whatsapp.ts";
import { adminClient, DbError, rpc } from "../_shared/supabase.ts";
import type { SupabaseClient } from "@supabase/supabase-js";

const CLAIM_LIMIT = 50;
const ITEM_CONCURRENCY = 5;
const TARGET_CONCURRENCY = 4;

export const DISPATCH_TIMING = {
  /** 剩下不到这么多时间就不再领新的、不再开始发（一个请求最多等这么久） */
  itemMinMs: REQUEST_TIMEOUT_MS,
  /** complete_notification 暂时失败时隔多久再试（已经发出去的用 sentRetryMs，多试一次） */
  retryMs: [500, 2_000],
  sentRetryMs: [500, 2_000, 5_000],
  /** 预算用完之后最多再等多久把结果记进数据库 */
  completeGraceMs: 10_000,
  /** worker 的总时间到之前，写完结果之后再留的余裕 */
  workerMarginMs: 5_000,
};

/** 这个 worker（isolate）什么时候开始的；stopping = 平台要关掉它了（beforeunload） */
export const worker = { startedAt: Date.now(), stopping: false };

/**
 * 这次 dispatch 的期限：请求进来 + 预算，也不能超过 worker 开始 + 平台总时间 - 写结果的宽限 - 余裕
 * （期限之后最多再花 completeGraceMs 写结果，全部要在平台杀掉 worker 之前做完）。
 */
export function dispatchDeadline(
  started: number,
  budgetMs: number,
  wallClockMs: number,
  workerStartedAt = worker.startedAt,
): number {
  const workerEnd = workerStartedAt + wallClockMs - DISPATCH_TIMING.completeGraceMs - DISPATCH_TIMING.workerMarginMs;
  return Math.min(started + budgetMs, workerEnd);
}

(globalThis as { addEventListener?: typeof addEventListener }).addEventListener?.("beforeunload", (ev: Event) => {
  worker.stopping = true;
  const detail = (ev as CustomEvent<{ reason?: unknown } | undefined>).detail;
  log("warn", "dispatch_worker_shutdown", { reason: String(detail?.reason ?? "unknown") });
  releaseWaiting();
});

/** 时间不够、没开始发的那条放不回队列时（release_notification 出错）：标 failed + 重试（2 分钟后再领） */
export const BUDGET_EXCEEDED = "DISPATCH_TIME_BUDGET";

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
  /** 时间不够 / worker 要被关掉、领到了但没发（放回队列；放不回去才标 failed + 重试） */
  deferred: number;
  errors: number;
  duration_ms: number;
  error?: string;
}

interface Services {
  fcm: FcmServiceAccount | null;
  whatsapp: WhatsAppConfig | null;
  /** 请求最多等到这时候（epoch 毫秒） */
  deadline?: number | null;
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

async function sendPush(
  item: NotificationItem,
  sa: FcmServiceAccount | null,
  deadline?: number | null,
): Promise<Outcome> {
  if (item.push_targets.length === 0) return skipped("push", "NO_PUSH_TARGETS");
  if (!sa) return failed("push", "FCM_NOT_CONFIGURED", false);
  const content = pushContent(item);
  const results = await mapLimit(item.push_targets, TARGET_CONCURRENCY, (t) => sendFcm(sa, t, content, { deadline }));
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

async function sendWhatsApp(
  item: NotificationItem,
  cfg: WhatsAppConfig | null,
  deadline?: number | null,
): Promise<Outcome> {
  if (!item.whatsapp_phone) return skipped("whatsapp", "NO_WHATSAPP_PHONE");
  const template = whatsappTemplate(item);
  if (!template) return skipped("whatsapp", "NO_WHATSAPP_TEMPLATE");
  if (!cfg) return failed("whatsapp", "WHATSAPP_NOT_CONFIGURED", false);
  const r = await sendTemplate(cfg, item.whatsapp_phone, template, { deadline });
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
    if (item.channel === "push") return await sendPush(item, services.fcm, services.deadline);
    if (item.channel === "whatsapp") return await sendWhatsApp(item, services.whatsapp, services.deadline);
    return skipped(null, "NO_CHANNEL"); // 没装 App、也不能发 WhatsApp（或事件不走 WhatsApp）
  } catch (e) {
    log("error", "dispatch_item_error", { notification_id: item.id, error: errorMessage(e) });
    return failed(item.channel ?? "push", `INTERNAL_ERROR: ${errorMessage(e)}`, true);
  }
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/**
 * 把结果记进数据库。暂时失败（网络、5xx……）→ 隔一下再试（DISPATCH_TIMING）；不会超过 stopAt。
 * 「已经发出去」的多试一次：没记到的话 10 分钟后会被重新领、再发一次（对方收到两张一样的单）。
 */
async function complete(admin: SupabaseClient, id: string, o: Outcome, stopAt: number): Promise<boolean> {
  const params = {
    p_id: id,
    p_status: o.status,
    p_channel: o.channel,
    p_error: o.error,
    p_wa_message_id: o.waMessageId,
    p_retry: o.retry,
  };
  const waits = o.status === "sent" ? DISPATCH_TIMING.sentRetryMs : DISPATCH_TIMING.retryMs;
  for (let attempt = 0;; attempt++) {
    try {
      await rpc<boolean>(admin, "complete_notification", params);
      return true;
    } catch (e) {
      const transient = e instanceof DbError ? e.transient : true;
      const wait = waits[attempt];
      const last = !transient || wait === undefined || Date.now() + wait > stopAt;
      log("error", "complete_notification_failed", {
        notification_id: id,
        attempt,
        status: o.status,
        channel: o.channel,
        // 已经发出去的 WhatsApp：记下 wamid，才对得回去（不然按钮回覆找不到订单）
        wa_message_id: o.waMessageId,
        final: last,
        error: errorMessage(e),
      });
      if (last) return false; // 留在「发送中」，10 分钟后会被重新领（算失败一次）
      await sleep(wait);
    }
  }
}

/** 正在处理的一批（claim_notifications 领到的） */
interface Round {
  admin: SupabaseClient;
  stopAt: number;
  s: Summary;
  /** 领到了、还没开始发的（id → 那条）。开始发、放回去之前先从这里拿掉，所以每条只处理一次 */
  waiting: Map<string, NotificationItem>;
  /** worker 要被关掉时放回去的那几条（这一批做完之前要等它们） */
  releases: Promise<void>[];
}

/** 这个 worker 里正在处理的每一批（beforeunload 时要处理） */
const ROUNDS = new Set<Round>();

/**
 * 领到了、但不发的那条放回队列（release_notification：sending → queued，不算失败、attempts 不变，下一次马上再领）。
 * 回 false = 已经不是「发送中」（被别人处理了），不用管。叫不到（数据库出错）→ 退回旧的做法：
 * 标 failed + 重试（2 分钟后再领），不然会卡在「发送中」10 分钟、之后还算失败一次。
 */
async function release(round: Round, item: NotificationItem & { channel: Channel }): Promise<void> {
  round.s.deferred++;
  try {
    await rpc<boolean>(round.admin, "release_notification", { p_id: item.id });
    return;
  } catch (e) {
    log("warn", "release_notification_failed", { notification_id: item.id, error: errorMessage(e) });
  }
  if (!(await complete(round.admin, item.id, failed(item.channel, BUDGET_EXCEEDED, true), round.stopAt))) {
    round.s.errors++;
  }
}

/** worker 要被关掉：每一批领到了、还没开始发的马上放回队列（不等正在发的那几条发完）。没渠道的照样标 skipped（不用发） */
export function releaseWaiting(): void {
  for (const round of ROUNDS) {
    for (const item of [...round.waiting.values()]) {
      if (item.channel === null) continue;
      round.waiting.delete(item.id);
      round.releases.push(release(round, { ...item, channel: item.channel }));
    }
  }
}

export async function dispatch(): Promise<Summary> {
  const started = Date.now();
  const budgetMs = intEnv("DISPATCH_TIME_BUDGET_MS", 100_000, 1_000, 380_000);
  const deadline = dispatchDeadline(started, budgetMs, intEnv("WORKER_WALL_CLOCK_MS", 150_000, 60_000, 400_000));
  const stopAt = deadline + DISPATCH_TIMING.completeGraceMs;
  // worker 要被关掉了：当作时间用完（不再领、不再开始发；已经发的照样记结果）
  const timeLeft = () => (worker.stopping ? -Infinity : deadline - Date.now());
  const s: Summary = {
    ok: true,
    rounds: 0,
    claimed: 0,
    sent: 0,
    failed: 0,
    retry_scheduled: 0,
    skipped: 0,
    tokens_removed: 0,
    deferred: 0,
    errors: 0,
    duration_ms: 0,
  };
  const admin = adminClient();
  const services: Services = { fcm: fcmServiceAccount(), whatsapp: whatsappConfig(), deadline };

  // 领之前就要留够一个请求的时间（领到了发不了还要放回去）
  while (timeLeft() >= DISPATCH_TIMING.itemMinMs) {
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
    const items: NotificationItem[] = [];
    for (const r of raw) {
      const item = toItem(r);
      if (item) items.push(item);
      else {
        s.errors++;
        log("error", "invalid_claimed_item", {});
      }
    }
    const round: Round = { admin, stopAt, s, waiting: new Map(items.map((i) => [i.id, i])), releases: [] };
    ROUNDS.add(round);
    try {
      await mapLimit(items, ITEM_CONCURRENCY, async (item) => {
        if (!round.waiting.delete(item.id)) return; // worker 要被关掉时已经放回去了
        if (item.channel !== null && timeLeft() < DISPATCH_TIMING.itemMinMs) {
          // 时间不够了：不开始发（发到一半被平台杀掉，就不知道发出去没有），放回队列
          await release(round, { ...item, channel: item.channel });
          return;
        }
        const o = await processItem(item, services);
        o.deadTokens.forEach((t) => dead.add(t));
        if (o.status === "sent") s.sent++;
        else if (o.status === "skipped") s.skipped++;
        else if (o.retry) s.retry_scheduled++;
        else s.failed++;
        if (!(await complete(admin, item.id, o, stopAt))) s.errors++;
      });
      await Promise.all(round.releases);
    } finally {
      ROUNDS.delete(round);
    }

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
    // 有放回去的（时间不够）也停：那几条留给下一次叫，不要在这次马上又领回来。
    if (raw.length < CLAIM_LIMIT || s.deferred > 0) break;
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
