import { assert, assertEquals, assertFalse } from "@std/assert";
import {
  classifyWhatsAppError,
  hmacSha256Hex,
  normalizePhone,
  parseWebhook,
  sendTemplate,
  sendText,
  toE164,
  verifySignature,
} from "../_shared/whatsapp.ts";
import { fakeFetch } from "./_helpers.ts";

const enc = new TextEncoder();
const CFG = { token: "wa-token", phoneNumberId: "106540352242922", graphVersion: "v27.0" };

Deno.test("签名：对的通过；错的、没有、格式不对都不通过", async () => {
  const raw = enc.encode('{"object":"whatsapp_business_account","entry":[]}');
  const sig = await hmacSha256Hex("app-secret", raw);
  assert(await verifySignature(raw, `sha256=${sig}`, "app-secret"));
  assert(await verifySignature(raw, `sha256=${sig.toUpperCase()}`, "app-secret"));
  assertFalse(await verifySignature(raw, `sha256=${sig}`, "other-secret"));
  assertFalse(await verifySignature(enc.encode('{"object":"x"}'), `sha256=${sig}`, "app-secret"));
  assertFalse(await verifySignature(raw, null, "app-secret"));
  assertFalse(await verifySignature(raw, sig, "app-secret")); // 少了 sha256=
  assertFalse(await verifySignature(raw, "sha256=abc", "app-secret"));
  assertFalse(await verifySignature(raw, `sha256=${sig}`, ""));
});

Deno.test("HMAC 跟已知的值一样（RFC 4231 test case 2）", async () => {
  assertEquals(
    await hmacSha256Hex("Jefe", enc.encode("what do ya want for nothing?")),
    "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
  );
});

Deno.test("号码：只留数字、0 开头补 6、发送时加 +", () => {
  assertEquals(normalizePhone("+60 12-345 6789"), "60123456789");
  assertEquals(normalizePhone("012-3456789"), "60123456789");
  assertEquals(normalizePhone(""), null);
  assertEquals(toE164("60123456789"), "+60123456789");
  assertEquals(toE164("abc"), null);
});

function webhook(values: Record<string, unknown>[][]): unknown {
  return {
    object: "whatsapp_business_account",
    entry: values.map((changes, i) => ({
      id: `waba-${i}`,
      changes: changes.map((value) => ({ field: "messages", value })),
    })),
  };
}

Deno.test("webhook：一次多笔（多个 entry / change）、按钮、文字、语音、状态、BSUID", () => {
  const meta = { display_phone_number: "15550783881", phone_number_id: "106540352242922" };
  const events = parseWebhook(webhook([
    [{
      messaging_product: "whatsapp",
      metadata: meta,
      messages: [
        {
          context: { from: "15550783881", id: "wamid.OUT1" },
          from: "60123456789",
          from_user_id: "MY.111",
          id: "wamid.IN1",
          timestamp: "1750091045",
          type: "button",
          button: { payload: "CONFIRM:5b1c2d3e-0000-4000-8000-123456789abc", text: "确认订单" },
        },
        { from: "60123456789", id: "wamid.IN2", type: "text", text: { body: "要 2 箱杯" } },
      ],
    }, {
      metadata: meta,
      statuses: [{
        id: "wamid.OUT0",
        status: "failed",
        recipient_id: "60111",
        errors: [{ code: 131026, title: "Message undeliverable", error_data: { details: "not on WhatsApp" } }],
      }],
    }],
    [{
      metadata: meta,
      messages: [
        // 用户只有用户名：没有 from，只有 from_user_id
        {
          context: { id: "wamid.OUT2" },
          from_user_id: "MY.222",
          id: "wamid.IN3",
          type: "button",
          button: { payload: "OOS:5b1c2d3e-0000-4000-8000-123456789abc", text: "Out of stock" },
        },
        {
          from: "60199",
          id: "wamid.IN4",
          type: "audio",
          audio: { mime_type: "audio/ogg; codecs=opus", id: "MEDIA1", voice: true },
        },
        { from: "60199", id: "wamid.IN5", type: "image", image: { id: "MEDIA2", caption: "价目表" } },
        { from: "60199", id: "wamid.IN6", type: "sticker", sticker: { id: "MEDIA3" } },
        { from: "60199", type: "text", text: { body: "no id -> ignored" } },
      ],
      statuses: [{ id: "wamid.OUT1", status: "READ", recipient_id: "60123456789" }],
    }],
  ]));

  assertEquals(events.map((e) => `${e.kind}:${e.id}`), [
    "button:wamid.IN1",
    "message:wamid.IN2",
    "status:wamid.OUT0",
    "button:wamid.IN3",
    "message:wamid.IN4",
    "message:wamid.IN5",
    "message:wamid.IN6",
    "status:wamid.OUT1",
  ]);
  const [b1, t1, s0, b2, a1, i1, st1, s1] = events;
  assert(b1.kind === "button" && b2.kind === "button");
  assertEquals(b1.from, "60123456789");
  assertEquals(b1.fromUserId, "MY.111");
  assertEquals(b1.contextId, "wamid.OUT1");
  assertEquals(b1.payload, "CONFIRM:5b1c2d3e-0000-4000-8000-123456789abc");
  assertEquals(b1.phoneNumberId, "106540352242922");
  assertEquals(b2.from, null);
  assertEquals(b2.fromUserId, "MY.222");
  assertEquals(b2.contextId, "wamid.OUT2");
  assert(t1.kind === "message" && t1.type === "text" && t1.body === "要 2 箱杯");
  assert(a1.kind === "message" && a1.type === "audio" && a1.mediaId === "MEDIA1");
  assert(i1.kind === "message" && i1.type === "image" && i1.mediaId === "MEDIA2" && i1.body === "价目表");
  assert(st1.kind === "message" && st1.type === "other" && st1.mediaId === "MEDIA3");
  assert(s0.kind === "status");
  assertEquals(s0.status, "failed");
  assertEquals(s0.errorCode, 131026);
  assertEquals(s0.error, "Message undeliverable: not on WhatsApp");
  assert(s1.kind === "status" && s1.status === "read" && s1.errorCode === null);
});

Deno.test("webhook：不是 WhatsApp 的、别的 field、坏掉的内容 → 不处理", () => {
  assertEquals(parseWebhook({ object: "page", entry: [] }), []);
  assertEquals(parseWebhook(null), []);
  assertEquals(parseWebhook({ object: "whatsapp_business_account", entry: "x" }), []);
  assertEquals(
    parseWebhook({
      object: "whatsapp_business_account",
      entry: [{
        changes: [{ field: "message_template_status_update", value: { messages: [{ id: "x", type: "text" }] } }],
      }],
    }),
    [],
  );
});

Deno.test("webhook：普通互动按钮（interactive.button_reply）当成按钮", () => {
  const [e] = parseWebhook(webhook([[{
    messages: [{
      from: "601",
      id: "wamid.I",
      type: "interactive",
      interactive: { type: "button_reply", button_reply: { id: "CONFIRM:abc", title: "Confirm" } },
    }],
  }]]));
  assert(e.kind === "button" && e.payload === "CONFIRM:abc" && e.contextId === null);
});

Deno.test("错误分类：可以重试 / 不重试 / 要通知技术", () => {
  for (const code of [130429, 131056, 80007, 4, 131016, 133004, 131000]) {
    assert(classifyWhatsAppError(code, 400).retryable, String(code));
  }
  // 131026：要对方处理，不自动重试（但不是「永久死掉」）
  assertEquals(classifyWhatsAppError(131026, 400), { retryable: false, alert: false });
  for (const code of [132001, 132000, 132012, 132015, 132016, 131008, 131009, 100, 131021, 131047]) {
    assertFalse(classifyWhatsAppError(code, 400).retryable, String(code));
  }
  assert(classifyWhatsAppError(132001, 404).alert);
  // 我们的设定问题：通知技术、修好后会自动补发
  assertEquals(classifyWhatsAppError(190, 401), { retryable: true, alert: true });
  assertEquals(classifyWhatsAppError(131042, 400), { retryable: true, alert: true });
  assertEquals(classifyWhatsAppError(null, 503), { retryable: true, alert: false });
  assertEquals(classifyWhatsAppError(null, 0), { retryable: true, alert: false });
  assertEquals(classifyWhatsAppError(99999, 400), { retryable: false, alert: false });
});

Deno.test("发模板：+ 号码、具名参数、quick reply payload", async () => {
  const net = fakeFetch((c) =>
    c.url.host === "graph.facebook.com"
      ? Response.json({
        messaging_product: "whatsapp",
        contacts: [{ input: "+60123456789", wa_id: "60123456789" }],
        messages: [{ id: "wamid.SENT", message_status: "accepted" }],
      })
      : undefined
  );
  try {
    const r = await sendTemplate(CFG, "60123456789", {
      name: "order_new_v1",
      languageCode: "zh_CN",
      params: { order_no: "JHB1", shop_name: "阿成" },
      buttons: [{ index: 0, payload: "CONFIRM:x" }, { index: 1, payload: "OOS:x" }],
    });
    assertEquals(r, { ok: true, messageId: "wamid.SENT", messageStatus: "accepted" });
    const c = net.calls[0];
    assertEquals(c.url.toString(), "https://graph.facebook.com/v27.0/106540352242922/messages");
    assertEquals(c.headers.get("authorization"), "Bearer wa-token");
    assertEquals(c.json(), {
      messaging_product: "whatsapp",
      recipient_type: "individual",
      to: "+60123456789",
      type: "template",
      template: {
        name: "order_new_v1",
        language: { code: "zh_CN" },
        components: [
          {
            type: "body",
            parameters: [
              { type: "text", parameter_name: "order_no", text: "JHB1" },
              { type: "text", parameter_name: "shop_name", text: "阿成" },
            ],
          },
          {
            type: "button",
            sub_type: "quick_reply",
            index: "0",
            parameters: [{ type: "payload", payload: "CONFIRM:x" }],
          },
          { type: "button", sub_type: "quick_reply", index: "1", parameters: [{ type: "payload", payload: "OOS:x" }] },
        ],
      },
    });
  } finally {
    net.restore();
  }
});

Deno.test("发文字：只有 BSUID 时用 recipient；回覆在原消息上；错误回传分类", async () => {
  let n = 0;
  const net = fakeFetch((c) => {
    if (c.url.host !== "graph.facebook.com") return undefined;
    n++;
    if (n === 1) return Response.json({ messages: [{ id: "wamid.T1" }] });
    return Response.json({
      error: {
        message: "(#131047) Re-engagement message",
        type: "OAuthException",
        code: 131047,
        error_data: { messaging_product: "whatsapp", details: "More than 24 hours have passed" },
        fbtrace_id: "x",
      },
    }, { status: 400 });
  });
  try {
    const ok = await sendText(CFG, { userId: "MY.222" }, "你好", { replyTo: "wamid.IN3", phoneNumberId: "999" });
    assertEquals(ok, { ok: true, messageId: "wamid.T1", messageStatus: null });
    assertEquals(net.calls[0].url.pathname, "/v27.0/999/messages");
    assertEquals(net.calls[0].json(), {
      messaging_product: "whatsapp",
      recipient_type: "individual",
      recipient: "MY.222",
      context: { message_id: "wamid.IN3" },
      type: "text",
      text: { preview_url: false, body: "你好" },
    });
    const bad = await sendText(CFG, { phone: "0123456789" }, "hi");
    assertEquals(net.calls[1].json().to, "+60123456789");
    assert(!bad.ok);
    if (!bad.ok) {
      assertEquals(bad.code, 131047);
      assertEquals(bad.retryable, false);
      assertEquals(bad.message, "(#131047) Re-engagement message | More than 24 hours have passed");
    }
  } finally {
    net.restore();
  }
});

Deno.test("发送：网络断 → 可以重试；号码不对 → 不发", async () => {
  const net = fakeFetch(() => {
    throw new TypeError("connection reset");
  });
  try {
    const r = await sendText(CFG, { phone: "60123" }, "x");
    assert(!r.ok && r.retryable && r.httpStatus === 0);
    const bad = await sendText(CFG, { phone: "---" }, "x");
    assert(!bad.ok && !bad.retryable && bad.message === "INVALID_RECIPIENT");
    assertEquals(net.calls.length, 1);
  } finally {
    net.restore();
  }
});
