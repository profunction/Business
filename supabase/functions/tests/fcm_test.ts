import { assert, assertEquals, assertFalse } from "@std/assert";
import {
  buildFcmMessage,
  classifyFcmError,
  clearFcmTokenCache,
  getAccessToken,
  sendFcm,
  signServiceAccountJwt,
} from "../_shared/fcm.ts";
import type { PushContent } from "../_shared/messages.ts";
import { fakeFetch } from "./_helpers.ts";
import { googleTokenEndpoint, testServiceAccount } from "./_google.ts";

const CONTENT: PushContent = {
  title: "新订单 JHB1",
  body: "阿成，RM10.00",
  data: { type: "order_new", order_id: "o1", notification_id: "n1" },
  ttlSeconds: 86400,
  tag: "order-o1",
};

const fcmErr = (status: number, s: string, errorCode?: string, extra: Record<string, unknown>[] = []) =>
  Response.json({
    error: {
      code: status,
      message: `${s} message`,
      status: s,
      details: [
        ...(errorCode ? [{ "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError", errorCode }] : []),
        ...extra,
      ],
    },
  }, { status });

Deno.test("JWT 用 WebCrypto 签（RS256），Google 端点验得过；token 会缓存", async () => {
  clearFcmTokenCache();
  const { sa, publicKey } = await testServiceAccount();
  let issued = 0;
  const net = fakeFetch((c) => {
    if (c.url.toString() === "https://oauth2.googleapis.com/token") {
      return googleTokenEndpoint(c, publicKey, `ya29.t${++issued}`);
    }
  });
  try {
    const jwt = await signServiceAccountJwt(sa, 1_800_000_000);
    assertEquals(jwt.split(".").length, 3);
    assertEquals(await getAccessToken(sa), "ya29.t1");
    assertEquals(await getAccessToken(sa), "ya29.t1"); // 缓存
    assertEquals(await getAccessToken(sa, true), "ya29.t2"); // 强制重拿
    assertEquals(await getAccessToken(sa, true, "ya29.t1"), "ya29.t2"); // 被拒绝的是旧的：用现在缓存的新的
    assertEquals(net.calls.length, 2);
    // 环境变量里 \n 是字面两个字也读得懂
    const escaped = { ...sa, client_email: `x-${sa.client_email}`, private_key: sa.private_key.replace(/\n/g, "\\n") };
    assertEquals(await getAccessToken(escaped), "ya29.t3");
  } finally {
    net.restore();
  }
});

Deno.test("同时发很多条：只拿一次 OAuth token", async () => {
  clearFcmTokenCache();
  const { sa, publicKey } = await testServiceAccount();
  let issued = 0;
  const net = fakeFetch((c) => {
    if (c.url.host === "oauth2.googleapis.com") return googleTokenEndpoint(c, publicKey, `ya29.t${++issued}`);
    if (c.url.host === "fcm.googleapis.com") return Response.json({ name: "projects/p/messages/1" });
  });
  try {
    const results = await Promise.all(
      Array.from({ length: 8 }, (_, i) => sendFcm(sa, { target: `tok-${i}`, kind: "token" }, CONTENT)),
    );
    assert(results.every((r) => r.ok));
    assertEquals(issued, 1);
  } finally {
    net.restore();
  }
});

Deno.test("FCM 讯息：token / fid、data 字串、Android 频道 orders、APNs alert", () => {
  const m = buildFcmMessage({ target: "fid-1", kind: "fid" }, CONTENT, 1000).message as Record<string, unknown>;
  assertEquals(m.fid, "fid-1");
  assertFalse("token" in m);
  assertEquals(m.notification, { title: "新订单 JHB1", body: "阿成，RM10.00" });
  assertEquals(m.data, CONTENT.data);
  assertEquals(m.android, {
    priority: "high",
    ttl: "86400s",
    notification: { channel_id: "orders", sound: "default", tag: "order-o1" },
  });
  assertEquals((m.apns as Record<string, unknown>).headers, {
    "apns-priority": "10",
    "apns-expiration": "87400",
    "apns-collapse-id": "order-o1",
  });
  const t = buildFcmMessage({ target: "tok-1", kind: "token" }, { ...CONTENT, tag: null }).message as Record<
    string,
    unknown
  >;
  assertEquals(t.token, "tok-1");
});

Deno.test("错误分类：UNREGISTERED 删、payload 错不删、APNs 设定不删、限速重试", async () => {
  const badReq = {
    "@type": "type.googleapis.com/google.rpc.BadRequest",
    fieldViolations: [{ field: "message.data[0].value" }],
  };
  const body = async (r: Response) => await r.json();
  {
    assert(classifyFcmError(404, await body(fcmErr(404, "NOT_FOUND", "UNREGISTERED"))).dead);
    assert(classifyFcmError(400, await body(fcmErr(400, "INVALID_ARGUMENT", "INVALID_ARGUMENT"))).dead);
    // payload 错（有 BadRequest）→ 不删、不重试
    const payload = classifyFcmError(400, await body(fcmErr(400, "INVALID_ARGUMENT", "INVALID_ARGUMENT", [badReq])));
    assertEquals([payload.dead, payload.retryable], [false, false]);
    // 只看 HTTP 404 不算（要 details 里的 UNREGISTERED）
    assertFalse(classifyFcmError(404, await body(fcmErr(404, "NOT_FOUND"))).dead);
    const apns = classifyFcmError(401, await body(fcmErr(401, "UNAUTHENTICATED", "THIRD_PARTY_AUTH_ERROR")));
    assertEquals([apns.dead, apns.retryable, apns.errorCode], [false, false, "THIRD_PARTY_AUTH_ERROR"]);
    assertFalse(classifyFcmError(403, await body(fcmErr(403, "PERMISSION_DENIED", "SENDER_ID_MISMATCH"))).dead);
    for (const [code, s] of [[429, "RESOURCE_EXHAUSTED"], [500, "INTERNAL"], [503, "UNAVAILABLE"]] as const) {
      const r = classifyFcmError(code, await body(fcmErr(code, s, code === 429 ? "QUOTA_EXCEEDED" : undefined)));
      assertEquals([r.dead, r.retryable], [false, true]);
    }
    assertEquals(classifyFcmError(502, null).status, "HTTP_502");
  }
});

Deno.test("OAuth token 过期（401 UNAUTHENTICATED 没有 FcmError）→ 重拿一次再发", async () => {
  clearFcmTokenCache();
  const { sa, publicKey } = await testServiceAccount();
  let issued = 0;
  const net = fakeFetch((c) => {
    if (c.url.host === "oauth2.googleapis.com") return googleTokenEndpoint(c, publicKey, `ya29.t${++issued}`);
    if (c.url.toString() === "https://fcm.googleapis.com/v1/projects/test-project/messages:send") {
      if (c.headers.get("authorization") === "Bearer ya29.t1") return fcmErr(401, "UNAUTHENTICATED");
      return Response.json({ name: "projects/test-project/messages/123" });
    }
  });
  try {
    const r = await sendFcm(sa, { target: "tok", kind: "token" }, CONTENT);
    assertEquals(r, { ok: true, name: "projects/test-project/messages/123" });
    assertEquals(issued, 2);
    assertEquals(net.calls.filter((c) => c.url.host === "fcm.googleapis.com").length, 2);
  } finally {
    net.restore();
  }
});

Deno.test("THIRD_PARTY_AUTH_ERROR（也是 401）不会重拿 token、不删", async () => {
  clearFcmTokenCache();
  const { sa, publicKey } = await testServiceAccount();
  const net = fakeFetch((c) => {
    if (c.url.host === "oauth2.googleapis.com") return googleTokenEndpoint(c, publicKey, "ya29.x");
    if (c.url.host === "fcm.googleapis.com") return fcmErr(401, "UNAUTHENTICATED", "THIRD_PARTY_AUTH_ERROR");
  });
  try {
    const r = await sendFcm(sa, { target: "tok", kind: "token" }, CONTENT);
    assert(!r.ok && !r.dead && !r.retryable && r.errorCode === "THIRD_PARTY_AUTH_ERROR");
    assertEquals(net.calls.length, 2); // 1 次 token + 1 次发送
  } finally {
    net.restore();
  }
});

Deno.test("Google token 端点拒绝（钥匙不对）→ 不重试；网络断 → 可以重试", async () => {
  clearFcmTokenCache();
  const { sa } = await testServiceAccount();
  let mode = "reject";
  const net = fakeFetch((c) => {
    if (c.url.host !== "oauth2.googleapis.com") return undefined;
    if (mode === "reject") return Response.json({ error: "invalid_grant" }, { status: 400 });
    throw new TypeError("network down");
  });
  try {
    const r = await sendFcm(sa, { target: "tok", kind: "token" }, CONTENT);
    assert(!r.ok && r.status === "OAUTH_FAILED" && !r.retryable && !r.dead);
    mode = "network";
    const r2 = await sendFcm(sa, { target: "tok", kind: "token" }, CONTENT);
    assert(!r2.ok && r2.retryable);
  } finally {
    net.restore();
  }
});
