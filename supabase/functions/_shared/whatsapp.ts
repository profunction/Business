// WhatsApp Business Platform（Cloud API）：发模板 / 文字、验 webhook 签名、解析 webhook、错误分类。
// 查证结果见 docs/04-research.md 第 1 节和 docs/research/step4/whatsapp.json（以 verifications.json 的更正为准）。

import type { WhatsAppConfig } from "./env.ts";
import type { TemplateMessage } from "./messages.ts";
import { timingSafeEqual } from "./http.ts";

const GRAPH = "https://graph.facebook.com";

// ---------------------------------------------------------------------------
// 号码
// ---------------------------------------------------------------------------

/** 跟数据库的 normalize_phone 一样：只留数字，0 开头补 6（马来西亚）。 */
export function normalizePhone(phone: string | null | undefined): string | null {
  const digits = (phone ?? "").replace(/\D/g, "");
  if (!digits) return null;
  return digits.startsWith("0") ? `6${digits}` : digits;
}

/** 发送时一定要加 +（不加的话 Meta 会当成我们号码的国家） */
export function toE164(phone: string): string | null {
  const n = normalizePhone(phone);
  return n ? `+${n}` : null;
}

// ---------------------------------------------------------------------------
// 发送
// ---------------------------------------------------------------------------

export type Recipient = { phone: string } | { userId: string };

export type SendResult =
  | { ok: true; messageId: string; messageStatus: string | null }
  | {
    ok: false;
    httpStatus: number;
    code: number | null;
    message: string;
    /** 等一下再试可能会好（限速、Meta 暂时有问题、网络） */
    retryable: boolean;
    /** 要通知技术人员（token 过期、付款、账号被限制、模板问题……） */
    alert: boolean;
  };

/** 不重试：等对方处理（131026）、我们的请求本身错、模板问题 */
const NOT_RETRYABLE = new Set([
  131026, // 收不到（不是 WhatsApp 号码 / 没接受新条款 / 版本太旧）：要对方处理，不自动重试
  131047, // 超过 24 小时窗口（普通文字发不出去，要改用模板）
  131050, // 对方不收营销消息
  130403, // 我们封锁了对方
  131021, // 收件人是自己
  131051, // 不支持的消息类型
  131008, // 少了参数
  131009, // 参数值不对
  100, // 参数错误
  132000, // 参数数量不对
  132001, // 模板不存在这个语言 / 没批准
  132005, // 模板内文太长
  132007, // 模板内容违规
  132012, // 参数格式不对
  132015, // 模板暂停（品质太差）
  132016, // 模板永久停用
  132068,
  132069,
  131062,
]);

/** 重试：限速、暂时不能用、未知错误 */
const RETRYABLE = new Set([130429, 131056, 80007, 4, 131048, 131016, 133004, 131000, 1, 2]);

/** 要通知技术：token / 权限 / 付款 / 账号 / 号码 / 模板问题 */
const ALERT = new Set([
  190,
  0,
  3,
  10,
  131042,
  131031,
  368,
  131045,
  133010,
  131057,
  131064,
  132001,
  132005,
  132007,
  132012,
  132015,
  132016,
  132000,
  100,
]);

/**
 * WhatsApp 错误分类。
 * 我们自己的设定问题（token 过期 190、权限、付款 131042、账号被限制）→ 重试（修好后会自动补发，
 * 最多 5 次、2/4/8/16 分钟）并通知技术；对方的问题或请求本身错 → 不重试。
 */
export function classifyWhatsAppError(code: number | null, httpStatus: number): { retryable: boolean; alert: boolean } {
  const alert = (code != null && (ALERT.has(code) || (code >= 200 && code <= 299))) || httpStatus === 401;
  if (code != null) {
    if (NOT_RETRYABLE.has(code)) return { retryable: false, alert };
    if (RETRYABLE.has(code)) return { retryable: true, alert };
    if (alert) return { retryable: true, alert };
  }
  if (httpStatus === 0 || httpStatus === 429 || httpStatus >= 500) return { retryable: true, alert };
  if (httpStatus === 401 || httpStatus === 403) return { retryable: true, alert: true };
  return { retryable: false, alert };
}

async function postMessage(
  cfg: WhatsAppConfig,
  body: Record<string, unknown>,
  phoneNumberId?: string,
): Promise<SendResult> {
  const url = `${GRAPH}/${cfg.graphVersion}/${phoneNumberId ?? cfg.phoneNumberId}/messages`;
  let res: Response;
  try {
    res = await fetch(url, {
      method: "POST",
      headers: { "Authorization": `Bearer ${cfg.token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ messaging_product: "whatsapp", recipient_type: "individual", ...body }),
      signal: AbortSignal.timeout(15_000),
    });
  } catch (e) {
    return {
      ok: false,
      httpStatus: 0,
      code: null,
      message: `NETWORK: ${e instanceof Error ? e.message : e}`,
      retryable: true,
      alert: false,
    };
  }
  const data = await res.json().catch(() => null) as Record<string, unknown> | null;
  if (res.ok) {
    const msg = Array.isArray(data?.messages) ? (data!.messages as Record<string, unknown>[])[0] : null;
    const id = typeof msg?.id === "string" ? msg.id : null;
    if (id) {
      return {
        ok: true,
        messageId: id,
        messageStatus: typeof msg?.message_status === "string" ? msg.message_status : null,
      };
    }
    return { ok: false, httpStatus: res.status, code: null, message: "NO_MESSAGE_ID", retryable: true, alert: false };
  }
  const err = (data?.error ?? {}) as Record<string, unknown>;
  const code = typeof err.code === "number" ? err.code : Number.isInteger(Number(err.code)) ? Number(err.code) : null;
  const details = (err.error_data as Record<string, unknown> | undefined)?.details;
  const message = [err.message, details].filter((x) => typeof x === "string" && x).join(" | ") || `HTTP ${res.status}`;
  return {
    ok: false,
    httpStatus: res.status,
    code,
    message: message.slice(0, 300),
    ...classifyWhatsAppError(code, res.status),
  };
}

function recipientFields(to: Recipient): Record<string, string> | null {
  if ("phone" in to) {
    const e164 = toE164(to.phone);
    return e164 ? { to: e164 } : null;
  }
  // 2026 年起：用户只有 BSUID（没有电话）时用 recipient
  return to.userId ? { recipient: to.userId } : null;
}

/** 发审核过的模板（具名参数 + quick reply 按钮 payload） */
export function sendTemplate(cfg: WhatsAppConfig, phone: string, t: TemplateMessage): Promise<SendResult> {
  const to = recipientFields({ phone });
  if (!to) return Promise.resolve(invalidRecipient());
  const components: Record<string, unknown>[] = [{
    type: "body",
    parameters: Object.entries(t.params).map(([name, value]) => ({ type: "text", parameter_name: name, text: value })),
  }];
  for (const b of t.buttons) {
    components.push({
      type: "button",
      sub_type: "quick_reply",
      index: String(b.index),
      parameters: [{ type: "payload", payload: b.payload }],
    });
  }
  return postMessage(cfg, {
    ...to,
    type: "template",
    template: { name: t.name, language: { code: t.languageCode }, components },
  });
}

/** 普通文字（只能在对方 24 小时内发过消息的窗口里发） */
export function sendText(
  cfg: WhatsAppConfig,
  to: Recipient,
  text: string,
  opts: { replyTo?: string | null; phoneNumberId?: string | null } = {},
): Promise<SendResult> {
  const r = recipientFields(to);
  if (!r) return Promise.resolve(invalidRecipient());
  return postMessage(cfg, {
    ...r,
    ...(opts.replyTo ? { context: { message_id: opts.replyTo } } : {}),
    type: "text",
    text: { preview_url: false, body: text },
  }, opts.phoneNumberId ?? undefined);
}

function invalidRecipient(): SendResult {
  return { ok: false, httpStatus: 0, code: null, message: "INVALID_RECIPIENT", retryable: false, alert: false };
}

// ---------------------------------------------------------------------------
// webhook 签名：X-Hub-Signature-256: sha256=<hex>，HMAC-SHA256(App Secret, 原始 body)
// ---------------------------------------------------------------------------

function hex(buf: ArrayBuffer): string {
  return Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, "0")).join("");
}

export async function hmacSha256Hex(secret: string, data: Uint8Array): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return hex(await crypto.subtle.sign("HMAC", key, data as Uint8Array<ArrayBuffer>));
}

/** 一定要用收到的原始 bytes 算（JSON.parse 再 stringify 会变） */
export async function verifySignature(raw: Uint8Array, header: string | null, appSecret: string): Promise<boolean> {
  if (!header || !appSecret) return false;
  const m = /^sha256=([0-9a-fA-F]{64})$/.exec(header.trim());
  if (!m) return false;
  const expected = await hmacSha256Hex(appSecret, raw);
  return timingSafeEqual(expected, m[1].toLowerCase());
}

// ---------------------------------------------------------------------------
// webhook 内容：entry[] → changes[] → value.messages[] / value.statuses[]（可能一次很多笔）
// ---------------------------------------------------------------------------

export type InboundType = "text" | "audio" | "image" | "document" | "other";

export type WebhookEvent =
  | {
    kind: "button";
    id: string;
    /** 用户电话（纯数字，没有 +）。用户只有用户名时可能没有 */
    from: string | null;
    /** BSUID（例如 MY.1349...） */
    fromUserId: string | null;
    /** 按钮所在的那条消息（我们发的 wamid） */
    contextId: string | null;
    payload: string;
    text: string | null;
    phoneNumberId: string | null;
    raw: Record<string, unknown>;
  }
  | {
    kind: "message";
    id: string;
    from: string | null;
    fromUserId: string | null;
    type: InboundType;
    body: string | null;
    mediaId: string | null;
    phoneNumberId: string | null;
    raw: Record<string, unknown>;
  }
  | {
    kind: "status";
    id: string;
    status: string;
    recipientId: string | null;
    errorCode: number | null;
    error: string | null;
    raw: Record<string, unknown>;
  };

type Obj = Record<string, unknown>;

function obj(v: unknown): Obj | null {
  return v && typeof v === "object" && !Array.isArray(v) ? v as Obj : null;
}

function arr(v: unknown): Obj[] {
  return Array.isArray(v) ? v.map(obj).filter((x): x is Obj => x !== null) : [];
}

function s(v: unknown): string | null {
  return typeof v === "string" && v.trim() !== "" ? v : null;
}

function parseMessage(m: Obj, phoneNumberId: string | null): WebhookEvent | null {
  const id = s(m.id);
  if (!id) return null;
  const from = s(m.from);
  const fromUserId = s(m.from_user_id);
  const type = s(m.type) ?? "unknown";
  const contextId = s(obj(m.context)?.id);

  if (type === "button") {
    const b = obj(m.button) ?? {};
    return {
      kind: "button",
      id,
      from,
      fromUserId,
      contextId,
      payload: s(b.payload) ?? s(b.text) ?? "",
      text: s(b.text),
      phoneNumberId,
      raw: m,
    };
  }
  if (type === "interactive") {
    // 普通（非模板）互动按钮：button_reply.id 就是 payload
    const i = obj(m.interactive) ?? {};
    const reply = obj(i.button_reply);
    if (reply) {
      return {
        kind: "button",
        id,
        from,
        fromUserId,
        contextId,
        payload: s(reply.id) ?? "",
        text: s(reply.title),
        phoneNumberId,
        raw: m,
      };
    }
  }

  let t: InboundType = "other";
  let body: string | null = null;
  let mediaId: string | null = null;
  if (type === "text") {
    t = "text";
    body = s(obj(m.text)?.body);
  } else if (type === "audio") {
    t = "audio";
    mediaId = s(obj(m.audio)?.id);
  } else if (type === "image") {
    t = "image";
    mediaId = s(obj(m.image)?.id);
    body = s(obj(m.image)?.caption);
  } else if (type === "document") {
    t = "document";
    mediaId = s(obj(m.document)?.id);
    body = s(obj(m.document)?.caption) ?? s(obj(m.document)?.filename);
  } else if (type === "interactive") {
    const list = obj(obj(m.interactive)?.list_reply);
    body = s(list?.title) ?? s(list?.id);
  } else if (type === "reaction") {
    body = s(obj(m.reaction)?.emoji);
  } else if (type === "system") {
    body = s(obj(m.system)?.body);
  } else {
    const media = obj(m[type]);
    mediaId = s(media?.id);
    body = s(media?.caption);
  }
  return { kind: "message", id, from, fromUserId, type: t, body, mediaId, phoneNumberId, raw: m };
}

function parseStatus(st: Obj): WebhookEvent | null {
  const id = s(st.id);
  const status = s(st.status);
  if (!id || !status) return null;
  const e = arr(st.errors)[0] ?? null;
  const codeNum = e ? Number(e.code) : NaN;
  const details = s(obj(e?.error_data)?.details);
  const errText = e ? [s(e.title) ?? s(e.message), details].filter(Boolean).join(": ") : "";
  return {
    kind: "status",
    id,
    status: status.toLowerCase(),
    recipientId: s(st.recipient_id),
    errorCode: Number.isInteger(codeNum) ? codeNum : null,
    error: errText ? errText.slice(0, 300) : null,
    raw: st,
  };
}

/** 把整个 webhook 拆成一笔一笔（照原本的顺序）。不是 WhatsApp 的 → []。 */
export function parseWebhook(body: unknown): WebhookEvent[] {
  const root = obj(body);
  if (!root || root.object !== "whatsapp_business_account") return [];
  const out: WebhookEvent[] = [];
  for (const entry of arr(root.entry)) {
    for (const change of arr(entry.changes)) {
      if (change.field !== undefined && change.field !== "messages") continue;
      const value = obj(change.value);
      if (!value) continue;
      const phoneNumberId = s(obj(value.metadata)?.phone_number_id);
      for (const m of arr(value.messages)) {
        const ev = parseMessage(m, phoneNumberId);
        if (ev) out.push(ev);
      }
      for (const st of arr(value.statuses)) {
        const ev = parseStatus(st);
        if (ev) out.push(ev);
      }
    }
  }
  return out;
}
