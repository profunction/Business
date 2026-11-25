import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import fn from "../dispatch-notifications/index.ts";
import { clearFcmTokenCache } from "../_shared/fcm.ts";
import {
  type Call,
  fakeEdgeRuntime,
  fakeFetch,
  isService,
  LEGACY_SERVICE_KEY,
  pgError,
  rpcName,
  SB_URL,
  SECRET,
  setEnv,
  SUPABASE_ENV,
} from "./_helpers.ts";
import { googleTokenEndpoint, testServiceAccount } from "./_google.ts";

const ORDER_ID = "5b1c2d3e-0000-4000-8000-123456789abc";
const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;

const details = {
  order_id: ORDER_ID,
  order_no: "JHB261126-00012",
  status: "pending",
  shop_name: "阿成茶室",
  shop_address: "12, Jalan Kuning 2",
  shop_phone: "60123",
  wholesaler_name: "ABC",
  items_text: "16安士 PP杯 x2 箱",
  item_count: 1,
  total_sen: 17800,
  expected_delivery_date: "2026-11-26",
  out_of_stock_count: 0,
};

function claimed(n: number, over: Record<string, unknown>) {
  return {
    id: id(n),
    event_type: "order_new",
    payload: { order_id: ORDER_ID, order_no: "JHB261126-00012", shop_name: "阿成茶室", total_sen: 17800 },
    locale: "zh",
    channel: "push",
    push_targets: [],
    whatsapp_phone: null,
    attempts: 0,
    details,
    ...over,
  };
}

interface Backend {
  batches: unknown[][];
  completes: Record<string, Record<string, unknown>>;
  removed: string[][];
  templates: Record<string, unknown>[];
  claimError?: boolean;
}

/** PostgREST RPC + Google OAuth + FCM + Graph API */
function backend(b: Backend, publicKey: CryptoKey) {
  return async (c: Call): Promise<Response | undefined> => {
    const name = rpcName(c);
    if (name) {
      if (!isService(c)) return pgError("NOT_ALLOWED", "42501", 403);
      if (name === "claim_notifications") {
        assertEquals(c.json(), { p_limit: 50 });
        if (b.claimError) return pgError("boom", "XX000", 500);
        return Response.json(b.batches.shift() ?? []);
      }
      if (name === "complete_notification") {
        const p = c.json();
        assertEquals(Object.keys(p).sort(), ["p_channel", "p_error", "p_id", "p_retry", "p_status", "p_wa_message_id"]);
        b.completes[p.p_id] = p;
        return Response.json(true);
      }
      if (name === "remove_device_tokens") {
        b.removed.push(c.json().p_tokens);
        return Response.json(c.json().p_tokens.length);
      }
      return undefined;
    }
    if (c.url.host === "oauth2.googleapis.com") return await googleTokenEndpoint(c, publicKey, "ya29.ok");
    if (c.url.host === "fcm.googleapis.com") {
      assertEquals(c.headers.get("authorization"), "Bearer ya29.ok");
      const m = c.json().message;
      const target = m.token ?? m.fid;
      if (target.startsWith("dead")) {
        return Response.json({
          error: {
            code: 404,
            status: "NOT_FOUND",
            message: "Requested entity was not found.",
            details: [{ "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError", errorCode: "UNREGISTERED" }],
          },
        }, { status: 404 });
      }
      if (target === "busy") {
        return Response.json({ error: { code: 503, status: "UNAVAILABLE", message: "x" } }, { status: 503 });
      }
      return Response.json({ name: `projects/test-project/messages/${target}` });
    }
    if (c.url.host === "graph.facebook.com") {
      const body = c.json();
      b.templates.push(body);
      if (body.to === "+60111") return Response.json({ messages: [{ id: "wamid.SENT1", message_status: "accepted" }] });
      const code = body.to === "+60222" ? 131026 : 131056;
      return Response.json({ error: { message: `(#${code}) failed`, code, error_data: { details: "d" } } }, {
        status: 400,
      });
    }
    return undefined;
  };
}

async function setup(extra: Record<string, string | undefined> = {}) {
  clearFcmTokenCache();
  const { json, publicKey } = await testServiceAccount();
  const restoreEnv = setEnv({
    ...SUPABASE_ENV,
    FCM_SERVICE_ACCOUNT_JSON: json,
    WHATSAPP_TOKEN: "wa-token",
    WHATSAPP_PHONE_NUMBER_ID: "1065",
    WHATSAPP_GRAPH_VERSION: undefined,
    ...extra,
  });
  const b: Backend = { batches: [], completes: {}, removed: [], templates: [] };
  const net = fakeFetch(backend(b, publicKey));
  return {
    b,
    net,
    restore: () => {
      net.restore();
      restoreEnv();
    },
  };
}

const post = (headers: Record<string, string> = { apikey: SECRET }) =>
  new Request(`${SB_URL}/functions/v1/dispatch-notifications`, { method: "POST", headers, body: "{}" });

Deno.test("dispatch：没有 / 错的 apikey → 401，不碰数据库；GET → 405", async () => {
  const t = await setup();
  try {
    assertEquals((await fn.fetch(post({}))).status, 401);
    assertEquals((await fn.fetch(post({ apikey: "sb_secret_wrong" }))).status, 401);
    assertEquals((await fn.fetch(post({ apikey: "sb_publishable_test_abcdef" }))).status, 401);
    assertEquals((await fn.fetch(post({ Authorization: `Bearer ${SECRET}` }))).status, 401); // 规格：只看 apikey
    assertEquals((await fn.fetch(new Request(`${SB_URL}/x`, { headers: { apikey: SECRET } }))).status, 405);
    assertEquals(t.net.calls.length, 0);
  } finally {
    t.restore();
  }
});

Deno.test("dispatch：旧项目的 service_role key 也可以", async () => {
  const t = await setup({ SUPABASE_SECRET_KEYS: undefined, SUPABASE_SERVICE_ROLE_KEY: LEGACY_SERVICE_KEY });
  try {
    assertEquals((await fn.fetch(post({ apikey: SECRET }))).status, 401);
    const res = await fn.fetch(post({ apikey: LEGACY_SERVICE_KEY }));
    assertEquals(res.status, 200);
    assertEquals((await res.json()).claimed, 0);
    assertEquals(t.net.calls[0].headers.get("apikey"), LEGACY_SERVICE_KEY);
  } finally {
    t.restore();
  }
});

Deno.test("dispatch：推送（失效 token 清掉）、WhatsApp（成功 / 不重试 / 重试）、没渠道 skipped、坏资料不影响别条", async () => {
  const t = await setup();
  const rt = fakeEdgeRuntime();
  t.b.batches.push([
    claimed(1, {
      push_targets: [{ target: "tok-ok", kind: "token" }, { target: "dead-tok", kind: "token" }, {
        target: "dead-fid",
        kind: "fid",
      }],
    }),
    claimed(2, { push_targets: [{ target: "dead-only", kind: "fid" }] }),
    claimed(3, { channel: "whatsapp", whatsapp_phone: "60111" }),
    claimed(4, {
      channel: "whatsapp",
      whatsapp_phone: "60222",
      event_type: "order_cancelled",
      payload: { order_id: ORDER_ID },
    }),
    claimed(5, { channel: "whatsapp", whatsapp_phone: "60333" }),
    claimed(6, { channel: null }),
    claimed(7, { push_targets: [{ target: "busy", kind: "token" }] }),
    { id: "not-a-uuid", channel: "push" },
    claimed(9, { channel: "whatsapp", whatsapp_phone: "60111", event_type: "daily_summary", payload: {} }),
  ]);
  t.b.batches.push([claimed(10, { push_targets: [{ target: "tok-2", kind: "fid" }], event_type: "daily_summary" })]);
  try {
    const res = await fn.fetch(post());
    assertEquals(res.status, 200);
    const s = await res.json();
    assertEquals(
      {
        rounds: s.rounds,
        claimed: s.claimed,
        sent: s.sent,
        failed: s.failed,
        retry: s.retry_scheduled,
        skipped: s.skipped,
      },
      { rounds: 1, claimed: 9, sent: 2, failed: 1, retry: 3, skipped: 2 },
    );
    assertEquals(s.tokens_removed, 3);
    assertEquals(s.errors, 1); // not-a-uuid
    assertEquals(t.net.unexpected, []);
    assertEquals(rt.pending.length, 1); // 交给 EdgeRuntime.waitUntil 保护

    const c = t.b.completes;
    assertEquals(c[id(1)], {
      p_id: id(1),
      p_status: "sent",
      p_channel: "push",
      p_error: null,
      p_wa_message_id: null,
      p_retry: false,
    });
    assertEquals([c[id(2)].p_status, c[id(2)].p_retry, c[id(2)].p_error], [
      "failed",
      true,
      "PUSH_TARGETS_UNREGISTERED",
    ]);
    assertEquals([c[id(3)].p_status, c[id(3)].p_channel, c[id(3)].p_wa_message_id], [
      "sent",
      "whatsapp",
      "wamid.SENT1",
    ]);
    assertEquals([c[id(4)].p_status, c[id(4)].p_retry], ["failed", false]); // 131026：等对方处理
    assertStringIncludes(c[id(4)].p_error as string, "WHATSAPP_131026");
    assertEquals([c[id(5)].p_status, c[id(5)].p_retry], ["failed", true]); // 131056：限速，重试
    assertEquals([c[id(6)].p_status, c[id(6)].p_channel, c[id(6)].p_error], ["skipped", null, "NO_CHANNEL"]);
    assertEquals([c[id(7)].p_status, c[id(7)].p_retry], ["failed", true]); // 503
    assertEquals([c[id(9)].p_status, c[id(9)].p_error], ["skipped", "NO_WHATSAPP_TEMPLATE"]);
    assertEquals(Object.keys(c).length, 8);
    assertEquals(t.b.batches.length, 1); // 不满 50 条：第二批留给下一次叫
    assertEquals(t.b.removed.map((r) => [...r].sort()), [["dead-fid", "dead-only", "dead-tok"]]);

    // 新订单的模板：按钮 payload
    const tpl = t.b.templates.find((x) => x.to === "+60111") as { template: { name: string; components: unknown[] } };
    assertEquals(tpl.template.name, "order_new_v1");
    assertEquals(tpl.template.components.slice(1), [
      {
        type: "button",
        sub_type: "quick_reply",
        index: "0",
        parameters: [{ type: "payload", payload: `CONFIRM:${ORDER_ID}` }],
      },
      {
        type: "button",
        sub_type: "quick_reply",
        index: "1",
        parameters: [{ type: "payload", payload: `OOS:${ORDER_ID}` }],
      },
    ]);
    const cancelled = t.b.templates.find((x) => x.to === "+60222") as { template: { name: string } };
    assertEquals(cancelled.template.name, "order_cancelled_v1");
  } finally {
    rt.restore();
    t.restore();
  }
});

Deno.test("dispatch：领满 50 条就再领一批，直到领到的不满一批", async () => {
  const t = await setup();
  t.b.batches.push(Array.from({ length: 50 }, (_, i) => claimed(100 + i, { channel: null })));
  t.b.batches.push([claimed(200, { push_targets: [{ target: "tok-2", kind: "fid" }], event_type: "daily_summary" })]);
  t.b.batches.push([claimed(300, { channel: null })]);
  try {
    const s = await (await fn.fetch(post())).json();
    assertEquals([s.rounds, s.claimed, s.skipped, s.sent], [2, 51, 50, 1]);
    assertEquals(t.b.completes[id(200)].p_status, "sent");
    assertEquals(t.b.batches.length, 1);
  } finally {
    t.restore();
  }
});

Deno.test("dispatch：没设定 FCM / WhatsApp → failed、不重试", async () => {
  const t = await setup({ FCM_SERVICE_ACCOUNT_JSON: undefined, WHATSAPP_TOKEN: undefined });
  t.b.batches.push([
    claimed(1, { push_targets: [{ target: "tok", kind: "token" }] }),
    claimed(2, { channel: "whatsapp", whatsapp_phone: "60111" }),
    claimed(3, { push_targets: [] }),
  ]);
  try {
    const s = await (await fn.fetch(post())).json();
    assertEquals([s.failed, s.skipped, s.sent], [2, 1, 0]);
    const c = t.b.completes;
    assertEquals([c[id(1)].p_error, c[id(1)].p_retry], ["FCM_NOT_CONFIGURED", false]);
    assertEquals([c[id(2)].p_error, c[id(2)].p_retry], ["WHATSAPP_NOT_CONFIGURED", false]);
    assertEquals([c[id(3)].p_status, c[id(3)].p_error], ["skipped", "NO_PUSH_TARGETS"]);
    assert(!t.net.calls.some((x) => x.url.origin !== SB_URL));
  } finally {
    t.restore();
  }
});

Deno.test("dispatch：claim 失败 → 502；complete 失败一次会再试", async () => {
  const t = await setup();
  t.b.claimError = true;
  try {
    const res = await fn.fetch(post());
    assertEquals(res.status, 502);
    assertEquals((await res.json()).error, "CLAIM_FAILED");
  } finally {
    t.restore();
  }

  const t2 = await setup();
  t2.b.batches.push([claimed(1, { channel: null })]);
  let failOnce = true;
  const inner = globalThis.fetch;
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    if (String(input).endsWith("/rpc/complete_notification") && failOnce) {
      failOnce = false;
      return new Response("bad gateway", { status: 502 });
    }
    return await inner(input, init);
  }) as typeof fetch;
  try {
    const s = await (await fn.fetch(post())).json();
    assertEquals([s.skipped, s.errors], [1, 0]);
    assertEquals(t2.b.completes[id(1)].p_status, "skipped");
  } finally {
    globalThis.fetch = inner;
    t2.restore();
  }
});
