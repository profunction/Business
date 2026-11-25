import { assert, assertEquals, assertFalse, assertThrows } from "@std/assert";
import { bearerToken, json, mapLimit, matchesAny, timingSafeEqual } from "../_shared/http.ts";
import {
  ConfigError,
  DEFAULT_GRAPH_VERSION,
  fcmServiceAccount,
  intEnv,
  readKeyMap,
  serviceKeys,
  supabaseEnv,
  whatsappConfig,
} from "../_shared/env.ts";
import { setEnv } from "./_helpers.ts";

Deno.test("timingSafeEqual: 一样 / 不一样 / 长度不同 / 中文", () => {
  assert(timingSafeEqual("sb_secret_abc", "sb_secret_abc"));
  assertFalse(timingSafeEqual("sb_secret_abc", "sb_secret_abd"));
  assertFalse(timingSafeEqual("sb_secret_abc", "sb_secret_ab"));
  assertFalse(timingSafeEqual("", "x"));
  assert(timingSafeEqual("", ""));
  assert(timingSafeEqual("确认", "确认"));
  assertFalse(timingSafeEqual("确认", "缺货"));
});

Deno.test("matchesAny / bearerToken", () => {
  assert(matchesAny("b", ["a", "b"]));
  assertFalse(matchesAny("c", ["a", "b"]));
  assertFalse(matchesAny(null, ["a"]));
  assertFalse(matchesAny("a", []));
  assertEquals(bearerToken(new Request("http://x", { headers: { Authorization: "Bearer abc.def" } })), "abc.def");
  assertEquals(bearerToken(new Request("http://x", { headers: { Authorization: "bearer  xyz " } })), "xyz");
  assertEquals(bearerToken(new Request("http://x", { headers: { Authorization: "Basic xyz" } })), null);
  assertEquals(bearerToken(new Request("http://x")), null);
});

Deno.test("json 回应", async () => {
  const res = json({ a: 1 }, 202, { "X-Test": "1" });
  assertEquals(res.status, 202);
  assertEquals(res.headers.get("content-type"), "application/json; charset=utf-8");
  assertEquals(res.headers.get("x-test"), "1");
  assertEquals(await res.json(), { a: 1 });
});

Deno.test("mapLimit：顺序不变、同时最多 limit 个", async () => {
  let running = 0;
  let peak = 0;
  const out = await mapLimit([1, 2, 3, 4, 5, 6, 7], 3, async (n) => {
    running++;
    peak = Math.max(peak, running);
    await new Promise((r) => setTimeout(r, 1));
    running--;
    return n * 10;
  });
  assertEquals(out, [10, 20, 30, 40, 50, 60, 70]);
  assertEquals(peak, 3);
  assertEquals(await mapLimit([], 3, (n: number) => Promise.resolve(n)), []);
});

Deno.test("SUPABASE_SECRET_KEYS 是 JSON（取 default），退回旧的 SERVICE_ROLE_KEY", () => {
  const restore = setEnv({
    SUPABASE_URL: "http://sb.test/",
    SUPABASE_SECRET_KEYS: JSON.stringify({ default: "sb_secret_new", other: "sb_secret_other" }),
    SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({ default: "sb_publishable_new" }),
    SUPABASE_SERVICE_ROLE_KEY: "legacy.jwt.key",
    SUPABASE_ANON_KEY: undefined,
  });
  try {
    const env = supabaseEnv();
    assertEquals(env, { url: "http://sb.test", secretKey: "sb_secret_new", publishableKey: "sb_publishable_new" });
    assertEquals(serviceKeys(), ["sb_secret_new", "legacy.jwt.key"]);

    Deno.env.set("SUPABASE_SECRET_KEYS", "{not json");
    assertEquals(readKeyMap("SUPABASE_SECRET_KEYS"), null);
    assertEquals(supabaseEnv().secretKey, "legacy.jwt.key");

    Deno.env.set("SUPABASE_SECRET_KEYS", "sb_secret_plain");
    assertEquals(readKeyMap("SUPABASE_SECRET_KEYS"), "sb_secret_plain");

    Deno.env.set("SUPABASE_SECRET_KEYS", JSON.stringify({ other: "x" }));
    Deno.env.delete("SUPABASE_SERVICE_ROLE_KEY");
    assertThrows(() => supabaseEnv(), ConfigError, "SUPABASE_ENV_MISSING");
    assertEquals(serviceKeys(), []);
  } finally {
    restore();
  }
});

Deno.test("FCM 服务账号：完整才用；token_uri 只接受 https", () => {
  const restore = setEnv({ FCM_SERVICE_ACCOUNT_JSON: undefined });
  try {
    assertEquals(fcmServiceAccount(), null);
    Deno.env.set("FCM_SERVICE_ACCOUNT_JSON", "nope");
    assertEquals(fcmServiceAccount(), null);
    Deno.env.set("FCM_SERVICE_ACCOUNT_JSON", JSON.stringify({ client_email: "a@b", project_id: "p" }));
    assertEquals(fcmServiceAccount(), null);
    Deno.env.set(
      "FCM_SERVICE_ACCOUNT_JSON",
      JSON.stringify({ client_email: "a@b", private_key: "k", project_id: "p", token_uri: "http://evil" }),
    );
    assertEquals(fcmServiceAccount()?.token_uri, "https://oauth2.googleapis.com/token");
  } finally {
    restore();
  }
});

Deno.test("WhatsApp 设定：版本默认 v27.0，格式不对也用默认", () => {
  const restore = setEnv({
    WHATSAPP_TOKEN: "tok",
    WHATSAPP_PHONE_NUMBER_ID: "123",
    WHATSAPP_GRAPH_VERSION: undefined,
  });
  try {
    assertEquals(whatsappConfig(), { token: "tok", phoneNumberId: "123", graphVersion: DEFAULT_GRAPH_VERSION });
    assertEquals(DEFAULT_GRAPH_VERSION, "v27.0");
    Deno.env.set("WHATSAPP_GRAPH_VERSION", "v25.0");
    assertEquals(whatsappConfig()?.graphVersion, "v25.0");
    Deno.env.set("WHATSAPP_GRAPH_VERSION", "../../x");
    assertEquals(whatsappConfig()?.graphVersion, "v27.0");
    Deno.env.delete("WHATSAPP_TOKEN");
    assertEquals(whatsappConfig(), null);
  } finally {
    restore();
  }
});

Deno.test("intEnv：范围外用默认值", () => {
  const restore = setEnv({ TEST_INT_ENV: "5000" });
  try {
    assertEquals(intEnv("TEST_INT_ENV", 100, 1, 10_000), 5000);
    assertEquals(intEnv("TEST_INT_ENV", 100, 1, 1000), 100);
    Deno.env.set("TEST_INT_ENV", "abc");
    assertEquals(intEnv("TEST_INT_ENV", 100, 1, 1000), 100);
  } finally {
    restore();
  }
});
