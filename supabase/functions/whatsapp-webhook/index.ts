// whatsapp-webhook：Meta 的 WhatsApp webhook（config.toml 里 verify_jwt = false，Meta 不会带 Supabase 的钥匙）。
//   GET  验证握手：hub.verify_token 对（WHATSAPP_VERIFY_TOKEN）→ 原样回 hub.challenge（纯文字 200），不对 403
//   POST 先验 X-Hub-Signature-256（WHATSAPP_APP_SECRET，用原始 body 算 HMAC），不对 401，验过才 JSON.parse
//        一次可能很多笔（entry[] / changes[] / messages[] / statuses[]），全部照顺序处理：
//          按钮 → handle_whatsapp_button → 回一句普通文字（Meta 重送的 duplicate 不回）
//          其他消息 → record_whatsapp_message（只记录，第六步再处理）
//          送达状态 → update_whatsapp_status
//        数据库的写入（会去重）做完才回 200；回复文字交给 EdgeRuntime.waitUntil 在背景发。
//        数据库暂时有问题 → 回 500，Meta 会重送（已经处理过的会变 duplicate，重送是安全的）。

import { whatsappAppSecret, whatsappConfig, whatsappVerifyToken } from "../_shared/env.ts";
import { errorMessage, json, log, runInBackground, text, timingSafeEqual } from "../_shared/http.ts";
import { buttonReplyText, toLocale } from "../_shared/messages.ts";
import { adminClient, DbError, rpc } from "../_shared/supabase.ts";
import { parseWebhook, type Recipient, sendText, verifySignature, type WebhookEvent } from "../_shared/whatsapp.ts";

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
  const raw = new Uint8Array(await req.arrayBuffer()); // 原始 bytes：签名要算在这上面
  if (!(await verifySignature(raw, req.headers.get("x-hub-signature-256"), secret))) {
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
  const counts = { buttons: 0, messages: 0, statuses: 0, duplicates: 0, dropped: 0 };
  let retryLater = false;

  for (const ev of events) {
    try {
      await handleEvent(admin, ev, replies, counts);
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

  const sending = sendReplies(replies);
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
    if (res?.result === "duplicate") counts.duplicates++;
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

export default { fetch: handler };
