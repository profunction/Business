// 第六步：WhatsApp 下单（webhook）：店的号码发文字 / 语音 → 草稿 + 回「收到」；不认识的号码 → 「请先注册」；照片 → 「请用文字或语音」
import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import fn from "../whatsapp-webhook/index.ts";
import { hmacSha256Hex } from "../_shared/whatsapp.ts";
import { STT_URL } from "../_shared/stt.ts";
import { REGISTER_REPLY } from "../_shared/messages.ts";
import {
  type Call,
  claudeStream,
  fakeEdgeRuntime,
  fakeFetch,
  isAnthropic,
  isService,
  rpcName,
  SB_URL,
  setEnv,
  SUPABASE_ENV,
} from "./_helpers.ts";
import { orderJson, PRODUCTS } from "./voice_test.ts";

const APP_SECRET = "meta-app-secret";
const SHOP = "dddddddd-0000-4000-8000-000000000002";
const ENV = {
  ...SUPABASE_ENV,
  WHATSAPP_APP_SECRET: APP_SECRET,
  WHATSAPP_VERIFY_TOKEN: "v",
  WHATSAPP_TOKEN: "wa-token",
  WHATSAPP_PHONE_NUMBER_ID: "1065",
  WHATSAPP_GRAPH_VERSION: undefined,
  ELEVENLABS_API_KEY: "xi",
  ANTHROPIC_API_KEY: "sk-ant-test",
};

async function signed(body: string): Promise<Request> {
  const raw = new TextEncoder().encode(body);
  return new Request(`${SB_URL}/functions/v1/whatsapp-webhook`, {
    method: "POST",
    headers: { "X-Hub-Signature-256": `sha256=${await hmacSha256Hex(APP_SECRET, raw)}` },
    body: raw,
  });
}

const envelope = (messages: Record<string, unknown>[]) =>
  JSON.stringify({
    object: "whatsapp_business_account",
    entry: [{
      id: "waba",
      changes: [{
        field: "messages",
        value: { messaging_product: "whatsapp", metadata: { phone_number_id: "1065" }, messages },
      }],
    }],
  });

interface W {
  intake: Record<string, unknown>;
  rpc: { name: string; params: Record<string, unknown> }[];
  graph: Record<string, unknown>[];
  uploads: string[];
  stt: number;
}

function backend(w: W) {
  return (c: Call): Response | undefined => {
    const name = rpcName(c);
    if (name) {
      assert(isService(c));
      const params = c.json();
      w.rpc.push({ name, params });
      if (name === "record_whatsapp_message") return Response.json({ result: "recorded", id: crypto.randomUUID() });
      if (name === "reserve_whatsapp_order") return Response.json(w.intake);
      if (name === "get_voice_order_context") return Response.json({ products: PRODUCTS });
      if (name === "create_order_draft") {
        const n = Array.isArray(params.p_lines) ? params.p_lines.length : 0;
        return Response.json({ result: "created", draft_id: "d1", shop_id: SHOP, item_count: n, unmatched_count: 0 });
      }
      if (name === "fail_voice_order_run") return Response.json(true);
      return undefined;
    }
    if (c.url.host === "graph.facebook.com") {
      if (c.method === "GET" && c.url.pathname === "/v27.0/MEDIA7") {
        return Response.json({ url: "https://lookaside.fbsbx.com/media/7", mime_type: "audio/ogg", file_size: 60 });
      }
      w.graph.push(c.json());
      return Response.json({ messages: [{ id: `wamid.R${w.graph.length}` }] });
    }
    if (c.url.host === "lookaside.fbsbx.com") {
      assertEquals(c.headers.get("authorization"), "Bearer wa-token");
      return new Response(new TextEncoder().encode("OggS\0\0\0\0\0\0\0\0\0\0\0\0"));
    }
    if (c.url.pathname.startsWith("/storage/v1/object/voice-orders/") && c.method === "POST") {
      w.uploads.push(c.url.pathname);
      return Response.json({ Key: c.url.pathname });
    }
    if (c.url.href === STT_URL) {
      w.stt++;
      return Response.json({ text: "nng kotak sap lak oz cup", language_code: "nan", audio_duration_secs: 3 });
    }
    if (isAnthropic(c)) {
      return claudeStream({
        blocks: [{
          type: "text",
          text: orderJson([{ product_ref: "p1", qty: 2, said: "nng kotak sap lak oz cup", confidence: 0.7 }]),
        }],
      });
    }
    return undefined;
  };
}

async function run(w: W, messages: Record<string, unknown>[], env: Record<string, string | undefined> = {}) {
  const restore = setEnv({ ...ENV, ...env });
  const net = fakeFetch(backend(w));
  const rt = fakeEdgeRuntime();
  try {
    const res = await fn.fetch(await signed(envelope(messages)));
    assertEquals(res.status, 200);
    await Promise.all(rt.pending);
    assertEquals(net.unexpected, []);
  } finally {
    rt.restore();
    net.restore();
    restore();
  }
}

const newW = (intake: Record<string, unknown>): W => ({ intake, rpc: [], graph: [], uploads: [], stt: 0 });

Deno.test("WhatsApp 文字：店的号码 → 草稿 → 回「收到」（店的语言、回在那条消息上）", async () => {
  const w = newW({
    result: "ok",
    run_id: "run-1",
    shop_id: SHOP,
    locale: "ms",
    message_type: "text",
    body: "2 karton cawan 16oz",
  });
  await run(w, [{ from: "60111000002", id: "wamid.T1", type: "text", text: { body: "2 karton cawan 16oz" } }]);
  assertEquals(w.rpc.map((r) => r.name), [
    "record_whatsapp_message",
    "reserve_whatsapp_order",
    "get_voice_order_context",
    "create_order_draft",
  ]);
  const create = w.rpc[3].params;
  assertEquals(create.p_run_id, "run-1");
  assertEquals(create.p_transcript, "2 karton cawan 16oz");
  assertEquals(w.stt, 0, "文字不用转");
  assertEquals(w.graph.length, 1);
  assertEquals(w.graph[0].to, "+60111000002");
  assertEquals(w.graph[0].context, { message_id: "wamid.T1" });
  assertStringIncludes((w.graph[0].text as { body: string }).body, "Pesanan anda diterima (1 barang)");
});

Deno.test("WhatsApp 语音：从 Graph 下载 → 存到 voice-orders/<店>/ → 转文字 → 草稿", async () => {
  const w = newW({
    result: "ok",
    run_id: "run-2",
    shop_id: SHOP,
    locale: "zh",
    message_type: "audio",
    media_id: "MEDIA7",
  });
  await run(w, [{
    from: "60111000002",
    id: "wamid.A1",
    type: "audio",
    audio: { id: "MEDIA7", mime_type: "audio/ogg" },
  }]);
  assertEquals(w.uploads.length, 1);
  assert(w.uploads[0].startsWith(`/storage/v1/object/voice-orders/${SHOP}/`) && w.uploads[0].endsWith(".ogg"));
  assertEquals(w.stt, 1);
  const create = w.rpc.find((r) => r.name === "create_order_draft")!.params;
  assertEquals(create.p_transcript, "nng kotak sap lak oz cup");
  assertEquals(create.p_audio_path, w.uploads[0].slice("/storage/v1/object/voice-orders/".length));
  assertStringIncludes((w.graph[0].text as { body: string }).body, "收到您的订单（1 样）");
});

Deno.test("WhatsApp 语音：AI 没设定 → 照样建空草稿（error_code），回「客服会看一下」", async () => {
  const w = newW({
    result: "ok",
    run_id: "run-3",
    shop_id: SHOP,
    locale: "en",
    message_type: "audio",
    media_id: "MEDIA7",
  });
  await run(w, [{ from: "60111000002", id: "wamid.A2", type: "audio", audio: { id: "MEDIA7" } }], {
    ANTHROPIC_API_KEY: undefined,
  });
  const create = w.rpc.find((r) => r.name === "create_order_draft")!.params;
  assertEquals((create.p_ai_meta as Record<string, unknown>).error_code, "AI_NOT_CONFIGURED");
  assertEquals(create.p_lines, []);
  assertStringIncludes((w.graph[0].text as { body: string }).body, "Our team will take a look");
});

Deno.test("WhatsApp：不认识的号码 → 请先注册（三种语言）；照片 → 请用文字或语音；reply=false 不回", async () => {
  const w = newW({ result: "unknown_sender", reply: true });
  await run(w, [{ from: "60199999999", id: "wamid.U1", type: "text", text: { body: "hi" } }]);
  assertEquals((w.graph[0].text as { body: string }).body, REGISTER_REPLY);
  assertEquals(w.rpc.filter((r) => r.name === "create_order_draft").length, 0);

  const w2 = newW({ result: "unsupported", reply: true, locale: "zh" });
  await run(w2, [{ from: "60111000002", id: "wamid.I1", type: "image", image: { id: "M1" } }]);
  assertStringIncludes((w2.graph[0].text as { body: string }).body, "请用文字或语音");

  const w3 = newW({ result: "unknown_sender", reply: false });
  await run(w3, [{ from: "60199999999", id: "wamid.U2", type: "text", text: { body: "hello?" } }]);
  assertEquals(w3.graph.length, 0);
  const w4 = newW({ result: "quota", shop_id: SHOP });
  await run(w4, [{ from: "60111000002", id: "wamid.T9", type: "text", text: { body: "x" } }]);
  assertEquals(w4.graph.length, 0);
});
