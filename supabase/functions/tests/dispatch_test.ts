import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import fn, {
  BUDGET_EXCEEDED,
  DISPATCH_TIMING,
  dispatchDeadline,
  processItem,
  worker,
} from "../dispatch-notifications/index.ts";
import { requestTimeoutMs } from "../_shared/http.ts";
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
  waitFor,
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
  /** release_notification 收到的 id（照顺序，包括回 false 的） */
  releases: string[];
  /** 每条通知现在的状态：claim → sending；complete → sent / failed / skipped；release → queued */
  status: Map<string, string>;
  claimError?: boolean;
  /** release_notification 回 500 */
  releaseError?: boolean;
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
        const batch = b.batches.shift() ?? [];
        for (const r of batch) {
          const id = (r as { id?: unknown }).id;
          if (typeof id === "string") b.status.set(id, "sending");
        }
        return Response.json(batch);
      }
      if (name === "complete_notification") {
        const p = c.json();
        assertEquals(Object.keys(p).sort(), ["p_channel", "p_error", "p_id", "p_retry", "p_status", "p_wa_message_id"]);
        b.completes[p.p_id] = p;
        // 照 SQL：只改「发送中」的那条（true）；不是发送中就不改（false）
        if (b.status.get(p.p_id) !== "sending") return Response.json(false);
        b.status.set(p.p_id, p.p_status);
        return Response.json(true);
      }
      if (name === "release_notification") {
        const p = c.json();
        assertEquals(Object.keys(p), ["p_id"]);
        b.releases.push(p.p_id);
        if (b.releaseError) return pgError("canceling statement due to statement timeout", "57014", 500);
        // 照 SQL：没有这条 → NOTIFICATION_NOT_FOUND；只放「发送中」的（true），其他不改（false）
        if (!b.status.has(p.p_id)) return pgError("NOTIFICATION_NOT_FOUND");
        if (b.status.get(p.p_id) !== "sending") return Response.json(false);
        b.status.set(p.p_id, "queued");
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

const TIMING_DEFAULT = structuredClone(DISPATCH_TIMING);

async function setup(extra: Record<string, string | undefined> = {}) {
  clearFcmTokenCache();
  // complete 重试的间隔缩短（测试不用真的等 0.5 / 2 / 5 秒）
  Object.assign(DISPATCH_TIMING, { ...structuredClone(TIMING_DEFAULT), retryMs: [20, 50], sentRetryMs: [20, 50, 100] });
  const workerBefore = { ...worker };
  Object.assign(worker, { startedAt: Date.now(), stopping: false }); // 新的 worker
  const { json, publicKey } = await testServiceAccount();
  const restoreEnv = setEnv({
    ...SUPABASE_ENV,
    FCM_SERVICE_ACCOUNT_JSON: json,
    WHATSAPP_TOKEN: "wa-token",
    WHATSAPP_PHONE_NUMBER_ID: "1065",
    WHATSAPP_GRAPH_VERSION: undefined,
    ...extra,
  });
  const b: Backend = { batches: [], completes: {}, removed: [], templates: [], releases: [], status: new Map() };
  const net = fakeFetch(backend(b, publicKey));
  return {
    b,
    net,
    restore: () => {
      net.restore();
      restoreEnv();
      Object.assign(DISPATCH_TIMING, structuredClone(TIMING_DEFAULT));
      Object.assign(worker, workerBefore);
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

Deno.test("dispatch：一批里面也看时间预算——剩下不到 15 秒就不再开始发，没发的放回队列（release_notification）；不再领下一批", async () => {
  const t = await setup();
  t.b.batches.push(
    Array.from({ length: 50 }, (_, i) => claimed(400 + i, { channel: "whatsapp", whatsapp_phone: "60111" })),
  );
  t.b.batches.push([claimed(500, { channel: "whatsapp", whatsapp_phone: "60111" })]);
  // 假的时钟：Meta 每个请求要 10 秒
  const realNow = Date.now;
  const t0 = realNow();
  let now = t0;
  Date.now = () => now;
  const inner = globalThis.fetch;
  const starts: number[] = [];
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    if (String(input).includes("graph.facebook.com")) {
      starts.push(now - t0);
      now += 10_000;
    }
    return await inner(input, init);
  }) as typeof fetch;
  try {
    const s = await (await fn.fetch(post())).json();
    assertEquals(s.rounds, 1); // 预算用完：第二批留给下一次
    assertEquals(t.b.batches.length, 1);
    assert(s.deferred > 0 && s.sent > 0, JSON.stringify(s));
    assertEquals(s.sent + s.deferred, 50);
    assertEquals(t.b.templates.length, s.sent);
    // 每个请求开始的时候都还剩至少 15 秒（100 秒预算）
    assert(Math.max(...starts) <= 100_000 - DISPATCH_TIMING.itemMinMs, starts.join(","));
    // 没发的放回队列（排队中，下一次马上再领；不算失败、不标 failed）
    assertEquals(t.b.releases.length, s.deferred);
    assertEquals(Object.values(t.b.completes).filter((c) => c.p_error === BUDGET_EXCEEDED), []);
    assertEquals(Object.keys(t.b.completes).length, s.sent);
    assertEquals(new Set([...t.b.releases, ...Object.keys(t.b.completes)]).size, 50); // 每条都处理了、只处理一次
    for (const r of t.b.releases) assertEquals(t.b.status.get(r), "queued");
    assertEquals([...t.b.status.values()].filter((x) => x === "sending"), []); // 没有卡在「发送中」的
    assertEquals(s.errors, 0);
  } finally {
    Date.now = realNow;
    globalThis.fetch = inner;
    t.restore();
  }
});

Deno.test("时间不够、放不回队列（release_notification 出错）→ 退回旧的做法：标 failed + 重试；回 false（已经不是发送中）不用管", async () => {
  const batch = (from: number) =>
    Array.from({ length: 50 }, (_, i) => claimed(from + i, { channel: "whatsapp", whatsapp_phone: "60111" }));
  const t = await setup();
  t.b.releaseError = true;
  t.b.batches.push(batch(900));
  const clock = fakeClock();
  try {
    const s = await (await fn.fetch(post())).json();
    assert(s.deferred > 0 && s.sent > 0, JSON.stringify(s));
    assertEquals(t.b.releases.length, s.deferred); // 先试过放回去
    const fallback = Object.values(t.b.completes).filter((c) => c.p_error === BUDGET_EXCEEDED);
    assertEquals(fallback.length, s.deferred);
    for (const c of fallback) assertEquals([c.p_status, c.p_retry, c.p_channel], ["failed", true, "whatsapp"]);
    assertEquals(Object.keys(t.b.completes).length, 50); // 不会卡在「发送中」
    assertEquals([...t.b.status.values()].filter((x) => x === "sending"), []);
    assertEquals(s.errors, 0);
  } finally {
    clock.restore();
    t.restore();
  }

  // 回 false：那条已经不是「发送中」（例如被当成卡住、别的 dispatcher 领走发完了）→ 不再 complete，也不算错误
  const t2 = await setup();
  t2.b.batches.push(batch(950));
  const clock2 = fakeClock();
  const inner = globalThis.fetch;
  globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
    if (String(input).includes("graph.facebook.com")) t2.b.status.set(id(999), "sent");
    return inner(input, init);
  }) as typeof fetch;
  try {
    const s = await (await fn.fetch(post())).json();
    assert(t2.b.releases.includes(id(999)), JSON.stringify(s));
    assertEquals(t2.b.status.get(id(999)), "sent");
    assert(!(id(999) in t2.b.completes));
    assertEquals(Object.keys(t2.b.completes).length + t2.b.releases.length, 50);
    assertEquals([s.deferred, s.errors], [t2.b.releases.length, 0]);
  } finally {
    globalThis.fetch = inner;
    clock2.restore();
    t2.restore();
  }
});

Deno.test("worker 要被关掉（beforeunload）：领到了、还没开始发的马上放回队列，不等正在发的那几条；每条只处理一次", async () => {
  const t = await setup();
  t.b.batches.push(
    Array.from({ length: 12 }, (_, i) => claimed(1000 + i, { channel: "whatsapp", whatsapp_phone: "60111" })),
  );
  t.b.batches.push([claimed(1100, { channel: "whatsapp", whatsapp_phone: "60111" })]);
  // Meta 一直不回，直到 finish：同时最多 5 条在发
  const inner = globalThis.fetch;
  const inFlight: (() => void)[] = [];
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    if (String(input).includes("graph.facebook.com")) await new Promise<void>((r) => inFlight.push(r));
    return await inner(input, init);
  }) as typeof fetch;
  try {
    const res = fn.fetch(post());
    await waitFor(() => inFlight.length === 5);
    globalThis.dispatchEvent(new CustomEvent("beforeunload", { detail: { reason: "WallClockTime" } }));
    // 正在发的 5 条还没回来，没开始的 7 条已经放回去了
    await waitFor(() => t.b.releases.length === 7);
    assertEquals([...t.b.releases].sort(), Array.from({ length: 7 }, (_, i) => id(1005 + i)));
    for (const r of t.b.releases) assertEquals(t.b.status.get(r), "queued");
    assertEquals(Object.keys(t.b.completes), []);
    inFlight.forEach((finish) => finish());
    const s = await (await res).json();
    assertEquals([s.rounds, s.sent, s.deferred, s.errors], [1, 5, 7, 0]);
    assertEquals(t.b.releases.length, 7);
    assertEquals(Object.keys(t.b.completes).sort(), Array.from({ length: 5 }, (_, i) => id(1000 + i)));
    assertEquals(t.b.batches.length, 1); // 不再领
  } finally {
    globalThis.fetch = inner;
    t.restore();
  }
});

Deno.test("请求的 timeout：平常 15 秒；快到期限时缩短（最少 1 秒）", () => {
  const now = Date.now();
  assertEquals(requestTimeoutMs(), 15_000);
  assertEquals(requestTimeoutMs(null), 15_000);
  assertEquals(requestTimeoutMs(now + 60_000), 15_000);
  const near = requestTimeoutMs(now + 5_000);
  assert(near <= 5_000 && near > 4_000, String(near));
  assertEquals(requestTimeoutMs(now - 1_000), 1_000);
});

/** complete_notification 在 outageMs 毫秒内都回 503；回传每次被叫的时间 */
function flakyComplete(outageMs: number): { times: number[]; restore: () => void } {
  const inner = globalThis.fetch;
  const times: number[] = [];
  let first = 0;
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    if (String(input).endsWith("/rpc/complete_notification")) {
      const now = performance.now();
      if (!first) first = now;
      times.push(now - first);
      if (now - first < outageMs) return new Response("service unavailable", { status: 503 });
    }
    return await inner(input, init);
  }) as typeof fetch;
  return { times, restore: () => (globalThis.fetch = inner) };
}

Deno.test("complete 失败：隔一下再试（不是马上），数据库短暂断线也记得到", async () => {
  const t = await setup();
  t.b.batches.push([claimed(1, { channel: null })]);
  const flaky = flakyComplete(40); // 0 ms、20 ms 失败，70 ms 成功
  try {
    const s = await (await fn.fetch(post())).json();
    assertEquals([s.skipped, s.errors], [1, 0]);
    assertEquals(t.b.completes[id(1)].p_status, "skipped");
    assertEquals(flaky.times.length, 3);
    assert(flaky.times[1] >= 18 && flaky.times[2] - flaky.times[1] >= 45, flaky.times.join(","));
  } finally {
    flaky.restore();
    t.restore();
  }
});

Deno.test("complete 失败：已经发出去的 WhatsApp 多试一次；还是不行 → 日志记 wamid（对得回去）", async () => {
  const errors: string[] = [];
  const realError = console.error;
  console.error = (line: string) => errors.push(line);
  try {
    // 断线 120 ms：sent 试 4 次（0、20、70、170 ms）记得到；skipped 只试 3 次（0、20、70）就放弃
    const t = await setup();
    t.b.batches.push([claimed(3, { channel: "whatsapp", whatsapp_phone: "60111" })]);
    const flaky = flakyComplete(120);
    try {
      const s = await (await fn.fetch(post())).json();
      assertEquals([s.sent, s.errors], [1, 0]);
      assertEquals(t.b.completes[id(3)].p_wa_message_id, "wamid.SENT1");
      assertEquals(flaky.times.length, 4);
    } finally {
      flaky.restore();
      t.restore();
    }

    const t2 = await setup();
    t2.b.batches.push([claimed(4, { channel: null })]);
    const flaky2 = flakyComplete(120);
    try {
      const s = await (await fn.fetch(post())).json();
      assertEquals([s.skipped, s.errors], [1, 1]);
      assertEquals(flaky2.times.length, 3);
    } finally {
      flaky2.restore();
      t2.restore();
    }

    // 一直断线：sent 那条放弃时，日志有 wamid
    const t3 = await setup();
    t3.b.batches.push([claimed(5, { channel: "whatsapp", whatsapp_phone: "60111" })]);
    const flaky3 = flakyComplete(60_000);
    try {
      const s = await (await fn.fetch(post())).json();
      assertEquals([s.sent, s.errors], [1, 1]);
      const last = errors.map((l) => JSON.parse(l)).filter((l) => l.event === "complete_notification_failed").at(-1);
      assertEquals([last.notification_id, last.wa_message_id, last.final], [id(5), "wamid.SENT1", true]);
    } finally {
      flaky3.restore();
      t3.restore();
    }
  } finally {
    console.error = realError;
  }
});

Deno.test("dispatch：某一条发的时候丢错（程式错误）→ 那条 failed + 重试，别条照常发完", async () => {
  const { json } = await testServiceAccount();
  // project_id 有落单的 surrogate：encodeURIComponent 会丢 URIError（sendFcm 里没接住的那种错）
  const broken = JSON.stringify({ ...JSON.parse(json), project_id: "bad\ud800" });
  const t = await setup({ FCM_SERVICE_ACCOUNT_JSON: broken });
  t.b.batches.push([
    claimed(1, { push_targets: [{ target: "tok-ok", kind: "token" }] }),
    claimed(2, { channel: "whatsapp", whatsapp_phone: "60111" }),
    claimed(3, { channel: null }),
  ]);
  try {
    const res = await fn.fetch(post());
    assertEquals(res.status, 200);
    const s = await res.json();
    assertEquals([s.sent, s.retry_scheduled, s.skipped, s.errors], [1, 1, 1, 0]);
    const c = t.b.completes;
    assertEquals([c[id(1)].p_status, c[id(1)].p_retry, c[id(1)].p_channel], ["failed", true, "push"]);
    assertStringIncludes(c[id(1)].p_error as string, "INTERNAL_ERROR");
    assertEquals(c[id(2)].p_status, "sent");
    assertEquals(c[id(3)].p_status, "skipped");
  } finally {
    t.restore();
  }
  // processItem 本身也不会丢错
  const o = await processItem(
    {
      id: id(9),
      event_type: "order_new",
      payload: {},
      locale: "zh",
      channel: "push",
      push_targets: [{ target: "x", kind: "token" }],
      whatsapp_phone: null,
      details: null,
    },
    { fcm: JSON.parse(broken), whatsapp: null },
  );
  assertEquals([o.status, o.retry], ["failed", true]);
});

/** 假的时钟：Meta 每个请求要 10 秒；回传每个请求开始时（离 t0）的时间 */
function fakeClock() {
  const realNow = Date.now;
  const t0 = realNow();
  let now = t0;
  Date.now = () => now;
  const inner = globalThis.fetch;
  const starts: number[] = [];
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    if (String(input).includes("graph.facebook.com")) {
      starts.push(now - t0);
      now += 10_000;
    }
    return await inner(input, init);
  }) as typeof fetch;
  return {
    t0,
    starts,
    restore: () => {
      Date.now = realNow;
      globalThis.fetch = inner;
    },
  };
}

Deno.test("dispatch 的期限也不能超过 worker 的总时间（一个 worker 接很多个请求）：晚进来的请求少发一点，不会发到一半被平台杀掉", async () => {
  // 免费方案（默认 WORKER_WALL_CLOCK_MS = 150 秒）：worker 已经跑了 60 秒 → 只剩 150 - 60 - 10（写结果）- 5 = 75 秒
  for (
    const [env, age, lastStart] of [[undefined, 60_000, 75_000], [
      "400000",
      60_000,
      100_000,
    ]] as const
  ) {
    const t = await setup({ WORKER_WALL_CLOCK_MS: env });
    t.b.batches.push(
      Array.from(
        { length: 50 },
        (_, i) => claimed(600 + i, { channel: "whatsapp", whatsapp_phone: "60111" }),
      ),
    );
    const clock = fakeClock();
    worker.startedAt = clock.t0 - age;
    try {
      const s = await (await fn.fetch(post())).json();
      assert(s.deferred > 0 && s.sent > 0, JSON.stringify(s));
      // 每个请求开始的时候，离 worker 被杀掉都还有 15 秒以上，写结果的宽限也在 worker 的时间里面
      assert(
        Math.max(...clock.starts) <= lastStart - DISPATCH_TIMING.itemMinMs,
        clock.starts.join(","),
      );
      assert(
        Math.max(...clock.starts) >
          lastStart - DISPATCH_TIMING.itemMinMs - 10_000,
        clock.starts.join(","),
      );
      assertEquals(Object.keys(t.b.completes).length + t.b.releases.length, 50);
      assertEquals(t.b.releases.length, s.deferred);
    } finally {
      clock.restore();
      t.restore();
    }
  }
  // worker 已经跑了 140 秒：根本不领（领到了也发不完）
  const t = await setup();
  t.b.batches.push([
    claimed(700, { channel: "whatsapp", whatsapp_phone: "60111" }),
  ]);
  worker.startedAt = Date.now() - 140_000;
  try {
    const s = await (await fn.fetch(post())).json();
    assertEquals([s.ok, s.rounds, s.claimed], [true, 0, 0]);
    assertEquals(t.b.batches.length, 1);
  } finally {
    t.restore();
  }
  assertEquals(
    dispatchDeadline(1_000_000, 100_000, 150_000, 1_000_000),
    1_100_000,
  );
  assertEquals(
    dispatchDeadline(1_100_000, 100_000, 150_000, 1_000_000),
    1_135_000,
  );
  assertEquals(
    dispatchDeadline(1_100_000, 100_000, 400_000, 1_000_000),
    1_200_000,
  );
});

Deno.test("worker 要被关掉（beforeunload）→ 不再领、不再开始发", async () => {
  const t = await setup();
  t.b.batches.push([
    claimed(800, { channel: "whatsapp", whatsapp_phone: "60111" }),
  ]);
  try {
    globalThis.dispatchEvent(
      new CustomEvent("beforeunload", { detail: { reason: "WallClockTime" } }),
    );
    assert(worker.stopping);
    const s = await (await fn.fetch(post())).json();
    assertEquals([s.claimed, t.b.templates.length], [0, 0]);
    assertEquals(t.b.batches.length, 1);
  } finally {
    t.restore();
  }
  assertEquals(worker.stopping, false);
});
