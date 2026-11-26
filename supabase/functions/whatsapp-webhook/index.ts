// whatsapp-webhook：Meta 的 WhatsApp webhook（config.toml 里 verify_jwt = false，Meta 不会带 Supabase 的钥匙）。
//   GET  验证握手：hub.verify_token 对（WHATSAPP_VERIFY_TOKEN）→ 原样回 hub.challenge（纯文字 200），不对 403
//   POST 先验 X-Hub-Signature-256（WHATSAPP_APP_SECRET，用原始 body 算 HMAC），不对 401，验过才 JSON.parse
//        验之前：没有签名 / 格式不对 → 直接 401（不读 body）；body 最多 MAX_WEBHOOK_BODY_BYTES（Meta 最多 3 MB），
//        超过 → 413（Content-Length 写超过就不读；没写就边读边数）——公开的端点，不能让人用大 body 塞爆 worker 记忆体
//        一次可能很多笔（entry[] / changes[] / messages[] / statuses[]），全部照顺序处理：
//          按钮 → handle_whatsapp_button → 回一句普通文字（Meta 重送的 duplicate 不回）
//          其他消息 → record_whatsapp_message（记录）→ 第六步：reserve_whatsapp_order 决定要不要做成订单草稿：
//            注册过的店发文字 / 语音 → 背景：（语音先从 Graph 下载、存到 voice-orders、转文字）→ Claude → 草稿，
//              进客服后台的「WhatsApp 订单」，然后回一句「收到，客服确认后帮您下单」（店的语言）；
//            不认识的号码 → 「请先注册」（24 小时内第一条才回）；照片 / 文件 → 「请用文字或语音」；批发商的号码不处理
//          送达状态 → update_whatsapp_status
//        数据库的写入（会去重）做完才回 200；回复文字交给 EdgeRuntime.waitUntil 在背景发。
//        数据库暂时有问题 → 回 500，Meta 会重送（已经处理过的会变 duplicate，重送是安全的）。

import { anthropicApiKey, sttConfig, whatsappAppSecret, whatsappConfig, whatsappVerifyToken } from "../_shared/env.ts";
import {
  BodyTooLargeError,
  errorMessage,
  json,
  log,
  readBodyLimited,
  runInBackground,
  text,
  timingSafeEqual,
} from "../_shared/http.ts";
import { buttonReplyText, orderReplyText, REGISTER_REPLY, toLocale } from "../_shared/messages.ts";
import { adminClient, DbError, rpc } from "../_shared/supabase.ts";
import { sniffAudio } from "../_shared/filetype.ts";
import { makeDraft } from "../_shared/voice_order.ts";
import {
  downloadMedia,
  parseWebhook,
  type Recipient,
  sendText,
  verifySignature,
  type WebhookEvent,
} from "../_shared/whatsapp.ts";

/** Meta 的 webhook 最多 3 MB（docs/research/step4/verifications.json）；留一点余地 */
export const MAX_WEBHOOK_BODY_BYTES = 4 * 1024 * 1024;

/** WhatsApp 语音最多存多大（跟 voice-orders bucket 一样 3 MB；一分钟的语音大约 100 KB） */
export const MAX_VOICE_BYTES = 3 * 1024 * 1024;
/** 背景做草稿最多多久 */
export const ORDER_TIME_BUDGET_MS = 120_000;

const SIGNATURE_RE = /^\s*sha256=[0-9a-fA-F]{64}\s*$/;

/** handle_whatsapp_button 回传的 JSON */
export interface ButtonResult {
  result: string;
  order_no?: string | null;
  status?: string | null;
  locale?: string | null;
}

interface Reply {
  to: Recipient;
  text: string;
  replyTo: string;
  phoneNumberId: string | null;
  result: string;
}

export function handshake(url: URL): Response {
  const expected = whatsappVerifyToken();
  const mode = url.searchParams.get("hub.mode");
  const token = url.searchParams.get("hub.verify_token");
  const challenge = url.searchParams.get("hub.challenge");
  if (expected && mode === "subscribe" && token != null && challenge != null && timingSafeEqual(token, expected)) {
    return text(challenge, 200);
  }
  return text("forbidden", 403);
}

async function sendReplies(replies: Reply[]): Promise<void> {
  if (replies.length === 0) return;
  const cfg = whatsappConfig();
  if (!cfg) {
    log("warn", "whatsapp_reply_skipped", { reason: "WHATSAPP_NOT_CONFIGURED", count: replies.length });
    return;
  }
  for (const r of replies) {
    try {
      const res = await sendText(cfg, r.to, r.text, { replyTo: r.replyTo, phoneNumberId: r.phoneNumberId });
      if (!res.ok) {
        log(res.alert ? "error" : "warn", "whatsapp_reply_failed", {
          result: r.result,
          http: res.httpStatus,
          code: res.code,
          message: res.message,
        });
      }
    } catch (e) {
      log("error", "whatsapp_reply_failed", { result: r.result, error: errorMessage(e) });
    }
  }
}

export async function handler(req: Request): Promise<Response> {
  if (req.method === "GET") return handshake(new URL(req.url));
  if (req.method !== "POST") return text("method not allowed", 405);

  const secret = whatsappAppSecret();
  if (!secret) {
    // 还没设定：回 500 让 Meta 晚一点重送（设好之后就收得到）
    log("error", "whatsapp_webhook_not_configured", { reason: "WHATSAPP_APP_SECRET missing" });
    return json({ error: "WEBHOOK_NOT_CONFIGURED" }, 500);
  }
  const signature = req.headers.get("x-hub-signature-256");
  if (!signature || !SIGNATURE_RE.test(signature)) {
    // 连签名都没有：不用读 body
    await req.body?.cancel().catch(() => {});
    log("warn", "whatsapp_webhook_bad_signature", { reason: "missing_or_malformed" });
    return json({ error: "INVALID_SIGNATURE" }, 401);
  }
  let raw: Uint8Array; // 原始 bytes：签名要算在这上面
  try {
    raw = await readBodyLimited(req, MAX_WEBHOOK_BODY_BYTES);
  } catch (e) {
    if (e instanceof BodyTooLargeError) {
      log("warn", "whatsapp_webhook_body_too_large", { limit: MAX_WEBHOOK_BODY_BYTES });
      return json({ error: "BODY_TOO_LARGE" }, 413);
    }
    log("warn", "whatsapp_webhook_body_unreadable", { error: errorMessage(e) });
    return json({ error: "INVALID_BODY" }, 400);
  }
  if (!(await verifySignature(raw, signature, secret))) {
    log("warn", "whatsapp_webhook_bad_signature", {});
    return json({ error: "INVALID_SIGNATURE" }, 401);
  }
  let body: unknown;
  try {
    body = JSON.parse(new TextDecoder().decode(raw));
  } catch {
    return json({ error: "INVALID_JSON" }, 400);
  }

  const events = parseWebhook(body);
  if (events.length === 0) return json({ ok: true, events: 0 });

  let admin: ReturnType<typeof adminClient>;
  try {
    admin = adminClient();
  } catch (e) {
    log("error", "whatsapp_webhook_not_configured", { reason: errorMessage(e) });
    return json({ error: "WEBHOOK_NOT_CONFIGURED" }, 500);
  }
  const replies: Reply[] = [];
  const jobs: (() => Promise<void>)[] = [];
  const counts = { buttons: 0, messages: 0, statuses: 0, duplicates: 0, dropped: 0, orders: 0 };
  let retryLater = false;

  for (const ev of events) {
    try {
      await handleEvent(admin, ev, replies, counts, jobs);
    } catch (e) {
      if (e instanceof DbError && !e.transient) {
        // 数据本身的问题（重送也一样）：记下来，不要让 Meta 重送 7 天
        counts.dropped++;
        log("error", "whatsapp_event_rejected", { kind: ev.kind, op: e.op, code: e.code, error: e.message });
      } else {
        retryLater = true;
        log("error", "whatsapp_event_failed", { kind: ev.kind, error: errorMessage(e) });
      }
    }
  }

  // 先回答按钮 / 注册的那几句，再做草稿（语音转文字 + AI 要几十秒，Meta 不用等）
  const sending = sendReplies(replies).then(async () => {
    for (const job of jobs) await job();
  });
  if (!runInBackground(sending)) await sending;

  log("info", "whatsapp_webhook_done", {
    events: events.length,
    ...counts,
    replies: replies.length,
    retry: retryLater,
  });
  if (retryLater) return json({ ok: false, retry: true }, 500);
  return json({ ok: true, events: events.length });
}

async function handleEvent(
  admin: ReturnType<typeof adminClient>,
  ev: WebhookEvent,
  replies: Reply[],
  counts: Record<string, number>,
  jobs: (() => Promise<void>)[],
): Promise<void> {
  if (ev.kind === "button") {
    counts.buttons++;
    const res = await rpc<ButtonResult>(admin, "handle_whatsapp_button", {
      p_from: ev.from,
      p_from_user_id: ev.fromUserId,
      p_context_id: ev.contextId,
      p_payload: ev.payload,
      p_wa_message_id: ev.id,
      p_raw: ev.raw,
    });
    const result = typeof res?.result === "string" ? res.result : "";
    if (result === "duplicate") {
      counts.duplicates++;
      return;
    }
    const reply = buttonReplyText(result, res?.order_no ?? null, toLocale(res?.locale));
    const to: Recipient | null = ev.from ? { phone: ev.from } : ev.fromUserId ? { userId: ev.fromUserId } : null;
    if (reply && to) replies.push({ to, text: reply, replyTo: ev.id, phoneNumberId: ev.phoneNumberId, result });
    return;
  }
  if (ev.kind === "message") {
    counts.messages++;
    const res = await rpc<{ result?: string }>(admin, "record_whatsapp_message", {
      p_from: ev.from,
      p_type: ev.type,
      p_body: ev.body,
      p_media_id: ev.mediaId,
      p_wa_message_id: ev.id,
      p_raw: ev.raw,
    });
    if (res?.result === "duplicate") {
      counts.duplicates++;
      return;
    }
    const messageId = (res as { id?: unknown } | null)?.id;
    if (res?.result !== "recorded" || typeof messageId !== "string") return;
    await handleOrderMessage(admin, ev, messageId, replies, counts, jobs);
    return;
  }
  counts.statuses++;
  await rpc(admin, "update_whatsapp_status", {
    p_wa_message_id: ev.id,
    p_status: ev.status,
    p_error_code: ev.errorCode,
    p_error: ev.error,
  });
}

/** reserve_whatsapp_order 回传的 JSON */
export interface IntakeResult {
  result: string;
  reply?: boolean;
  run_id?: string;
  shop_id?: string;
  locale?: string | null;
  message_type?: string;
  body?: string | null;
  media_id?: string | null;
}

async function handleOrderMessage(
  admin: ReturnType<typeof adminClient>,
  ev: Extract<WebhookEvent, { kind: "message" }>,
  messageId: string,
  replies: Reply[],
  counts: Record<string, number>,
  jobs: (() => Promise<void>)[],
): Promise<void> {
  const to: Recipient | null = ev.from ? { phone: ev.from } : ev.fromUserId ? { userId: ev.fromUserId } : null;
  const intake = await rpc<IntakeResult>(admin, "reserve_whatsapp_order", {
    p_message_id: messageId,
    p_run_id: crypto.randomUUID(),
  });
  const locale = toLocale(intake?.locale);
  const reply = (text: string, result: string) => {
    if (to) replies.push({ to, text, replyTo: ev.id, phoneNumberId: ev.phoneNumberId, result });
  };
  switch (intake?.result) {
    case "unknown_sender":
      if (intake.reply) reply(REGISTER_REPLY, "unknown_sender");
      return;
    case "unsupported":
      if (intake.reply) reply(orderReplyText("unsupported", locale), "unsupported");
      return;
    case "ok":
      break;
    default:
      if (intake?.result === "quota") log("warn", "whatsapp_order_quota", { shop_id: intake.shop_id ?? null });
      return;
  }
  const runId = intake.run_id;
  const shopId = intake.shop_id;
  if (!runId || !shopId) return;
  counts.orders++;
  jobs.push(async () => {
    try {
      const deadline = Date.now() + ORDER_TIME_BUDGET_MS;
      const deps = { admin, stt: sttConfig(), anthropicKey: anthropicApiKey(), deadline };
      let out;
      if (intake.message_type === "audio") {
        const cfg = whatsappConfig();
        const media = cfg && intake.media_id
          ? await downloadMedia(cfg, intake.media_id, MAX_VOICE_BYTES, deadline)
          : { ok: false as const, code: cfg ? "MEDIA_NOT_FOUND" : "WHATSAPP_NOT_CONFIGURED", message: "" };
        const audio = media.ok ? sniffAudio(media.bytes) : null;
        let audioPath: string | null = null;
        if (media.ok && audio) {
          audioPath = `${shopId}/${crypto.randomUUID()}.${audio.ext}`;
          const up = await admin.storage.from("voice-orders").upload(audioPath, media.bytes, {
            contentType: audio.mime,
            upsert: false,
          });
          if (up.error) {
            log("warn", "whatsapp_voice_store_failed", { error: up.error.message });
            audioPath = null;
          }
        }
        if (media.ok && audio && audioPath) {
          out = await makeDraft(deps, { runId, shopId }, {
            kind: "audio",
            bytes: media.bytes,
            mime: audio.mime,
            audioPath,
          }, true);
        } else {
          // 拿不到 / 存不了录音：照样放进客服的队列（空的草稿 + 原因），客服自己处理
          const code = !media.ok ? media.code : !audio ? "UNSUPPORTED_AUDIO" : "STORAGE_FAILED";
          out = await rpc<{ draft_id: string }>(admin, "create_order_draft", {
            p_run_id: runId,
            p_transcript: null,
            p_ai_meta: { error_code: code },
          }).then((draft) => ({ ok: true as const, draft: { ...draft, item_count: 0 } }));
        }
      } else {
        out = await makeDraft(deps, { runId, shopId }, { kind: "text", text: intake.body ?? "" }, true);
      }
      if (!out.ok || !to) return;
      const n = out.draft.item_count ?? 0;
      const cfg = whatsappConfig();
      if (!cfg) {
        log("warn", "whatsapp_reply_skipped", { reason: "WHATSAPP_NOT_CONFIGURED", count: 1 });
        return;
      }
      const text = n > 0 ? orderReplyText("received", locale, { n }) : orderReplyText("received_unclear", locale);
      const sent = await sendText(cfg, to, text, { replyTo: ev.id, phoneNumberId: ev.phoneNumberId });
      if (!sent.ok) log("warn", "whatsapp_reply_failed", { result: "order_received", code: sent.code });
    } catch (e) {
      log("error", "whatsapp_order_failed", { error: errorMessage(e) });
      await rpc(admin, "fail_voice_order_run", { p_run_id: runId, p_error_code: "INTERNAL_ERROR" }).catch(() => {});
    }
  });
}

export default { fetch: handler };
