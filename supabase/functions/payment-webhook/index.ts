// payment-webhook：HitPay 叫（Dashboard → Developers → Webhook endpoints，事件 payment_request.completed）。
// config.toml 里 verify_jwt = false；先验 Hitpay-Signature（HMAC-SHA256(HITPAY_SALT, 原始 body)），不对 401，验过才 JSON.parse。
// 已付 → mark_payment_paid（数据库：同一笔只算一次；月费从对的日子延长、锁定价不变；上架费；账单已付）。
// 失败 / 过期 → fail_payment。
// 回应：200 {result}（paid / already_paid / mismatch / not_found / failed / ignored：网关不用再送）；
//       401 BAD_SIGNATURE；413 BODY_TOO_LARGE；400 INVALID_JSON；
//       503 NOT_CONFIGURED（没设 HITPAY_SALT）/ 500 DB_ERROR（网关会再送，数据库那边可以重复）

import type { SupabaseClient } from "@supabase/supabase-js";
import { paymentWebhookSalt, supabaseEnv } from "../_shared/env.ts";
import { BodyTooLargeError, errorMessage, json, log, readBodyLimited } from "../_shared/http.ts";
import { parseWebhook, verifyWebhook } from "../_shared/payments.ts";
import { adminClient, rpc } from "../_shared/supabase.ts";

export const MAX_BODY_BYTES = 64 * 1024;
export const GATEWAY = "hitpay";

export async function handler(req: Request): Promise<Response> {
  if (req.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  const salt = paymentWebhookSalt();
  let admin: SupabaseClient;
  try {
    if (!salt) throw new Error("HITPAY_SALT missing");
    admin = adminClient(supabaseEnv());
  } catch (e) {
    log("error", "payment_webhook_not_configured", { error: errorMessage(e) });
    return json({ error: "NOT_CONFIGURED" }, 503);
  }

  let raw: Uint8Array;
  try {
    raw = await readBodyLimited(req, MAX_BODY_BYTES);
  } catch (e) {
    if (e instanceof BodyTooLargeError) return json({ error: "BODY_TOO_LARGE" }, 413);
    throw e;
  }
  if (!(await verifyWebhook(raw, req.headers.get("hitpay-signature"), salt))) {
    log("warn", "payment_webhook_bad_signature");
    return json({ error: "BAD_SIGNATURE" }, 401);
  }
  let body: unknown;
  try {
    body = JSON.parse(new TextDecoder().decode(raw));
  } catch {
    return json({ error: "INVALID_JSON" }, 400);
  }

  const ev = parseWebhook(body);
  if (!ev) {
    log("info", "payment_webhook_ignored", { reason: "not_ours" });
    return json({ result: "ignored" });
  }
  try {
    if (ev.status === "paid") {
      // 不是令吉：金额对不上（数据库会记下要客服处理）
      const amount = ev.currency === "MYR" ? ev.amountSen : -1;
      const r = await rpc<{ result?: string }>(admin, "mark_payment_paid", {
        p_payment_id: ev.paymentId,
        p_gateway: GATEWAY,
        p_gateway_ref: ev.ref,
        p_amount_sen: amount,
        p_method: ev.method,
        p_raw: ev.raw,
      });
      const result = r?.result ?? "unknown";
      log(result === "paid" || result === "already_paid" ? "info" : "warn", "payment_webhook_paid", {
        payment_id: ev.paymentId,
        result,
      });
      return json({ result });
    }
    if (ev.status === "failed") {
      await rpc(admin, "fail_payment", { p_payment_id: ev.paymentId, p_reason: "GATEWAY_FAILED" });
      return json({ result: "failed" });
    }
    return json({ result: "ignored" });
  } catch (e) {
    log("error", "payment_webhook_db_error", { payment_id: ev.paymentId, error: errorMessage(e) });
    return json({ error: "DB_ERROR" }, 500);
  }
}

export default { fetch: handler };
