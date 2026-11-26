// 第七步：付款（假的 HitPay）。金额格式、开付款页（create-payment）、网关通知（payment-webhook：签名、重复、失败）、收费推送。
import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import {
  amountToSen,
  createCheckout,
  methodOf,
  parseWebhook,
  senToAmount,
  verifyWebhook,
} from "../_shared/payments.ts";
import { HITPAY_URLS, paymentConfig } from "../_shared/env.ts";
import { hmacSha256Hex } from "../_shared/whatsapp.ts";
import { monthLabel, type NotificationItem, pushContent } from "../_shared/messages.ts";
import createPayment from "../create-payment/index.ts";
import paymentWebhook, { MAX_BODY_BYTES } from "../payment-webhook/index.ts";
import { type Call, fakeFetch, isService, pgError, rpcName, SB_URL, setEnv, SUPABASE_ENV } from "./_helpers.ts";

const USER_JWT = "user.jwt.token";
const USER_ID = "aaaaaaaa-0000-4000-8000-000000000001";
const SHOP = "dddddddd-0000-4000-8000-000000000001";
const PAY_ID = "9a9a9a9a-0000-4000-8000-000000000001";
const SALT = "hitpay-salt";
const ENV = {
  ...SUPABASE_ENV,
  HITPAY_API_KEY: "hp-key",
  HITPAY_SALT: SALT,
  HITPAY_ENV: undefined,
  PAYMENT_RETURN_URL: "https://app.example.my/paid",
};

Deno.test("金额：仙 ↔ 网关的字串（不用浮点数乘）", () => {
  assertEquals(senToAmount(5000), "50.00");
  assertEquals(senToAmount(255), "2.55");
  assertEquals(senToAmount(7), "0.07");
  assertEquals(amountToSen("50.00"), 5000);
  assertEquals(amountToSen("2.5"), 250);
  assertEquals(amountToSen("0.29"), 29);
  assertEquals(amountToSen(150), 15000);
  assertEquals(amountToSen(0.1 + 0.2), 30);
  for (const bad of ["", "-1", "1.234", "abc", null, "1e3"]) assertEquals(amountToSen(bad), null, String(bad));
});

Deno.test("付款方法：FPX / DuitNow / 电子钱包 / 卡", () => {
  assertEquals(methodOf("fpx"), "fpx");
  assertEquals(methodOf("duitnow_qr"), "duitnow");
  for (const w of ["touch_n_go", "grabpay", "shopee_pay", "boost"]) assertEquals(methodOf(w), "ewallet", w);
  assertEquals(methodOf("card"), "card");
  assertEquals(methodOf(undefined), "other");
});

Deno.test("设定：没有钥匙 → null；默认 sandbox；回来网址一定要 https", () => {
  let restore = setEnv({ ...ENV, HITPAY_API_KEY: undefined });
  try {
    assertEquals(paymentConfig(), null);
  } finally {
    restore();
  }
  restore = setEnv({ ...ENV, PAYMENT_RETURN_URL: "http://insecure" });
  try {
    const c = paymentConfig()!;
    assertEquals(c.baseUrl, HITPAY_URLS.sandbox);
    assertEquals(c.returnUrl, null);
  } finally {
    restore();
  }
  restore = setEnv({ ...ENV, HITPAY_ENV: "production" });
  try {
    assertEquals(paymentConfig()!.baseUrl, HITPAY_URLS.production);
  } finally {
    restore();
  }
});

Deno.test("网关开单：请求格式；错误分类", async () => {
  const restore = setEnv(ENV);
  let reply: () => Response = () => Response.json({ id: "HP-REQ-1", url: "https://securecheckout.hit-pay.com/x" });
  const seen: Call[] = [];
  const f = fakeFetch((c) => {
    seen.push(c);
    return reply();
  });
  try {
    const cfg = paymentConfig()!;
    const ok = await createCheckout(cfg, {
      paymentId: PAY_ID,
      amountSen: 15000,
      description: "x3",
      name: "阿明茶餐室",
    });
    assertEquals(ok, { ok: true, ref: "HP-REQ-1", url: "https://securecheckout.hit-pay.com/x" });
    const c = seen[0];
    assertEquals(c.url.href, `${HITPAY_URLS.sandbox}/payment-requests`);
    assertEquals(c.headers.get("x-business-api-key"), "hp-key");
    const form = new URLSearchParams(c.text);
    assertEquals(form.get("amount"), "150.00");
    assertEquals(form.get("currency"), "MYR");
    assertEquals(form.get("reference_number"), PAY_ID);
    assertEquals(form.get("redirect_url"), `https://app.example.my/paid?payment_id=${PAY_ID}`);
    assertEquals(form.get("email"), null, "不送电邮 / 电话");
    assertEquals(form.has("payment_methods[]"), false, "网关页显示全部开了的方法");

    for (
      const [res, code] of [
        [() => new Response("no", { status: 401 }), "GATEWAY_AUTH_FAILED"],
        [() => new Response("busy", { status: 503 }), "GATEWAY_UNAVAILABLE"],
        [() => new Response("bad", { status: 422 }), "GATEWAY_REJECTED"],
        [() => Response.json({ id: "x", url: "http://not-https" }), "GATEWAY_BAD_RESPONSE"],
        [() => {
          throw new TypeError("network");
        }, "GATEWAY_UNAVAILABLE"],
      ] as const
    ) {
      reply = res;
      const out = await createCheckout(cfg, { paymentId: PAY_ID, amountSen: 100, description: "x" });
      assertEquals(out.ok ? "ok" : out.code, code);
    }
  } finally {
    f.restore();
    restore();
  }
});

interface World {
  rpc: { name: string; params: Record<string, unknown> }[];
  intent: Record<string, unknown>;
  gateway: () => Response;
  gatewayCalls: number;
  paid?: Response;
}

function backend(w: World) {
  return (c: Call): Response | undefined => {
    if (c.url.origin === "https://api.sandbox.hit-pay.com") {
      w.gatewayCalls++;
      return w.gateway();
    }
    if (c.url.pathname === "/auth/v1/user") {
      if (c.headers.get("authorization") !== `Bearer ${USER_JWT}`) {
        return Response.json({ code: 401, error_code: "bad_jwt", msg: "invalid JWT" }, { status: 401 });
      }
      return Response.json({ id: USER_ID, aud: "authenticated", role: "authenticated" });
    }
    if (c.url.origin === SB_URL && c.url.pathname === "/rest/v1/shops") return Response.json({ name: "阿明茶餐室" });
    const name = rpcName(c);
    if (name) {
      if (!isService(c)) return pgError("NOT_ALLOWED", "42501", 403);
      const params = c.json();
      w.rpc.push({ name, params });
      if (name === "create_payment_intent") return Response.json(w.intent);
      if (name === "attach_payment_checkout") return Response.json(true);
      if (name === "fail_payment") return Response.json(true);
      if (name === "mark_payment_paid") return w.paid ?? Response.json({ result: "paid" });
    }
    return undefined;
  };
}

const PAYMENT = {
  id: PAY_ID,
  amount_sen: 15000,
  description: "Monthly subscription x3",
  checkout_url: null,
  expires_at: "2026-11-27T00:00:00Z",
  shop_id: SHOP,
  wholesaler_id: null,
};

function payReq(body: unknown, jwt: string | null = USER_JWT): Request {
  return new Request(`${SB_URL}/functions/v1/create-payment`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...(jwt ? { Authorization: `Bearer ${jwt}` } : {}) },
    body: JSON.stringify(body),
  });
}

function world(over: Partial<World> = {}): World {
  return {
    rpc: [],
    intent: { result: "ok", reuse: false, payment: PAYMENT },
    gateway: () => Response.json({ id: "HP-REQ-1", url: "https://securecheckout.hit-pay.com/x" }),
    gatewayCalls: 0,
    ...over,
  };
}

async function runPay(w: World, body: unknown, env: Record<string, string | undefined> = ENV, jwt?: string | null) {
  const restore = setEnv(env);
  const f = fakeFetch(backend(w));
  try {
    const res = await createPayment.fetch(payReq(body, jwt === undefined ? USER_JWT : jwt));
    return { status: res.status, body: await res.json(), unexpected: f.unexpected };
  } finally {
    f.restore();
    restore();
  }
}

Deno.test("create-payment：开单 → 网关 → 记下付款页，回传网址", async () => {
  const w = world();
  const r = await runPay(w, { purpose: "subscription", target_id: SHOP, months: 3 });
  assertEquals(r.status, 200);
  assertEquals(r.body.checkout_url, "https://securecheckout.hit-pay.com/x");
  assertEquals(r.body.amount_sen, 15000);
  assertEquals(r.body.reuse, false);
  assertEquals(w.rpc[0].params, {
    p_user_id: USER_ID,
    p_purpose: "subscription",
    p_target_id: SHOP,
    p_months: 3,
    p_gateway: "hitpay",
  });
  assertEquals(w.rpc[1].name, "attach_payment_checkout");
  assertEquals(w.rpc[1].params.p_gateway_ref, "HP-REQ-1");
  assertEquals(r.unexpected, []);
});

Deno.test("create-payment：同一张还有效 → 不再去网关", async () => {
  const w = world({
    intent: {
      result: "ok",
      reuse: true,
      payment: { ...PAYMENT, checkout_url: "https://securecheckout.hit-pay.com/old" },
    },
  });
  const r = await runPay(w, { purpose: "subscription", target_id: SHOP });
  assertEquals(r.body.checkout_url, "https://securecheckout.hit-pay.com/old");
  assertEquals(r.body.reuse, true);
  assertEquals(w.gatewayCalls, 0);
});

Deno.test("create-payment：没设网关 → 503 PAYMENT_NOT_CONFIGURED，不开单", async () => {
  const w = world();
  const r = await runPay(w, { purpose: "subscription", target_id: SHOP }, { ...ENV, HITPAY_API_KEY: undefined });
  assertEquals([r.status, r.body.error], [503, "PAYMENT_NOT_CONFIGURED"]);
  assertEquals(w.rpc.length, 0);
});

Deno.test("create-payment：数据库说不行 → 对应的错误", async () => {
  for (
    const [result, status, code] of [
      ["not_allowed", 403, "NOT_ALLOWED"],
      ["not_found", 404, "NOT_FOUND"],
      ["nothing_due", 409, "NOTHING_DUE"],
      ["founding_full", 409, "FOUNDING_FULL"],
      ["too_many", 429, "TOO_MANY_PAYMENTS"],
      ["invalid", 400, "INVALID_REQUEST"],
    ] as const
  ) {
    const w = world({ intent: { result } });
    const r = await runPay(w, { purpose: "listing_fee", target_id: SHOP });
    assertEquals([r.status, r.body.error], [status, code], result);
    assertEquals(w.gatewayCalls, 0);
  }
});

Deno.test("create-payment：网关失败 → 付款单标失败、回 503 / 502", async () => {
  let w = world({ gateway: () => new Response("busy", { status: 502 }) });
  let r = await runPay(w, { purpose: "commission_invoice", target_id: SHOP });
  assertEquals([r.status, r.body.error], [503, "GATEWAY_UNAVAILABLE"]);
  assertEquals(w.rpc.at(-1), {
    name: "fail_payment",
    params: { p_payment_id: PAY_ID, p_reason: "GATEWAY_UNAVAILABLE" },
  });
  w = world({ gateway: () => new Response("bad", { status: 422 }) });
  r = await runPay(w, { purpose: "commission_invoice", target_id: SHOP });
  assertEquals([r.status, r.body.error], [502, "GATEWAY_REJECTED"]);
});

Deno.test("create-payment：没登录 / 请求不对", async () => {
  assertEquals((await runPay(world(), { purpose: "subscription", target_id: SHOP }, ENV, null)).status, 401);
  assertEquals((await runPay(world(), { purpose: "subscription", target_id: SHOP }, ENV, "bad.jwt")).status, 401);
  for (
    const body of [
      { purpose: "donation", target_id: SHOP },
      { purpose: "subscription", target_id: "not-a-uuid" },
      { purpose: "subscription", target_id: SHOP, months: 1.5 },
    ]
  ) {
    const w = world();
    const r = await runPay(w, body);
    assertEquals([r.status, r.body.error], [400, "INVALID_REQUEST"], JSON.stringify(body));
    assertEquals(w.rpc.length, 0);
  }
});

// ---------------------------------------------------------------------------
// payment-webhook
// ---------------------------------------------------------------------------

function completed(over: Record<string, unknown> = {}) {
  return JSON.stringify({
    id: "HP-REQ-1",
    reference_number: PAY_ID,
    status: "completed",
    amount: "150.00",
    currency: "MYR",
    email: "boss@example.com",
    phone: "+60120000001",
    payments: [{
      id: "PAY-1",
      status: "succeeded",
      payment_type: "fpx",
      amount: "150.00",
      buyer_email: "boss@example.com",
    }],
    ...over,
  });
}

async function hook(
  w: World,
  body: string,
  opts: { sig?: string | null; env?: Record<string, string | undefined> } = {},
) {
  const restore = setEnv(opts.env ?? ENV);
  const f = fakeFetch(backend(w));
  try {
    const raw = new TextEncoder().encode(body);
    const sig = opts.sig === undefined ? await hmacSha256Hex(SALT, raw) : opts.sig;
    const res = await paymentWebhook.fetch(
      new Request(`${SB_URL}/functions/v1/payment-webhook`, {
        method: "POST",
        headers: { "Content-Type": "application/json", ...(sig ? { "Hitpay-Signature": sig } : {}) },
        body: raw,
      }),
    );
    return { status: res.status, body: await res.json() };
  } finally {
    f.restore();
    restore();
  }
}

Deno.test("webhook 签名：HMAC-SHA256(salt, 原始 body)", async () => {
  const raw = new TextEncoder().encode(completed());
  const good = await hmacSha256Hex(SALT, raw);
  assert(await verifyWebhook(raw, good, SALT));
  assert(await verifyWebhook(raw, good.toUpperCase(), SALT));
  assert(!(await verifyWebhook(raw, good, "other-salt")));
  assert(!(await verifyWebhook(new TextEncoder().encode(completed({ amount: "1.00" })), good, SALT)), "内容改了就不对");
  assert(!(await verifyWebhook(raw, null, SALT)));
  assert(!(await verifyWebhook(raw, "sha256=" + good, SALT)));
});

Deno.test("webhook 内容：已付 / 失败 / 不是我们的；不存老板的电邮电话", () => {
  const ev = parseWebhook(JSON.parse(completed()))!;
  assertEquals([ev.paymentId, ev.ref, ev.status, ev.amountSen, ev.method], [PAY_ID, "HP-REQ-1", "paid", 15000, "fpx"]);
  assert(!JSON.stringify(ev.raw).includes("boss@example.com"));
  assert(!JSON.stringify(ev.raw).includes("+6012"));
  assertEquals(parseWebhook(JSON.parse(completed({ status: "failed", payments: [] })))!.status, "failed");
  assertEquals(parseWebhook(JSON.parse(completed({ status: "pending", payments: [] })))!.status, "pending");
  assertEquals(parseWebhook(JSON.parse(completed({ reference_number: "ORDER-1" }))), null);
  assertEquals(parseWebhook(null), null);
});

Deno.test("payment-webhook：签名对 → mark_payment_paid（金额、方法、网关单号）", async () => {
  const w = world();
  const r = await hook(w, completed());
  assertEquals([r.status, r.body.result], [200, "paid"]);
  assertEquals(w.rpc[0].name, "mark_payment_paid");
  const p = w.rpc[0].params;
  assertEquals([p.p_payment_id, p.p_gateway, p.p_gateway_ref, p.p_amount_sen, p.p_method], [
    PAY_ID,
    "hitpay",
    "HP-REQ-1",
    15000,
    "fpx",
  ]);
});

Deno.test("payment-webhook：重复通知 → 数据库回 already_paid，照样 200", async () => {
  const w = world({ paid: Response.json({ result: "already_paid" }) });
  const r = await hook(w, completed());
  assertEquals([r.status, r.body.result], [200, "already_paid"]);
});

Deno.test("payment-webhook：签名不对 / 没有 → 401，不碰数据库", async () => {
  for (const sig of [null, "0".repeat(64), "not-hex"]) {
    const w = world();
    const r = await hook(w, completed(), { sig });
    assertEquals(r.status, 401);
    assertEquals(w.rpc.length, 0);
  }
});

Deno.test("payment-webhook：没设 salt → 503（网关之后会再送）", async () => {
  const w = world();
  const r = await hook(w, completed(), { env: { ...ENV, HITPAY_SALT: undefined } });
  assertEquals([r.status, r.body.error], [503, "NOT_CONFIGURED"]);
});

Deno.test("payment-webhook：失败 → fail_payment；不是令吉 → 金额当作对不上；数据库出错 → 500", async () => {
  let w = world();
  let r = await hook(w, completed({ status: "failed", payments: [] }));
  assertEquals(r.body.result, "failed");
  assertEquals(w.rpc[0], { name: "fail_payment", params: { p_payment_id: PAY_ID, p_reason: "GATEWAY_FAILED" } });

  w = world();
  await hook(w, completed({ currency: "SGD" }));
  assertEquals(w.rpc[0].params.p_amount_sen, -1);

  w = world({ paid: pgError("boom", "XX000", 500) });
  r = await hook(w, completed());
  assertEquals([r.status, r.body.error], [500, "DB_ERROR"]);

  w = world();
  r = await hook(w, completed({ reference_number: "not-ours" }));
  assertEquals([r.status, r.body.result], [200, "ignored"]);
  assertEquals(w.rpc.length, 0);
});

Deno.test("payment-webhook：body 太大 → 413；不是 POST → 405", async () => {
  const w = world();
  const r = await hook(w, "x".repeat(MAX_BODY_BYTES + 1), { sig: "0".repeat(64) });
  assertEquals(r.status, 413);
  const restore = setEnv(ENV);
  try {
    assertEquals((await paymentWebhook.fetch(new Request(`${SB_URL}/functions/v1/payment-webhook`))).status, 405);
  } finally {
    restore();
  }
});

// ---------------------------------------------------------------------------
// 收费的推送
// ---------------------------------------------------------------------------

function item(event_type: string, payload: Record<string, unknown>, locale = "zh"): NotificationItem {
  return {
    id: "n1",
    event_type,
    payload,
    locale,
    channel: "push",
    push_targets: [],
    whatsapp_phone: null,
    details: null,
  };
}

Deno.test("收费推送：新账单 / 逾期 / 快到期 / 收到付款（三种语言）", () => {
  const inv = {
    invoice_id: "inv-1",
    invoice_no: "INV2610-0001",
    period_month: "2026-10-01",
    commission_sen: 25500,
    due_date: "2026-11-15",
  };
  const zh = pushContent(item("invoice_issued", inv));
  assertEquals(zh.title, "2026年10月 佣金账单 INV2610-0001");
  assertStringIncludes(zh.body, "RM255.00");
  assertStringIncludes(zh.body, "2026年11月15日");
  assertEquals(zh.data.invoice_id, "inv-1");
  assertEquals(pushContent(item("invoice_overdue", inv, "en")).title, "Invoice INV2610-0001 is overdue");
  assertStringIncludes(pushContent(item("invoice_due_soon", inv, "ms")).body, "RM255.00");
  assertEquals(monthLabel("2026-10-01", "ms"), "Okt 2026");

  const trial = pushContent(item("subscription_ending", { status: "trialing", ends_at: "2026-12-01T04:00:00Z" }));
  assertStringIncludes(trial.body, "试用");
  assert(!/付|pay|bayar/i.test(trial.body), "买家的提醒不叫他去别的地方付钱（App Store 规定）");
  const paid = pushContent(
    item("payment_received", {
      purpose: "subscription",
      amount_sen: 5000,
      period_end: "2027-01-01T00:00:00Z",
      payment_id: "p1",
    }, "en"),
  );
  assertEquals(paid.title, "Payment received RM50.00");
  assertEquals(paid.data.payment_id, "p1");
});
