// 付款网关：HitPay（马来西亚：FPX 网银、DuitNow QR、Touch 'n Go、GrabPay、ShopeePay、Boost、卡）。
// 选它的原因和资料来源：docs/07-billing.md。
//   开单：POST {base}/payment-requests（form-urlencoded，X-BUSINESS-API-KEY），回 {id, url}；url 是网关的付款页
//   通知：Dashboard 设的 webhook（payment_request.completed）；Hitpay-Signature = HMAC-SHA256(salt, 原始 body) 的 hex
// 金额都用仙（整数）；送去网关时才变成 "50.00"。不送 payment_methods：网关页显示这个商户开了的全部方法。
// 不送老板的电话 / 电邮（网关页让他自己填，要的话）。

import type { PaymentGatewayConfig } from "./env.ts";
import { requestTimeoutMs, timingSafeEqual } from "./http.ts";
import { hmacSha256Hex } from "./whatsapp.ts";

export type PaymentMethod = "fpx" | "duitnow" | "ewallet" | "card" | "other";

/** 仙 → "50.00" */
export function senToAmount(sen: number): string {
  if (!Number.isInteger(sen) || sen <= 0) throw new RangeError("amount");
  return `${Math.floor(sen / 100)}.${String(sen % 100).padStart(2, "0")}`;
}

/** "50.00" / "50" / 50 / 50.5 → 仙。格式不对 → null（不用浮点数乘，免得 0.1 + 0.2 那种误差） */
export function amountToSen(v: unknown): number | null {
  const s = typeof v === "number" ? (Number.isFinite(v) ? v.toFixed(2) : "") : typeof v === "string" ? v.trim() : "";
  const m = /^(\d{1,9})(?:\.(\d{1,2}))?$/.exec(s);
  if (!m) return null;
  return Number(m[1]) * 100 + Number((m[2] ?? "").padEnd(2, "0"));
}

/** 网关的 payment_type → 数据库的 payment_method */
export function methodOf(type: unknown): PaymentMethod {
  const t = typeof type === "string" ? type.toLowerCase() : "";
  if (t.includes("fpx")) return "fpx";
  if (t.includes("duitnow")) return "duitnow";
  if (/touch_n_go|tng|grabpay|grab_pay|shopee|boost|wallet|alipay|wechat/.test(t)) return "ewallet";
  if (/card|visa|master|amex|apple_pay|google_pay/.test(t)) return "card";
  return "other";
}

export interface CheckoutRequest {
  paymentId: string;
  amountSen: number;
  description: string;
  /** 付款人名字（店名 / 批发商名，网关页显示） */
  name?: string | null;
}

export type CheckoutResult =
  | { ok: true; ref: string; url: string }
  | {
    ok: false;
    code: "GATEWAY_UNAVAILABLE" | "GATEWAY_AUTH_FAILED" | "GATEWAY_REJECTED" | "GATEWAY_BAD_RESPONSE";
    status?: number;
  };

/** 在网关开一张付款单。reference_number = 我们的付款单 id（webhook 用它对回来） */
export async function createCheckout(
  cfg: PaymentGatewayConfig,
  req: CheckoutRequest,
  deadline?: number,
): Promise<CheckoutResult> {
  const form = new URLSearchParams();
  form.set("amount", senToAmount(req.amountSen));
  form.set("currency", "MYR");
  form.set("reference_number", req.paymentId);
  form.set("purpose", req.description.slice(0, 255));
  if (req.name) form.set("name", req.name.slice(0, 100));
  if (cfg.returnUrl) {
    const u = new URL(cfg.returnUrl);
    u.searchParams.set("payment_id", req.paymentId);
    form.set("redirect_url", u.toString());
  }
  let res: Response;
  try {
    res = await fetch(`${cfg.baseUrl}/payment-requests`, {
      method: "POST",
      headers: {
        "X-BUSINESS-API-KEY": cfg.apiKey,
        "X-Requested-With": "XMLHttpRequest",
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json",
      },
      body: form.toString(),
      signal: AbortSignal.timeout(requestTimeoutMs(deadline)),
    });
  } catch {
    return { ok: false, code: "GATEWAY_UNAVAILABLE" };
  }
  if (res.status === 401 || res.status === 403) {
    await res.body?.cancel();
    return { ok: false, code: "GATEWAY_AUTH_FAILED", status: res.status };
  }
  if (res.status === 429 || res.status >= 500) {
    await res.body?.cancel();
    return { ok: false, code: "GATEWAY_UNAVAILABLE", status: res.status };
  }
  if (!res.ok) {
    await res.body?.cancel();
    return { ok: false, code: "GATEWAY_REJECTED", status: res.status };
  }
  const body = await res.json().catch(() => null) as { id?: unknown; url?: unknown } | null;
  const ref = typeof body?.id === "string" ? body.id.trim() : "";
  const url = typeof body?.url === "string" ? body.url.trim() : "";
  if (!ref || ref.length > 100 || !/^https:\/\/\S+$/.test(url)) return { ok: false, code: "GATEWAY_BAD_RESPONSE" };
  return { ok: true, ref, url };
}

/** webhook 签名：Hitpay-Signature = HMAC-SHA256(salt, 原始 body)，hex。一定要用原始 bytes 算 */
export async function verifyWebhook(raw: Uint8Array, header: string | null, salt: string): Promise<boolean> {
  if (!header || !salt) return false;
  const sig = header.trim().toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(sig)) return false;
  return timingSafeEqual(await hmacSha256Hex(salt, raw), sig);
}

export interface WebhookEvent {
  /** 我们的付款单 id（reference_number） */
  paymentId: string;
  /** 网关的单号 */
  ref: string;
  status: "paid" | "failed" | "pending";
  amountSen: number | null;
  currency: string | null;
  method: PaymentMethod;
  /** 存进 payments.raw 的（不放老板的电邮 / 电话） */
  raw: Record<string, unknown>;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** 看懂 payment_request 的通知。不是我们开的单（没有 reference_number）→ null */
export function parseWebhook(body: unknown): WebhookEvent | null {
  if (!body || typeof body !== "object") return null;
  const b = body as Record<string, unknown>;
  const paymentId = typeof b.reference_number === "string" ? b.reference_number.trim().toLowerCase() : "";
  const ref = typeof b.id === "string" ? b.id.trim() : "";
  if (!UUID.test(paymentId) || !ref) return null;
  const st = typeof b.status === "string" ? b.status.toLowerCase() : "";
  const payments = Array.isArray(b.payments) ? b.payments.filter((p) => p && typeof p === "object") : [];
  const ok = payments.find((p) => /^(succeeded|completed)$/i.test(String((p as Record<string, unknown>).status ?? "")));
  const status: WebhookEvent["status"] = st === "completed" || (st !== "failed" && ok)
    ? "paid"
    : /^(failed|expired|canceled|cancelled)$/.test(st)
    ? "failed"
    : "pending";
  const pay = (ok ?? payments[0] ?? {}) as Record<string, unknown>;
  return {
    paymentId,
    ref,
    status,
    amountSen: amountToSen(b.amount),
    currency: typeof b.currency === "string" ? b.currency.toUpperCase() : null,
    method: methodOf(pay.payment_type),
    raw: {
      id: ref,
      status: st,
      amount: b.amount ?? null,
      currency: b.currency ?? null,
      payments: payments.map((p) => {
        const x = p as Record<string, unknown>;
        return {
          id: x.id ?? null,
          status: x.status ?? null,
          payment_type: x.payment_type ?? null,
          amount: x.amount ?? null,
        };
      }),
    },
  };
}
