// Firebase Cloud Messaging HTTP v1：服务账号 JWT（WebCrypto RS256）→ OAuth access token（缓存）→ 一个一个发。
// 失效判断照 docs/research/step4/verifications.json 的更正：
//   * details[].errorCode = UNREGISTERED → 失效，删掉
//   * 400 只有 details 里有 FcmError、而且没有 google.rpc.BadRequest（payload 错）时才当成 token 错 → 删掉
//   * 401 UNAUTHENTICATED（没有 FcmError）= 我们的 OAuth token 过期 → 清缓存、重拿一次再发
//   * THIRD_PARTY_AUTH_ERROR = APNs 设定问题，不删
//   * SENDER_ID_MISMATCH 不删（设定错了 Firebase 项目时会让所有 token 都这样，删了就全没了）
//   * 429 / 500 / 503 → 重试

import type { FcmServiceAccount } from "./env.ts";
import type { PushContent, PushTarget } from "./messages.ts";

const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

function b64url(bytes: Uint8Array): string {
  let bin = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function b64urlJson(o: unknown): string {
  return b64url(new TextEncoder().encode(JSON.stringify(o)));
}

export async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem.replace(/\\n/g, "\n") // 环境变量里的 \n 可能是字面的两个字
    .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
}

/** 签一个给 Google token 端点的 JWT（RS256，最多 1 小时） */
export async function signServiceAccountJwt(sa: FcmServiceAccount, nowSec: number): Promise<string> {
  const input = `${b64urlJson({ alg: "RS256", typ: "JWT" })}.${
    b64urlJson({ iss: sa.client_email, scope: SCOPE, aud: sa.token_uri, iat: nowSec, exp: nowSec + 3600 })
  }`;
  const key = await importPrivateKey(sa.private_key);
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(input));
  return `${input}.${b64url(new Uint8Array(sig))}`;
}

export class FcmAuthError extends Error {
  constructor(message: string, public readonly retryable: boolean) {
    super(message);
    this.name = "FcmAuthError";
  }
}

// 模块层缓存：同一个 isolate 下一次调用还能用（离到期 5 分钟内就重拿）
const tokenCache = new Map<string, { token: string; exp: number }>();
// 同时有很多条要发时，只拿一次 token（不要每条讯息都拿一个）
const inflight = new Map<string, Promise<string>>();

export function clearFcmTokenCache(): void {
  tokenCache.clear();
  inflight.clear();
}

/**
 * 拿 OAuth access token（缓存到离到期 5 分钟）。force = 不管缓存重拿；
 * staleToken = 这个 token 被 FCM 拒绝了（401）：缓存的还是它才重拿，别人已经换新的就直接用新的。
 */
export function getAccessToken(sa: FcmServiceAccount, force = false, staleToken?: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const cached = tokenCache.get(sa.client_email);
  const usable = cached && cached.exp - 300 > now &&
    (!force || (staleToken !== undefined && cached.token !== staleToken));
  if (usable) return Promise.resolve(cached.token);
  const pending = inflight.get(sa.client_email);
  if (pending) return pending;
  const p = fetchAccessToken(sa, now).finally(() => inflight.delete(sa.client_email));
  inflight.set(sa.client_email, p);
  return p;
}

async function fetchAccessToken(sa: FcmServiceAccount, now: number): Promise<string> {
  const assertion = await signServiceAccountJwt(sa, now);
  let res: Response;
  try {
    res = await fetch(sa.token_uri, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
      signal: AbortSignal.timeout(15_000),
    });
  } catch (e) {
    throw new FcmAuthError(`GOOGLE_TOKEN_NETWORK: ${e instanceof Error ? e.message : e}`, true);
  }
  const data = await res.json().catch(() => null) as
    | { access_token?: string; expires_in?: number; error?: string }
    | null;
  if (!res.ok || !data?.access_token) {
    // 400 invalid_grant = 钥匙 / 时间不对（设定问题）；5xx = Google 暂时有问题
    throw new FcmAuthError(
      `GOOGLE_TOKEN_${res.status}${data?.error ? `_${data.error}` : ""}`,
      res.status >= 500 || res.status === 429,
    );
  }
  tokenCache.set(sa.client_email, { token: data.access_token, exp: now + (Number(data.expires_in) || 3600) });
  return data.access_token;
}

export type FcmSendResult =
  | { ok: true; name: string }
  | {
    ok: false;
    httpStatus: number;
    /** error.status，例如 NOT_FOUND / INVALID_ARGUMENT / UNAUTHENTICATED */
    status: string;
    /** details[] 里 FcmError 的 errorCode，例如 UNREGISTERED */
    errorCode: string | null;
    /** token / FID 已经失效，要删掉 */
    dead: boolean;
    retryable: boolean;
    message: string;
  };

interface GoogleErrorBody {
  error?: {
    code?: number;
    message?: string;
    status?: string;
    details?: { "@type"?: string; errorCode?: string }[];
  };
}

/** 照 HTTP 状态和回传内容决定：失效（删）/ 可以重试 / 都不是 */
export function classifyFcmError(httpStatus: number, body: unknown): Omit<Extract<FcmSendResult, { ok: false }>, "ok"> {
  const err = (body as GoogleErrorBody | null)?.error ?? {};
  const details = Array.isArray(err.details) ? err.details : [];
  const fcmError = details.find((d) =>
    typeof d?.["@type"] === "string" && d["@type"].endsWith("google.firebase.fcm.v1.FcmError")
  );
  const badRequest = details.some((d) =>
    typeof d?.["@type"] === "string" && d["@type"].endsWith("google.rpc.BadRequest")
  );
  const errorCode = typeof fcmError?.errorCode === "string" ? fcmError.errorCode : null;
  const status = typeof err.status === "string" ? err.status : `HTTP_${httpStatus}`;
  const message = (typeof err.message === "string" ? err.message : status).slice(0, 300);

  let dead = false;
  let retryable = false;
  if (errorCode === "UNREGISTERED") {
    dead = true;
  } else if (httpStatus === 400 && errorCode === "INVALID_ARGUMENT" && !badRequest) {
    dead = true; // 整个 payload 没问题，是 token / FID 本身不对
  } else if (errorCode === "THIRD_PARTY_AUTH_ERROR" || errorCode === "SENDER_ID_MISMATCH") {
    retryable = false; // 设定问题，不删 token
  } else if (httpStatus === 429 || httpStatus >= 500 || httpStatus === 0) {
    retryable = true;
  } else if (httpStatus === 401 || httpStatus === 403) {
    retryable = true; // 我们的服务账号 / 权限问题：修好后可以补发
  }
  return { httpStatus, status, errorCode, dead, retryable, message };
}

export function buildFcmMessage(target: PushTarget, p: PushContent, nowSec = Math.floor(Date.now() / 1000)) {
  const androidNotification: Record<string, string> = { channel_id: "orders", sound: "default" };
  if (p.tag) androidNotification.tag = p.tag;
  return {
    message: {
      ...(target.kind === "fid" ? { fid: target.target } : { token: target.target }),
      notification: { title: p.title, body: p.body },
      data: p.data, // 值全部是字串
      android: { priority: "high", ttl: `${p.ttlSeconds}s`, notification: androidNotification },
      apns: {
        headers: {
          "apns-priority": "10",
          "apns-expiration": String(nowSec + p.ttlSeconds),
          ...(p.tag ? { "apns-collapse-id": p.tag.slice(0, 64) } : {}),
        },
        // 有 apns.payload 时 iOS 可能不用 notification 的字，所以 alert 也明写
        payload: { aps: { alert: { title: p.title, body: p.body }, sound: "default" } },
      },
    },
  };
}

/** 发给一个 token / FID。401 UNAUTHENTICATED 会换新的 OAuth token 再试一次。 */
export async function sendFcm(sa: FcmServiceAccount, target: PushTarget, p: PushContent): Promise<FcmSendResult> {
  const url = `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(sa.project_id)}/messages:send`;
  const body = JSON.stringify(buildFcmMessage(target, p));
  let rejected: string | undefined;
  for (let attempt = 0; attempt < 2; attempt++) {
    let accessToken: string;
    try {
      accessToken = await getAccessToken(sa, attempt > 0, rejected);
    } catch (e) {
      const retryable = e instanceof FcmAuthError ? e.retryable : true;
      return {
        ok: false,
        httpStatus: 0,
        status: "OAUTH_FAILED",
        errorCode: null,
        dead: false,
        retryable,
        message: String(e instanceof Error ? e.message : e),
      };
    }
    let res: Response;
    try {
      res = await fetch(url, {
        method: "POST",
        headers: { "Authorization": `Bearer ${accessToken}`, "Content-Type": "application/json" },
        body,
        signal: AbortSignal.timeout(15_000),
      });
    } catch (e) {
      return {
        ok: false,
        httpStatus: 0,
        status: "NETWORK",
        errorCode: null,
        dead: false,
        retryable: true,
        message: String(e instanceof Error ? e.message : e),
      };
    }
    const data = await res.json().catch(() => null) as Record<string, unknown> | null;
    if (res.ok) return { ok: true, name: typeof data?.name === "string" ? data.name : "" };
    const c = classifyFcmError(res.status, data);
    if (attempt === 0 && res.status === 401 && c.status === "UNAUTHENTICATED" && c.errorCode === null) {
      rejected = accessToken; // OAuth token 过期 / 被撤销：重拿一次再发
      continue;
    }
    return { ok: false, ...c };
  }
  return {
    ok: false,
    httpStatus: 401,
    status: "UNAUTHENTICATED",
    errorCode: null,
    dead: false,
    retryable: true,
    message: "UNAUTHENTICATED",
  };
}
