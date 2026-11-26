// create-payment：App / 客服后台按「付款」。开一张付款单，去网关（HitPay）开付款页，回传网址（App 用浏览器打开）。
//   supabase.functions.invoke('create-payment', body: {purpose, target_id, months?})（自动带用户 JWT）
//   purpose = subscription（target_id = 店 id，months 1–12）| listing_fee（批发商 id）| commission_invoice（账单 id）
// config.toml 里 verify_jwt = false；这里自己验 auth.getUser(jwt)。金额由数据库算（create_payment_intent），App 送的不算数。
// 同样的东西、付款页还有效 → 拿回同一个网址（不会在网关重复开单）。
// 回应：200 {payment_id, checkout_url, amount_sen, expires_at, reuse}；400 INVALID_REQUEST；401 UNAUTHORIZED；
//       403 NOT_ALLOWED；404 NOT_FOUND；409 NOTHING_DUE / FOUNDING_FULL；429 TOO_MANY_PAYMENTS；
//       502 GATEWAY_REJECTED / GATEWAY_BAD_RESPONSE；
//       503 PAYMENT_NOT_CONFIGURED（没设 HITPAY_API_KEY）/ GATEWAY_UNAVAILABLE / GATEWAY_AUTH_FAILED / QUOTA_UNAVAILABLE；
//       500 CONFIG_MISSING / INTERNAL_ERROR

import type { SupabaseClient } from "@supabase/supabase-js";
import { paymentConfig, type SupabaseEnv, supabaseEnv } from "../_shared/env.ts";
import { bearerToken, CORS_HEADERS, errorMessage, json, log, UUID_RE } from "../_shared/http.ts";
import { createCheckout } from "../_shared/payments.ts";
import { adminClient, authUnavailable, rpc } from "../_shared/supabase.ts";

const PURPOSES = new Set(["subscription", "listing_fee", "commission_invoice"]);

const RESULT_STATUS: Record<string, [number, string]> = {
  not_found: [404, "NOT_FOUND"],
  not_allowed: [403, "NOT_ALLOWED"],
  invalid: [400, "INVALID_REQUEST"],
  nothing_due: [409, "NOTHING_DUE"],
  founding_full: [409, "FOUNDING_FULL"],
  too_many: [429, "TOO_MANY_PAYMENTS"],
};

const withCors = (res: Response): Response => {
  for (const [k, v] of Object.entries(CORS_HEADERS)) res.headers.set(k, v);
  return res;
};

interface Payment {
  id: string;
  amount_sen: number;
  description: string | null;
  checkout_url: string | null;
  expires_at: string | null;
  shop_id: string | null;
  wholesaler_id: string | null;
}

/** 网关页显示的名字：店名 / 批发商名（不送电话、电邮） */
async function payerName(admin: SupabaseClient, p: Payment): Promise<string | null> {
  const [table, id] = p.shop_id ? ["shops", p.shop_id] : ["wholesalers", p.wholesaler_id];
  if (!id) return null;
  const { data } = await admin.from(table).select("name").eq("id", id).maybeSingle();
  return typeof data?.name === "string" ? data.name : null;
}

export async function handler(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return withCors(new Response(null, { status: 204 }));
  if (req.method !== "POST") return withCors(json({ error: "METHOD_NOT_ALLOWED" }, 405));
  const jwt = bearerToken(req);
  if (!jwt) return withCors(json({ error: "UNAUTHORIZED" }, 401));

  let env: SupabaseEnv;
  let admin: SupabaseClient;
  try {
    env = supabaseEnv();
    admin = adminClient(env);
  } catch (e) {
    log("error", "create_payment_not_configured", { error: errorMessage(e) });
    return withCors(json({ error: "CONFIG_MISSING" }, 500));
  }

  try {
    const { data: auth, error: authError } = await admin.auth.getUser(jwt);
    if (authError && authUnavailable(authError)) {
      return withCors(json({ error: "QUOTA_UNAVAILABLE", cause: "AUTH" }, 503));
    }
    if (authError || !auth?.user) return withCors(json({ error: "UNAUTHORIZED" }, 401));

    const body = await req.json().catch(() => null) as Record<string, unknown> | null;
    const purpose = typeof body?.purpose === "string" ? body.purpose : "";
    const targetId = typeof body?.target_id === "string" ? body.target_id.trim().toLowerCase() : "";
    const months = body?.months == null ? 1 : body.months;
    if (!PURPOSES.has(purpose) || !UUID_RE.test(targetId) || !Number.isInteger(months)) {
      return withCors(json({ error: "INVALID_REQUEST" }, 400));
    }

    const cfg = paymentConfig();
    if (!cfg) {
      log("warn", "payment_not_configured", { purpose });
      return withCors(json({ error: "PAYMENT_NOT_CONFIGURED" }, 503));
    }

    let r: { result?: string; reuse?: boolean; payment?: Payment };
    try {
      r = await rpc<typeof r>(admin, "create_payment_intent", {
        p_user_id: auth.user.id,
        p_purpose: purpose,
        p_target_id: targetId,
        p_months: months,
        p_gateway: cfg.gateway,
      }) ?? {};
    } catch (e) {
      log("error", "payment_intent_failed", { error: errorMessage(e) });
      return withCors(json({ error: "QUOTA_UNAVAILABLE" }, 503));
    }
    if (r.result !== "ok" || !r.payment) {
      const [status, code] = RESULT_STATUS[r.result ?? ""] ?? [503, "QUOTA_UNAVAILABLE"];
      return withCors(json({ error: code }, status));
    }
    const p = r.payment;
    const done = (url: string, reuse: boolean) =>
      withCors(
        json({ payment_id: p.id, checkout_url: url, amount_sen: p.amount_sen, expires_at: p.expires_at, reuse }),
      );
    if (r.reuse && p.checkout_url) return done(p.checkout_url, true);

    const out = await createCheckout(cfg, {
      paymentId: p.id,
      amountSen: p.amount_sen,
      description: p.description ?? purpose,
      name: await payerName(admin, p).catch(() => null),
    });
    if (!out.ok) {
      log("warn", "payment_gateway_failed", { payment_id: p.id, code: out.code, status: out.status });
      await rpc(admin, "fail_payment", { p_payment_id: p.id, p_reason: out.code }).catch(() => {});
      const status = out.code === "GATEWAY_REJECTED" || out.code === "GATEWAY_BAD_RESPONSE" ? 502 : 503;
      return withCors(json({ error: out.code }, status));
    }
    await rpc(admin, "attach_payment_checkout", {
      p_payment_id: p.id,
      p_gateway_ref: out.ref,
      p_checkout_url: out.url,
    });
    log("info", "payment_created", { payment_id: p.id, purpose, amount_sen: p.amount_sen });
    return done(out.url, false);
  } catch (e) {
    log("error", "create_payment_error", { error: errorMessage(e) });
    return withCors(json({ error: "INTERNAL_ERROR" }, 500));
  }
}

export default { fetch: handler };
