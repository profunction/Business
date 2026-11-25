// 测试用的 Firebase 服务账号（自己产生的 RSA 钥匙）和假的 Google OAuth token 端点。
import { encodeBase64 } from "@std/encoding/base64";
import type { FcmServiceAccount } from "../_shared/env.ts";
import type { Call } from "./_helpers.ts";

/** 测试用的服务账号（自己产生的 RSA 钥匙）和假的 Google token 端点（会验 JWT 签名） */
export async function testServiceAccount(): Promise<{ sa: FcmServiceAccount; publicKey: CryptoKey; json: string }> {
  const kp = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  );
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", kp.privateKey));
  const b64 = encodeBase64(der).replace(/(.{64})/g, "$1\n");
  const pem = `-----BEGIN PRIVATE KEY-----\n${b64}\n-----END PRIVATE KEY-----\n`;
  const sa = {
    client_email: `fcm-${crypto.randomUUID()}@test-project.iam.gserviceaccount.com`,
    private_key: pem,
    project_id: "test-project",
    token_uri: "https://oauth2.googleapis.com/token",
  };
  return { sa, publicKey: kp.publicKey, json: JSON.stringify({ type: "service_account", ...sa }) };
}

function b64urlDecode(s: string): Uint8Array {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(s.length / 4) * 4, "=");
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

/** Google OAuth：验 JWT（RS256、iss、scope、aud、exp ≤ 1 小时）再发 access token */
export async function googleTokenEndpoint(c: Call, publicKey: CryptoKey, token: string): Promise<Response> {
  const form = new URLSearchParams(c.text);
  if (form.get("grant_type") !== "urn:ietf:params:oauth:grant-type:jwt-bearer") {
    return Response.json({ error: "unsupported_grant_type" }, { status: 400 });
  }
  const [h, p, s] = (form.get("assertion") ?? "").split(".");
  const ok = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    publicKey,
    b64urlDecode(s) as Uint8Array<ArrayBuffer>,
    new TextEncoder().encode(`${h}.${p}`),
  );
  const header = JSON.parse(new TextDecoder().decode(b64urlDecode(h)));
  const claims = JSON.parse(new TextDecoder().decode(b64urlDecode(p)));
  if (
    !ok || header.alg !== "RS256" || claims.scope !== "https://www.googleapis.com/auth/firebase.messaging" ||
    claims.aud !== "https://oauth2.googleapis.com/token" || claims.exp - claims.iat > 3600
  ) {
    return Response.json({ error: "invalid_grant" }, { status: 400 });
  }
  return Response.json({ access_token: token, expires_in: 3599, token_type: "Bearer" });
}
