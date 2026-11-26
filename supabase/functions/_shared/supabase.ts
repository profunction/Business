// Supabase 客户端：服务器身份（secret key，不受 RLS）和用户身份（publishable key + 用户 JWT，受 RLS）。
// fetch 每次都经过 globalThis.fetch（测试可以换成假的）。

import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { ConfigError, type SupabaseEnv, supabaseEnv } from "./env.ts";

const AUTH_OPTIONS = { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false };

const dynamicFetch: typeof fetch = (input, init) => globalThis.fetch(input, init);

export function adminClient(env: SupabaseEnv = supabaseEnv()): SupabaseClient {
  return createClient(env.url, env.secretKey, { auth: AUTH_OPTIONS, global: { fetch: dynamicFetch } });
}

/** 用户身份的客户端：读写都照这个用户的 RLS。 */
export function userClient(jwt: string, env: SupabaseEnv = supabaseEnv()): SupabaseClient {
  if (!env.publishableKey) throw new ConfigError("SUPABASE_PUBLISHABLE_KEY_MISSING");
  return createClient(env.url, env.publishableKey, {
    auth: AUTH_OPTIONS,
    global: { fetch: dynamicFetch, headers: { Authorization: `Bearer ${jwt}` } },
  });
}

/** 数据库函数（RPC）或 PostgREST 回传的错误。message 是数据库的英文代码（例如 IMPORT_NOT_FOUND）。 */
export class DbError extends Error {
  constructor(
    public readonly op: string,
    message: string,
    public readonly code: string,
    public readonly status: number,
  ) {
    super(message);
    this.name = "DbError";
  }

  /**
   * 重试可能会好的错误：网络断（status 0）、伺服器错误、钥匙 / 权限设定问题（42501、401、403）、
   * 函数还不存在（迁移没跑，404 / PGRST）。数据本身的错误（P0001 之类，HTTP 400）重试也一样。
   */
  get transient(): boolean {
    return this.status === 0 || this.status >= 500 || this.status === 401 || this.status === 403 ||
      this.status === 404 || this.code === "42501" || this.code.startsWith("PGRST");
  }
}

interface PgResult<T> {
  data: T | null;
  error: { message?: string; code?: string } | null;
  status: number;
}

export function unwrap<T>(op: string, res: PgResult<T>): T {
  if (res.error) {
    throw new DbError(op, res.error.message ?? "DB_ERROR", res.error.code ?? "", res.status ?? 0);
  }
  return res.data as T;
}

/** 调用数据库函数；参数名照 SQL 的（p_...）。出错丢 DbError。 */
export async function rpc<T>(client: SupabaseClient, fn: string, params: Record<string, unknown>): Promise<T> {
  let res: PgResult<T>;
  try {
    res = await client.rpc(fn, params) as unknown as PgResult<T>;
  } catch (e) {
    throw new DbError(fn, e instanceof Error ? e.message : String(e), "", 0);
  }
  return unwrap(fn, res);
}

/**
 * auth.getUser 的错误是不是 Auth 服务自己的问题（断线、逾时、5xx、429 太忙、回的不是 JSON）：
 * 这时候 JWT 可能是好的，不能回 401（App 会当成登录过期、把导入标 AUTH 失败）；回 503 QUOTA_UNAVAILABLE
 * （cause = "AUTH"）：App 已经认得这个代码是「没开始、什么都没改，等一下再传」，不用另外加新的代码。
 * auth-js 不会丢错，是回 {error}：断线 / 5xx 是 AuthRetryableFetchError（status 0 / 5xx），
 * 回的不是 JSON 是 AuthUnknownError；JWT 不对（401 / 403、session 不在了）才是真的 UNAUTHORIZED。
 */
export function authUnavailable(e: unknown): boolean {
  if (!e || typeof e !== "object") return false;
  const { name, status } = e as { name?: unknown; status?: unknown };
  if (name === "AuthRetryableFetchError" || name === "AuthUnknownError") return true;
  return typeof status === "number" && (status === 0 || status === 429 || status >= 500);
}
