// HTTP 小工具：JSON 回应、固定时间比较、背景工作、日志、限量并发。

const encoder = new TextEncoder();

export function json(body: unknown, status = 200, headers: HeadersInit = {}): Response {
  const h = new Headers(headers);
  h.set("Content-Type", "application/json; charset=utf-8");
  return new Response(JSON.stringify(body), { status, headers: h });
}

export function text(body: string, status = 200, headers: HeadersInit = {}): Response {
  const h = new Headers(headers);
  h.set("Content-Type", "text/plain; charset=utf-8");
  return new Response(body, { status, headers: h });
}

/** 固定时间比较（不会因为前面几个字对了就比较快回传）。长度不同直接 false，但照样跑完整个循环。 */
export function timingSafeEqual(a: string, b: string): boolean {
  const ea = encoder.encode(a);
  const eb = encoder.encode(b);
  const n = Math.max(ea.length, eb.length);
  let diff = ea.length ^ eb.length;
  for (let i = 0; i < n; i++) diff |= (ea[i] ?? 0) ^ (eb[i] ?? 0);
  return diff === 0;
}

/** 跟其中任何一个相等（每个都比，不提早结束）。 */
export function matchesAny(value: string | null, candidates: string[]): boolean {
  if (value == null || candidates.length === 0) return false;
  let ok = false;
  for (const c of candidates) ok = timingSafeEqual(value, c) || ok;
  return ok;
}

export function bearerToken(req: Request): string | null {
  const h = req.headers.get("authorization") ?? "";
  const m = /^Bearer\s+(.+)$/i.exec(h.trim());
  return m ? m[1].trim() : null;
}

export const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface EdgeRuntimeLike {
  waitUntil(promise: Promise<unknown>): void;
}

/**
 * 交给 Supabase 的 EdgeRuntime.waitUntil 在回应之后继续跑（受总时间限制：免费 150 秒、付费 400 秒）。
 * 没有 EdgeRuntime（deno test、一般 Deno）→ 回传 false，调用的地方自己 await。
 */
export function runInBackground(promise: Promise<unknown>): boolean {
  const rt = (globalThis as { EdgeRuntime?: EdgeRuntimeLike }).EdgeRuntime;
  if (rt && typeof rt.waitUntil === "function") {
    rt.waitUntil(promise);
    return true;
  }
  return false;
}

export type LogLevel = "info" | "warn" | "error";

/** 一行一个 JSON 的日志。不要放钥匙、电话号码、价目表内容。 */
export function log(level: LogLevel, event: string, fields: Record<string, unknown> = {}): void {
  const line = JSON.stringify({ level, event, ...fields });
  if (level === "error") console.error(line);
  else if (level === "warn") console.warn(line);
  else console.log(line);
}

export function errorMessage(e: unknown): string {
  if (e instanceof Error) return e.message;
  return typeof e === "string" ? e : JSON.stringify(e);
}

/** 最多同时跑 limit 个；结果顺序跟 items 一样。fn 不应该丢错（丢了会让整个 Promise 失败）。 */
export async function mapLimit<T, R>(
  items: T[],
  limit: number,
  fn: (item: T, index: number) => Promise<R>,
): Promise<R[]> {
  const out: R[] = new Array(items.length);
  let next = 0;
  const workers = Array.from({ length: Math.max(1, Math.min(limit, items.length)) }, async () => {
    while (next < items.length) {
      const i = next++;
      out[i] = await fn(items[i], i);
    }
  });
  await Promise.all(workers);
  return out;
}

/** 对外请求（Graph / FCM / Google）一个最多等多久 */
export const REQUEST_TIMEOUT_MS = 15_000;

/** 这个请求可以等多久：平常 15 秒；有期限的话不超过期限（最少 1 秒） */
export function requestTimeoutMs(deadline?: number | null): number {
  if (deadline == null) return REQUEST_TIMEOUT_MS;
  return Math.max(1_000, Math.min(REQUEST_TIMEOUT_MS, deadline - Date.now()));
}

export class BodyTooLargeError extends Error {
  constructor(public readonly limit: number) {
    super(`BODY_TOO_LARGE (> ${limit} bytes)`);
    this.name = "BodyTooLargeError";
  }
}

/**
 * 读整个 request body，但最多 max 个字：Content-Length 写超过 → 一个字都不读就丢 BodyTooLargeError；
 * 没写（chunked）或写少了 → 边读边数，超过就停（cancel）再丢。验身份之前用这个，不会被大 body 塞爆记忆体。
 */
export async function readBodyLimited(req: Request, max: number): Promise<Uint8Array> {
  const declared = req.headers.get("content-length");
  if (declared != null && /^\s*\d+\s*$/.test(declared) && Number(declared) > max) {
    await req.body?.cancel().catch(() => {});
    throw new BodyTooLargeError(max);
  }
  if (!req.body) return new Uint8Array(0);
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.length;
    if (total > max) {
      await reader.cancel().catch(() => {});
      throw new BodyTooLargeError(max);
    }
    chunks.push(value);
  }
  if (chunks.length === 1) return chunks[0];
  const out = new Uint8Array(total);
  let o = 0;
  for (const c of chunks) {
    out.set(c, o);
    o += c.length;
  }
  return out;
}

export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
