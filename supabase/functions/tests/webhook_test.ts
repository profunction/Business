import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import fn from "../whatsapp-webhook/index.ts";
import { hmacSha256Hex } from "../_shared/whatsapp.ts";
import {
  type Call,
  fakeEdgeRuntime,
  fakeFetch,
  isService,
  pgError,
  rpcName,
  SB_URL,
  setEnv,
  SUPABASE_ENV,
} from "./_helpers.ts";

const APP_SECRET = "meta-app-secret";
const VERIFY = "my-verify-token";
const ORDER_ID = "5b1c2d3e-0000-4000-8000-123456789abc";
const URL_ = `${SB_URL}/functions/v1/whatsapp-webhook`;

const ENV = {
  ...SUPABASE_ENV,
  WHATSAPP_APP_SECRET: APP_SECRET,
  WHATSAPP_VERIFY_TOKEN: VERIFY,
  WHATSAPP_TOKEN: "wa-token",
  WHATSAPP_PHONE_NUMBER_ID: "1065",
  WHATSAPP_GRAPH_VERSION: undefined,
};

async function signed(body: string, secret = APP_SECRET): Promise<Request> {
  const raw = new TextEncoder().encode(body);
  return new Request(URL_, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Hub-Signature-256": `sha256=${await hmacSha256Hex(secret, raw)}`,
    },
    body: raw,
  });
}

interface Db {
  rpc: { name: string; params: Record<string, unknown> }[];
  graph: Record<string, unknown>[];
  buttonResult: (p: Record<string, unknown>) => Response;
  failRecord?: Response;
}

function backend(db: Db) {
  return (c: Call): Response | undefined => {
    const name = rpcName(c);
    if (name) {
      if (!isService(c)) return pgError("NOT_ALLOWED", "42501", 403);
      const params = c.json();
      db.rpc.push({ name, params });
      if (name === "handle_whatsapp_button") return db.buttonResult(params);
      if (name === "record_whatsapp_message") return db.failRecord ?? Response.json({ result: "recorded", id: "m1" });
      if (name === "update_whatsapp_status") {
        return Response.json({ result: "updated", delivery_status: params.p_status });
      }
      return undefined;
    }
    if (c.url.host === "graph.facebook.com") {
      db.graph.push({ path: c.url.pathname, auth: c.headers.get("authorization"), ...c.json() });
      return Response.json({ messages: [{ id: `wamid.REPLY${db.graph.length}` }] });
    }
    return undefined;
  };
}

function setup(over: Partial<Db> = {}, env: Record<string, string | undefined> = {}) {
  const db: Db = {
    rpc: [],
    graph: [],
    buttonResult: () => Response.json({ result: "confirmed", order_no: "JHB1", status: "confirmed", locale: "en" }),
    ...over,
  };
  const restoreEnv = setEnv({ ...ENV, ...env });
  const net = fakeFetch(backend(db));
  return {
    db,
    net,
    restore: () => {
      net.restore();
      restoreEnv();
    },
  };
}

const button = (id: string, payload: string, from: string | null, extra: Record<string, unknown> = {}) => ({
  context: { from: "15550783881", id: "wamid.OUT1" },
  ...(from ? { from } : {}),
  from_user_id: "MY.13491208655302741918",
  id,
  timestamp: "1750091045",
  type: "button",
  button: { payload, text: "Confirm order" },
  ...extra,
});

const envelope = (values: Record<string, unknown>[]) =>
  JSON.stringify({
    object: "whatsapp_business_account",
    entry: values.map((value, i) => ({
      id: `waba${i}`,
      changes: [{
        field: "messages",
        value: {
          messaging_product: "whatsapp",
          metadata: { display_phone_number: "1555", phone_number_id: "1065" },
          ...value,
        },
      }],
    })),
  });

Deno.test("GET 握手：token 对 → 原样回 challenge（纯文字 200）；不对 → 403", async () => {
  const t = setup();
  try {
    const ok = await fn.fetch(
      new Request(`${URL_}?hub.mode=subscribe&hub.challenge=1158201444&hub.verify_token=${VERIFY}`),
    );
    assertEquals(ok.status, 200);
    assertEquals(await ok.text(), "1158201444");
    assertStringIncludes(ok.headers.get("content-type")!, "text/plain");
    const bad = await fn.fetch(new Request(`${URL_}?hub.mode=subscribe&hub.challenge=1&hub.verify_token=wrong`));
    assertEquals(bad.status, 403);
    assertEquals((await fn.fetch(new Request(`${URL_}?hub.challenge=1&hub.verify_token=${VERIFY}`))).status, 403);
    assertEquals(t.net.calls.length, 0);
  } finally {
    t.restore();
  }
  const t2 = setup({}, { WHATSAPP_VERIFY_TOKEN: undefined });
  try {
    const r = await fn.fetch(new Request(`${URL_}?hub.mode=subscribe&hub.challenge=1&hub.verify_token=`));
    assertEquals(r.status, 403);
  } finally {
    t2.restore();
  }
});

Deno.test("POST 签名：没有 / 不对 / body 被改过 → 401，不碰数据库", async () => {
  const t = setup();
  try {
    const body = envelope([{ messages: [button("wamid.IN1", `CONFIRM:${ORDER_ID}`, "60123456789")] }]);
    const noSig = await fn.fetch(new Request(URL_, { method: "POST", body }));
    assertEquals(noSig.status, 401);
    assertEquals((await fn.fetch(await signed(body, "wrong-secret"))).status, 401);
    const tampered = await signed(body);
    const forged = new Request(URL_, {
      method: "POST",
      headers: tampered.headers,
      body: body.replace("CONFIRM", "OOS:x"),
    });
    assertEquals((await fn.fetch(forged)).status, 401);
    assertEquals(t.db.rpc.length, 0);
    assertEquals(t.net.calls.length, 0);
  } finally {
    t.restore();
  }
});

Deno.test("POST：一次多笔（按钮、BSUID 按钮、重复、文字、语音、状态）全部处理，回复在背景发", async () => {
  const results: Record<string, unknown> = {
    "wamid.IN1": { result: "confirmed", order_no: "JHB261126-00012", status: "confirmed", locale: "en" },
    "wamid.IN2": { result: "out_of_stock", order_no: "JHB261126-00013", status: "out_of_stock", locale: "zh" },
    "wamid.IN3": { result: "duplicate" },
    "wamid.IN4": { result: "not_authorized", locale: null },
  };
  const t = setup({ buttonResult: (p) => Response.json(results[p.p_wa_message_id as string]) });
  const rt = fakeEdgeRuntime();
  try {
    const body = envelope([
      {
        messages: [
          button("wamid.IN1", `CONFIRM:${ORDER_ID}`, "60123456789"),
          // 只有 BSUID（用户用用户名，没有电话）
          button("wamid.IN2", `OOS:${ORDER_ID}`, null, { context: { id: "wamid.OUT2" } }),
        ],
      },
      {
        messages: [
          button("wamid.IN3", `CONFIRM:${ORDER_ID}`, "60123456789"), // Meta 重送
          button("wamid.IN4", `CONFIRM:${ORDER_ID}`, "60999"),
          { from: "60123456789", from_user_id: "MY.1", id: "wamid.T1", type: "text", text: { body: "明天要 5 箱" } },
          {
            from: "60123456789",
            id: "wamid.A1",
            type: "audio",
            audio: { id: "MEDIA9", mime_type: "audio/ogg; codecs=opus" },
          },
        ],
        statuses: [
          { id: "wamid.OUT1", status: "delivered", recipient_id: "60123456789" },
          {
            id: "wamid.OUT9",
            status: "failed",
            recipient_id: "60111",
            errors: [{ code: 131026, title: "Message undeliverable", error_data: { details: "not on WhatsApp" } }],
          },
        ],
      },
    ]);
    const res = await fn.fetch(await signed(body));
    assertEquals(res.status, 200);
    assertEquals(await res.json(), { ok: true, events: 8 });

    // 数据库写入照顺序、参数名照 SQL
    assertEquals(t.db.rpc.map((r) => r.name), [
      "handle_whatsapp_button",
      "handle_whatsapp_button",
      "handle_whatsapp_button",
      "handle_whatsapp_button",
      "record_whatsapp_message",
      "record_whatsapp_message",
      "update_whatsapp_status",
      "update_whatsapp_status",
    ]);
    const [b1, b2] = t.db.rpc;
    assertEquals(Object.keys(b1.params).sort(), [
      "p_context_id",
      "p_from",
      "p_from_user_id",
      "p_payload",
      "p_raw",
      "p_wa_message_id",
    ]);
    assertEquals(b1.params.p_from, "60123456789");
    assertEquals(b1.params.p_context_id, "wamid.OUT1");
    assertEquals(b1.params.p_payload, `CONFIRM:${ORDER_ID}`);
    assertEquals((b1.params.p_raw as Record<string, unknown>).id, "wamid.IN1");
    assertEquals(b2.params.p_from, null);
    assertEquals(b2.params.p_from_user_id, "MY.13491208655302741918");
    assertEquals(b2.params.p_context_id, "wamid.OUT2");
    assertEquals(t.db.rpc[4].params, {
      p_from: "60123456789",
      p_type: "text",
      p_body: "明天要 5 箱",
      p_media_id: null,
      p_wa_message_id: "wamid.T1",
      p_raw: { from: "60123456789", from_user_id: "MY.1", id: "wamid.T1", type: "text", text: { body: "明天要 5 箱" } },
    });
    assertEquals([t.db.rpc[5].params.p_type, t.db.rpc[5].params.p_media_id], ["audio", "MEDIA9"]);
    assertEquals(t.db.rpc[6].params, {
      p_wa_message_id: "wamid.OUT1",
      p_status: "delivered",
      p_error_code: null,
      p_error: null,
    });
    assertEquals(t.db.rpc[7].params, {
      p_wa_message_id: "wamid.OUT9",
      p_status: "failed",
      p_error_code: 131026,
      p_error: "Message undeliverable: not on WhatsApp",
    });

    // 回复：交给 waitUntil；duplicate 不回
    assertEquals(rt.pending.length, 1);
    await Promise.all(rt.pending);
    assertEquals(t.db.graph.length, 3);
    const [r1, r2, r3] = t.db.graph as Record<string, unknown>[];
    assertEquals(r1.to, "+60123456789");
    assertEquals(r1.context, { message_id: "wamid.IN1" });
    assertEquals(r1.text, {
      preview_url: false,
      body: "✅ Order JHB261126-00012 confirmed. Thank you! Please deliver on time.",
    });
    assertEquals(r1.path, "/v27.0/1065/messages");
    assertEquals(r1.auth, "Bearer wa-token");
    assertEquals(r2.recipient, "MY.13491208655302741918"); // 没有电话就用 BSUID
    assert(!("to" in r2));
    assertEquals((r2.text as { body: string }).body, "已记录订单 JHB261126-00013 缺货，我们会通知买家。谢谢！");
    assertEquals(r3.to, "+60999");
    assertStringIncludes((r3.text as { body: string }).body, "这个号码不能处理这张订单"); // locale null → zh
  } finally {
    rt.restore();
    t.restore();
  }
});

Deno.test("POST：没有 EdgeRuntime 时回复也会发完才回 200", async () => {
  const t = setup();
  try {
    const res = await fn.fetch(
      await signed(envelope([{ messages: [button("wamid.X", `CONFIRM:${ORDER_ID}`, "60123")] }])),
    );
    assertEquals(res.status, 200);
    assertEquals(t.db.graph.length, 1);
  } finally {
    t.restore();
  }
});

Deno.test("POST：数据库暂时有问题 → 500（Meta 重送）；资料本身错 → 记下来、回 200", async () => {
  const t = setup({ failRecord: new Response("upstream timeout", { status: 503 }) });
  try {
    const body = envelope([{
      messages: [
        { from: "601", id: "wamid.T1", type: "text", text: { body: "hi" } },
        button("wamid.B1", `CONFIRM:${ORDER_ID}`, "601"),
      ],
    }]);
    const res = await fn.fetch(await signed(body));
    assertEquals(res.status, 500);
    assertEquals(t.db.rpc.length, 2); // 后面那笔照样处理
    assertEquals(t.db.graph.length, 1);
  } finally {
    t.restore();
  }

  const t2 = setup({
    failRecord: Response.json({ message: "invalid input value for enum", code: "22P02" }, { status: 400 }),
  });
  try {
    const res = await fn.fetch(
      await signed(envelope([{ messages: [{ from: "601", id: "wamid.T2", type: "text", text: { body: "x" } }] }])),
    );
    assertEquals(res.status, 200);
  } finally {
    t2.restore();
  }
});

Deno.test("POST：不是 WhatsApp 的通知 → 200 不处理；没设 App Secret → 500；坏 JSON → 400", async () => {
  const t = setup();
  try {
    const res = await fn.fetch(await signed(JSON.stringify({ object: "page", entry: [] })));
    assertEquals(res.status, 200);
    assertEquals(await res.json(), { ok: true, events: 0 });
    assertEquals((await fn.fetch(await signed("{not json"))).status, 400);
    assertEquals((await fn.fetch(new Request(URL_, { method: "PUT" }))).status, 405);
  } finally {
    t.restore();
  }
  const t2 = setup({}, { WHATSAPP_APP_SECRET: undefined });
  try {
    assertEquals((await fn.fetch(await signed(envelope([])))).status, 500);
  } finally {
    t2.restore();
  }
});
