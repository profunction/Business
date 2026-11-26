// voice-order：App 的语音下单。老板按住麦克风录好音、上传到 Storage voice-orders/<店 id>/<uuid>.wav 之后叫这里：
//   supabase.functions.invoke('voice-order', body: {shop_id, audio_path})（自动带用户 JWT）
// config.toml 里 verify_jwt = false；这里自己验 auth.getUser(jwt)。
//   1. reserve_voice_order_run（服务器身份）：是不是这家店的人、路径在不在这家店的文件夹、用量（每家店 10 分钟 6 次……）
//   2. 下载录音（最多 3 MB），看魔术字节是不是录音
//   3. 语音转文字 → Claude 对到这家店可以下单的商品 → create_order_draft（草稿，老板确认后才下单）
//   4. 用老板的身份读 get_order_draft 回传（RLS / 权限照老板的）
// 回应：200 {draft}；400 INVALID_REQUEST / INVALID_FILE_PATH；401 UNAUTHORIZED；403 NOT_ALLOWED；
//       404 AUDIO_NOT_FOUND；413 AUDIO_TOO_LARGE；415 UNSUPPORTED_AUDIO；
//       422 NO_SPEECH / AUDIO_TOO_LONG / NO_ORDERABLE_PRODUCTS / AI_REFUSED / AI_INVALID_OUTPUT……（处理过了，看不懂）；
//       429 TOO_MANY_VOICE_ORDERS（retry_after 秒）；
//       503 STT_NOT_CONFIGURED / AI_NOT_CONFIGURED / STT_BUSY / AI_BUSY / AI_UNAVAILABLE / QUOTA_UNAVAILABLE（等一下再试）；
//       500 CONFIG_MISSING / DB_ERROR / INTERNAL_ERROR

import type { SupabaseClient } from "@supabase/supabase-js";
import { anthropicApiKey, sttConfig, type SupabaseEnv, supabaseEnv } from "../_shared/env.ts";
import { bearerToken, CORS_HEADERS, errorMessage, json, log, UUID_RE } from "../_shared/http.ts";
import { sniffAudio } from "../_shared/filetype.ts";
import { adminClient, authUnavailable, rpc, userClient } from "../_shared/supabase.ts";
import { makeDraft } from "../_shared/voice_order.ts";

export const BUCKET = "voice-orders";
export const MAX_AUDIO_BYTES = 3 * 1024 * 1024;
/** 整个请求最多跑多久（平台免费方案 150 秒） */
export const TIME_BUDGET_MS = 120_000;

const RETRY_LATER = new Set([
  "STT_NOT_CONFIGURED",
  "AI_NOT_CONFIGURED",
  "STT_BUSY",
  "STT_AUTH_FAILED",
  "STT_FAILED",
  "AI_BUSY",
  "AI_UNAVAILABLE",
  "AI_AUTH_FAILED",
  "AI_TIMEOUT",
  "AI_FAILED",
  "DB_ERROR",
]);

const withCors = (res: Response): Response => {
  for (const [k, v] of Object.entries(CORS_HEADERS)) res.headers.set(k, v);
  return res;
};

/** 录音路径：<店 id>/<uuid>.<副档名>（跟数据库的 _voice_path_ok 一样） */
export function audioPathOk(shopId: string, path: string): boolean {
  return new RegExp(
    `^${shopId.toLowerCase()}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\.(wav|m4a|aac|mp4|ogg|opus|webm|mp3)$`,
  ).test(path);
}

async function download(admin: SupabaseClient, path: string): Promise<Uint8Array | { code: string; status: number }> {
  const { data, error } = await admin.storage.from(BUCKET).download(path);
  if (error || !data) return { code: "AUDIO_NOT_FOUND", status: 404 };
  if (data.size > MAX_AUDIO_BYTES) return { code: "AUDIO_TOO_LARGE", status: 413 };
  const bytes = new Uint8Array(await data.arrayBuffer());
  if (bytes.length > MAX_AUDIO_BYTES) return { code: "AUDIO_TOO_LARGE", status: 413 };
  return bytes;
}

export async function handler(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return withCors(new Response(null, { status: 204 }));
  if (req.method !== "POST") return withCors(json({ error: "METHOD_NOT_ALLOWED" }, 405));
  const jwt = bearerToken(req);
  if (!jwt) return withCors(json({ error: "UNAUTHORIZED" }, 401));

  let env: SupabaseEnv;
  let uc: SupabaseClient;
  let admin: SupabaseClient;
  try {
    env = supabaseEnv();
    uc = userClient(jwt, env);
    admin = adminClient(env);
  } catch (e) {
    log("error", "voice_order_not_configured", { error: errorMessage(e) });
    return withCors(json({ error: "CONFIG_MISSING" }, 500));
  }
  const deadline = Date.now() + TIME_BUDGET_MS;

  try {
    const { data: auth, error: authError } = await uc.auth.getUser(jwt);
    if (authError && authUnavailable(authError)) {
      return withCors(json({ error: "QUOTA_UNAVAILABLE", cause: "AUTH" }, 503));
    }
    if (authError || !auth?.user) return withCors(json({ error: "UNAUTHORIZED" }, 401));

    const body = await req.json().catch(() => null) as { shop_id?: unknown; audio_path?: unknown } | null;
    const shopId = typeof body?.shop_id === "string" ? body.shop_id.trim().toLowerCase() : "";
    const path = typeof body?.audio_path === "string" ? body.audio_path.trim().replace(/^voice-orders\//, "") : "";
    if (!UUID_RE.test(shopId) || !path) return withCors(json({ error: "INVALID_REQUEST" }, 400));
    if (!audioPathOk(shopId, path)) return withCors(json({ error: "INVALID_FILE_PATH" }, 400));

    const runId = crypto.randomUUID();
    let r: Record<string, unknown>;
    try {
      r = await rpc<Record<string, unknown>>(admin, "reserve_voice_order_run", {
        p_shop_id: shopId,
        p_user_id: auth.user.id,
        p_run_id: runId,
        p_source: "app_voice",
        p_audio_path: path,
      }) ?? {};
    } catch (e) {
      log("error", "voice_reserve_failed", { error: errorMessage(e) });
      return withCors(json({ error: "QUOTA_UNAVAILABLE" }, 503));
    }
    switch (r.result) {
      case "ok":
        break;
      case "not_found":
      case "not_member":
        return withCors(json({ error: "NOT_ALLOWED" }, 403));
      case "invalid_path":
        return withCors(json({ error: "INVALID_FILE_PATH" }, 400));
      case "quota": {
        const n = Number(r.retry_after_sec);
        const sec = Number.isFinite(n) && n >= 1 ? Math.ceil(n) : 60;
        return withCors(
          json({ error: "TOO_MANY_VOICE_ORDERS", retry_after: sec }, 429, { "Retry-After": String(sec) }),
        );
      }
      default:
        return withCors(json({ error: "QUOTA_UNAVAILABLE" }, 503));
    }

    const fail = async (code: string, status: number) => {
      await rpc(admin, "fail_voice_order_run", { p_run_id: runId, p_error_code: code }).catch(() => {});
      return withCors(json({ error: code }, status));
    };
    const got = await download(admin, path);
    if (!(got instanceof Uint8Array)) return fail(got.code, got.status);
    const audio = sniffAudio(got);
    if (!audio) return fail("UNSUPPORTED_AUDIO", 415);

    const out = await makeDraft(
      { admin, stt: sttConfig(), anthropicKey: anthropicApiKey(), deadline },
      { runId, shopId },
      { kind: "audio", bytes: got, mime: audio.mime, audioPath: path },
      false,
    );
    if (!out.ok) {
      log("info", "voice_order_failed", { shop_id: shopId, code: out.code });
      return withCors(json({ error: out.code }, RETRY_LATER.has(out.code) ? 503 : 422));
    }
    const draft = await rpc<unknown>(uc, "get_order_draft", { p_draft_id: out.draft.draft_id });
    log("info", "voice_order_done", {
      shop_id: shopId,
      draft_id: out.draft.draft_id,
      items: out.draft.item_count,
      unmatched: out.draft.unmatched_count,
    });
    return withCors(json({ draft }, 200));
  } catch (e) {
    log("error", "voice_order_error", { error: errorMessage(e) });
    return withCors(json({ error: "INTERNAL_ERROR" }, 500));
  }
}

export default { fetch: handler };
