// 第六步：语音转文字（假的 ElevenLabs）、订单 AI（假的 Claude）、voice-order 函数、dispatcher 的 WhatsApp 回复。
import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import { keyterms, STT_URL, transcribe } from "../_shared/stt.ts";
import { normalizeOrder, ORDER_MODEL, type OrderProduct, renderProducts } from "../_shared/order_ai.ts";
import { sniffAudio } from "../_shared/filetype.ts";
import fn, { audioPathOk, MAX_AUDIO_BYTES } from "../voice-order/index.ts";
import { processItem } from "../dispatch-notifications/index.ts";
import {
  type Call,
  claudeStream,
  fakeFetch,
  isAnthropic,
  isService,
  PUBLISHABLE,
  rpcName,
  SB_URL,
  setEnv,
  SUPABASE_ENV,
} from "./_helpers.ts";

const SHOP = "dddddddd-0000-4000-8000-000000000001";
const P1 = "eeeeeeee-0000-4000-8000-000000000101";
const P2 = "eeeeeeee-0000-4000-8000-000000000102";
const USER_JWT = "user.jwt.token";
const USER_ID = "aaaaaaaa-0000-4000-8000-000000000001";
const PATH = `${SHOP}/0a1b2c3d-0000-4000-8000-0000000000aa.wav`;

export function wav(bytes = 64): Uint8Array {
  const b = new Uint8Array(44 + bytes);
  b.set(new TextEncoder().encode("RIFF"), 0);
  b.set(new TextEncoder().encode("WAVE"), 8);
  return b;
}

export const PRODUCTS: OrderProduct[] = [
  {
    product_id: P1,
    name: "16oz PP Cup 95mm",
    unit: "carton",
    pack_qty: 1000,
    min_order_qty: 1,
    stock_status: "in_stock",
    wholesaler_name: "JB Pack",
    catalog_name: { zh: "16安士杯", en: "16oz cup", ms: "Cawan 16oz" },
    times_bought: 3,
    last_qty: 2,
  },
  {
    product_id: P2,
    name: "95 平盖",
    unit: "carton",
    pack_qty: 1000,
    min_order_qty: 1,
    stock_status: "out_of_stock",
    wholesaler_name: "JB Pack",
    catalog_name: null,
    times_bought: 0,
    last_qty: null,
  },
];

export function orderJson(lines: Record<string, unknown>[], unmatched: Record<string, unknown>[] = []): string {
  return JSON.stringify({ language: "zh+yue", lines, unmatched });
}

Deno.test("keyterms：去掉不收的字、太长的、重复的，最多 100 个", () => {
  assertEquals(keyterms(["16oz <Cup>", "16OZ  cup", "a b c d e f", "x".repeat(51), "", "平盖"]), ["16oz Cup", "平盖"]);
  assertEquals(keyterms(Array.from({ length: 150 }, (_, i) => `p${i}`)).length, 100);
});

Deno.test("录音格式：看魔术字节", () => {
  assertEquals(sniffAudio(wav())?.ext, "wav");
  assertEquals(sniffAudio(new TextEncoder().encode("OggS\0\0\0\0\0\0\0\0\0"))?.mime, "audio/ogg");
  assertEquals(sniffAudio(new TextEncoder().encode("hello world, not audio")), null);
});

Deno.test("语音转文字：没设定 → STT_NOT_CONFIGURED；请求格式；限速；太长", async () => {
  assertEquals((await transcribe(null, wav(), "audio/wav")).ok, false);
  const seen: Call[] = [];
  let reply = () => Response.json({ language_code: "yue", text: " 两箱  十六安士杯 ", audio_duration_secs: 4.2 });
  const net = fakeFetch((c) => {
    if (c.url.href === STT_URL) {
      seen.push(c);
      return reply();
    }
    return undefined;
  });
  try {
    const r = await transcribe({ apiKey: "xi", model: "scribe_v3" }, wav(), "audio/wav", { terms: ["16oz cup"] });
    assertEquals(r, { ok: true, transcript: { text: "两箱 十六安士杯", language: "yue", durationSec: 4.2 } });
    assertEquals(seen[0].headers.get("xi-api-key"), "xi");
    assertStringIncludes(seen[0].text, 'name="model_id"\r\n\r\nscribe_v3');
    assertStringIncludes(seen[0].text, 'name="keyterms"\r\n\r\n16oz cup');
    assertStringIncludes(seen[0].text, 'name="secondary_language_codes"\r\n\r\nyue');
    const v2 = await transcribe({ apiKey: "xi", model: "scribe_v2" }, wav(), "audio/wav");
    assert(v2.ok);
    assert(!seen[1].text.includes("secondary_language_codes"), "v2 不送 secondary_language_codes");
    reply = () => Response.json({ detail: "rate limited" }, { status: 429 });
    assertEquals((await transcribe({ apiKey: "xi", model: "scribe_v2" }, wav(), "audio/wav")).ok, false);
    reply = () => Response.json({ detail: "bad key" }, { status: 401 });
    const bad = await transcribe({ apiKey: "xi", model: "scribe_v2" }, wav(), "audio/wav");
    assertEquals(bad.ok ? null : bad.code, "STT_AUTH_FAILED");
    reply = () => Response.json({ text: "x", audio_duration_secs: 600 });
    const long = await transcribe({ apiKey: "xi", model: "scribe_v2" }, wav(), "audio/wav");
    assertEquals(long.ok ? null : long.code, "AUDIO_TOO_LONG");
  } finally {
    net.restore();
  }
});

Deno.test("订单 AI：商品用代号给 Claude；回来的代号换成 id，不认得的放进 unmatched", () => {
  const text = renderProducts(PRODUCTS);
  assertStringIncludes(
    text,
    "p1 | 16oz PP Cup 95mm | (16安士杯 / 16oz cup / Cawan 16oz) | unit=carton | pack_qty=1000",
  );
  assertStringIncludes(text, "bought=3 | last=2");
  assertStringIncludes(text, "p2 | 95 平盖 | unit=carton | pack_qty=1000 | stock=out_of_stock");
  const out = normalizeOrder({
    language: "zh",
    lines: [
      { product_ref: "p1", qty: 2, said: "两箱杯", confidence: 1.4 },
      { product_ref: "P2", qty: 0, said: "盖", confidence: 0.5 },
      { product_ref: "p9", qty: 1, said: "吸管", confidence: 0.9 },
    ],
    unmatched: [{ said: "明天十点前送", reason: "note" }, { said: " ", reason: "x" }],
  }, PRODUCTS);
  assertEquals(out, {
    language: "zh",
    lines: [
      { product_id: P1, qty: 2, said: "两箱杯", confidence: 1 },
      { product_id: P2, qty: null, said: "盖", confidence: 0.5 },
    ],
    unmatched: [{ said: "吸管", reason: "unknown product" }, { said: "明天十点前送", reason: "note" }],
  });
  assertEquals(normalizeOrder({ lines: "x" }, PRODUCTS), null);
});

// ---------------------------------------------------------------------------
// voice-order 函数
// ---------------------------------------------------------------------------

interface World {
  reserve: Record<string, unknown>;
  files: Record<string, Uint8Array>;
  rpc: { name: string; params: Record<string, unknown> }[];
  claude: Call[];
  claudeReply: () => Response;
  stt: () => Response;
}

function world(over: Partial<World> = {}): World {
  return {
    reserve: { result: "ok", run_id: "r", shop_id: SHOP, locale: "zh" },
    files: { [PATH]: wav() },
    rpc: [],
    claude: [],
    claudeReply: () =>
      claudeStream({
        blocks: [{ type: "thinking" }, {
          type: "text",
          text: orderJson([{ product_ref: "p1", qty: 2, said: "两箱十六安士杯", confidence: 0.9 }], [{
            said: "吸管",
            reason: "not in list",
          }]),
        }],
      }),
    stt: () => Response.json({ language_code: "zh", text: "两箱十六安士杯，还有吸管", audio_duration_secs: 3 }),
    ...over,
  };
}

function backend(w: World) {
  return (c: Call): Response | undefined => {
    const p = c.url.pathname;
    if (p === "/auth/v1/user") {
      if (c.headers.get("authorization") !== `Bearer ${USER_JWT}`) {
        return Response.json({ code: 401, error_code: "bad_jwt", msg: "invalid JWT" }, { status: 401 });
      }
      return Response.json({ id: USER_ID, aud: "authenticated", role: "authenticated" });
    }
    const name = rpcName(c);
    if (name) {
      const params = c.json();
      w.rpc.push({ name, params });
      if (name === "get_order_draft") {
        // 用老板的身份读
        assertEquals(c.headers.get("apikey"), PUBLISHABLE);
        return Response.json({ id: params.p_draft_id, status: "pending_review", items: [] });
      }
      assert(isService(c), name);
      if (name === "reserve_voice_order_run") return Response.json(w.reserve);
      if (name === "get_voice_order_context") return Response.json({ shop_id: SHOP, products: PRODUCTS });
      if (name === "create_order_draft") {
        return Response.json({ result: "created", draft_id: "d1", shop_id: SHOP, item_count: 1, unmatched_count: 1 });
      }
      if (name === "fail_voice_order_run") return Response.json(true);
      return undefined;
    }
    if (p.startsWith("/storage/v1/object/voice-orders/") && c.method === "GET") {
      assert(isService(c));
      const f = w.files[decodeURIComponent(p.slice("/storage/v1/object/voice-orders/".length))];
      if (!f) {
        return Response.json({ statusCode: "404", error: "not_found", message: "Object not found" }, { status: 400 });
      }
      return new Response(f as Uint8Array<ArrayBuffer>);
    }
    if (c.url.href === STT_URL) return w.stt();
    if (isAnthropic(c)) {
      w.claude.push(c);
      return w.claudeReply();
    }
    return undefined;
  };
}

const ENV = { ...SUPABASE_ENV, ELEVENLABS_API_KEY: "xi-key", STT_MODEL: undefined, ANTHROPIC_API_KEY: "sk-ant-test" };

function call(body: unknown, jwt: string | null = USER_JWT): Promise<Response> {
  return fn.fetch(
    new Request(`${SB_URL}/functions/v1/voice-order`, {
      method: "POST",
      headers: { "Content-Type": "application/json", ...(jwt ? { Authorization: `Bearer ${jwt}` } : {}) },
      body: JSON.stringify(body),
    }),
  );
}

async function withWorld<T>(w: World, env: Record<string, string | undefined>, run: () => Promise<T>): Promise<T> {
  const restoreEnv = setEnv({ ...ENV, ...env });
  const net = fakeFetch(backend(w));
  try {
    return await run();
  } finally {
    net.restore();
    restoreEnv();
  }
}

Deno.test("voice-order：录音 → 转文字 → Claude → 草稿，用老板的身份读回来", async () => {
  const w = world();
  await withWorld(w, {}, async () => {
    const res = await call({ shop_id: SHOP, audio_path: PATH });
    assertEquals(res.status, 200);
    assertEquals((await res.json()).draft.id, "d1");
    const reserve = w.rpc.find((r) => r.name === "reserve_voice_order_run")!;
    assertEquals(reserve.params.p_user_id, USER_ID);
    assertEquals(reserve.params.p_source, "app_voice");
    assertEquals(reserve.params.p_audio_path, PATH);
    const create = w.rpc.find((r) => r.name === "create_order_draft")!;
    assertEquals(create.params.p_run_id, reserve.params.p_run_id);
    assertEquals(create.params.p_transcript, "两箱十六安士杯，还有吸管");
    assertEquals(create.params.p_lines, [{ product_id: P1, qty: 2, said: "两箱十六安士杯", confidence: 0.9 }]);
    assertEquals(create.params.p_unmatched, [{ said: "吸管", reason: "not in list" }]);
    assertEquals(create.params.p_audio_path, PATH);
    // Claude 的请求：模型、结构化输出、fallback、商品代号、老板的话放在标签里
    const req = w.claude[0].json();
    assertEquals(req.model, ORDER_MODEL);
    assertEquals(req.output_config.format.type, "json_schema");
    assertEquals(req.fallbacks, "default");
    assert(!("temperature" in req));
    const userText = req.messages[0].content.map((b: { text: string }) => b.text).join("\n");
    assertStringIncludes(userText, "p1 | 16oz PP Cup 95mm");
    assert(/<order_text id="[0-9a-f]{8}">\n两箱十六安士杯，还有吸管\n<\/order_text id="[0-9a-f]{8}">/.test(userText));
  });
});

Deno.test("voice-order：没登录 / 参数 / 路径 / 不是成员 / 用量满了", async () => {
  const w = world();
  await withWorld(w, {}, async () => {
    assertEquals((await call({ shop_id: SHOP, audio_path: PATH }, null)).status, 401);
    assertEquals((await call({ shop_id: SHOP, audio_path: PATH }, "bad")).status, 401);
    assertEquals((await call({ shop_id: "x", audio_path: PATH })).status, 400);
    const other = await call({ shop_id: SHOP, audio_path: `dddddddd-0000-4000-8000-000000000002/a.wav` });
    assertEquals([other.status, (await other.json()).error], [400, "INVALID_FILE_PATH"]);
    assertEquals(audioPathOk(SHOP, PATH), true);
    assertEquals(audioPathOk(SHOP, `${SHOP}/../x.wav`), false);
    w.reserve = { result: "not_member" };
    assertEquals((await call({ shop_id: SHOP, audio_path: PATH })).status, 403);
    w.reserve = { result: "quota", retry_after_sec: 42.2, window: "10m" };
    const q = await call({ shop_id: SHOP, audio_path: PATH });
    assertEquals([q.status, q.headers.get("retry-after")], [429, "43"]);
    assertEquals(await q.json(), { error: "TOO_MANY_VOICE_ORDERS", retry_after: 43 });
    assertEquals(w.claude.length, 0);
  });
});

Deno.test("voice-order：找不到录音 / 不是录音 / 太大 → 记失败，不叫 AI", async () => {
  const w = world({ files: { [PATH]: new TextEncoder().encode("this is not audio at all") } });
  await withWorld(w, {}, async () => {
    const r = await call({ shop_id: SHOP, audio_path: PATH });
    assertEquals([r.status, (await r.json()).error], [415, "UNSUPPORTED_AUDIO"]);
    w.files = {};
    assertEquals((await call({ shop_id: SHOP, audio_path: PATH })).status, 404);
    w.files = { [PATH]: wav(MAX_AUDIO_BYTES) };
    assertEquals((await call({ shop_id: SHOP, audio_path: PATH })).status, 413);
    assertEquals(
      w.rpc.filter((x) => x.name === "fail_voice_order_run").map((x) => x.params.p_error_code),
      ["UNSUPPORTED_AUDIO", "AUDIO_NOT_FOUND", "AUDIO_TOO_LARGE"],
    );
    assertEquals(w.claude.length, 0);
  });
});

Deno.test("voice-order：没设定语音 / AI → 503；没说话 → 422；Claude 拒绝 → 422（都记失败，不建草稿）", async () => {
  const w = world();
  await withWorld(w, { ELEVENLABS_API_KEY: undefined }, async () => {
    const r = await call({ shop_id: SHOP, audio_path: PATH });
    assertEquals([r.status, (await r.json()).error], [503, "STT_NOT_CONFIGURED"]);
  });
  await withWorld(w, { ANTHROPIC_API_KEY: undefined }, async () => {
    const r = await call({ shop_id: SHOP, audio_path: PATH });
    assertEquals([r.status, (await r.json()).error], [503, "AI_NOT_CONFIGURED"]);
  });
  w.stt = () => Response.json({ text: "  ", audio_duration_secs: 2 });
  await withWorld(w, {}, async () => {
    const r = await call({ shop_id: SHOP, audio_path: PATH });
    assertEquals([r.status, (await r.json()).error], [422, "NO_SPEECH"]);
  });
  w.stt = world().stt;
  w.claudeReply = () => claudeStream({ blocks: [], stopReason: "refusal", stopDetails: { category: "cyber" } });
  await withWorld(w, {}, async () => {
    const r = await call({ shop_id: SHOP, audio_path: PATH });
    assertEquals([r.status, (await r.json()).error], [422, "AI_REFUSED"]);
  });
  assertEquals(
    w.rpc.filter((x) => x.name === "fail_voice_order_run").map((x) => x.params.p_error_code),
    ["STT_NOT_CONFIGURED", "AI_NOT_CONFIGURED", "NO_SPEECH", "AI_REFUSED"],
  );
  assertEquals(w.rpc.filter((x) => x.name === "create_order_draft").length, 0);
});

Deno.test("dispatcher：WhatsApp 回复用普通文字发（payload.text）；没文字 → skipped", async () => {
  const sent: Record<string, unknown>[] = [];
  const net = fakeFetch((c) => {
    if (c.url.host === "graph.facebook.com") {
      sent.push(c.json());
      return Response.json({ messages: [{ id: "wamid.R1" }] });
    }
    return undefined;
  });
  try {
    const services = {
      fcm: null,
      whatsapp: { token: "t", phoneNumberId: "1065", graphVersion: "v27.0" },
      deadline: Date.now() + 10_000,
    };
    const item = {
      id: "aaaaaaaa-0000-4000-8000-0000000000ff",
      event_type: "whatsapp_reply",
      payload: { text: "已经帮您下单：JHB1。" },
      locale: "zh",
      channel: "whatsapp" as const,
      push_targets: [],
      whatsapp_phone: "60111000002",
      details: null,
    };
    const out = await processItem(item, services);
    assertEquals([out.status, out.waMessageId], ["sent", "wamid.R1"]);
    assertEquals(sent[0].type, "text");
    assertEquals(sent[0].to, "+60111000002");
    assertEquals((sent[0].text as { body: string }).body, "已经帮您下单：JHB1。");
    assertEquals((await processItem({ ...item, payload: {} }, services)).status, "skipped");
  } finally {
    net.restore();
  }
});
