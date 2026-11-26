// 语音 / 文字 → 订单草稿（voice-order 和 whatsapp-webhook 共用）。
// 已经用 reserve_voice_order_run（或 reserve_whatsapp_order）占好位：
//   get_voice_order_context（这家店可以下单的商品）→ 语音的话先转文字（商品名当 keyterms）→ Claude → create_order_draft
// 出错：App 的（keepOnFailure = false）→ fail_voice_order_run 记原因；
//       WhatsApp 的（keepOnFailure = true）→ 照样建一张空的草稿（ai_meta.error_code），客服自己看 / 听。

import type { SupabaseClient } from "@supabase/supabase-js";
import { classifyClaudeError } from "./claude.ts";
import { errorMessage, log } from "./http.ts";
import { draftOrder, type OrderProduct } from "./order_ai.ts";
import { keyterms, type SttConfig, transcribe } from "./stt.ts";
import { rpc } from "./supabase.ts";

export interface DraftDeps {
  admin: SupabaseClient;
  stt: SttConfig | null;
  anthropicKey: string | null;
  /** 期限（epoch 毫秒） */
  deadline: number;
}

export type DraftInput =
  | { kind: "audio"; bytes: Uint8Array; mime: string; audioPath: string }
  | { kind: "text"; text: string };

export interface CreatedDraft {
  result: string;
  draft_id: string;
  shop_id: string;
  locale: string | null;
  item_count: number;
  unmatched_count: number;
}

export type DraftOutcome =
  | { ok: true; draft: CreatedDraft; errorCode: string | null; transcript: string | null }
  | { ok: false; code: string };

interface Context {
  products?: OrderProduct[];
}

export async function makeDraft(
  deps: DraftDeps,
  run: { runId: string; shopId: string },
  input: DraftInput,
  keepOnFailure: boolean,
): Promise<DraftOutcome> {
  let transcript: string | null = input.kind === "text" ? input.text.trim() : null;
  let language: string | null = null;
  const meta: Record<string, unknown> = {};
  let code: string | null = null;
  let lines: unknown[] = [];
  let unmatched: unknown[] = [];

  try {
    const ctx = await rpc<Context>(deps.admin, "get_voice_order_context", { p_shop_id: run.shopId });
    const products = Array.isArray(ctx?.products) ? ctx.products : [];

    if (input.kind === "audio") {
      const stt = await transcribe(deps.stt, input.bytes, input.mime, {
        terms: keyterms(products.map((p) => p.name)),
        deadline: deps.deadline,
      });
      if (!stt.ok) {
        code = stt.code;
        log("warn", "voice_stt_failed", { run_id: run.runId, code: stt.code, message: stt.message });
      } else {
        transcript = stt.transcript.text;
        language = stt.transcript.language;
        meta.stt = { model: deps.stt?.model, language, duration_sec: stt.transcript.durationSec };
        if (!transcript) code = "NO_SPEECH";
      }
    }

    if (!code && transcript) {
      if (!deps.anthropicKey) {
        code = "AI_NOT_CONFIGURED";
      } else if (products.length === 0) {
        code = "NO_ORDERABLE_PRODUCTS";
      } else {
        try {
          const out = await draftOrder(transcript, products, {
            apiKey: deps.anthropicKey,
            timeoutMs: Math.max(5_000, deps.deadline - Date.now() - 5_000),
          });
          meta.ai = out.meta;
          if (out.ok) {
            lines = out.data.lines;
            unmatched = out.data.unmatched;
            language = out.data.language ?? language;
          } else {
            code = out.reason === "refusal"
              ? "AI_REFUSED"
              : out.reason === "max_tokens"
              ? "AI_TRUNCATED"
              : "AI_INVALID_OUTPUT";
          }
        } catch (e) {
          code = classifyClaudeError(e) ?? "AI_FAILED";
          log("warn", "voice_ai_failed", { run_id: run.runId, code, error: errorMessage(e) });
        }
      }
    }
  } catch (e) {
    code = "INTERNAL_ERROR";
    log("error", "voice_draft_error", { run_id: run.runId, error: errorMessage(e) });
  }

  if (code && !keepOnFailure) {
    await rpc(deps.admin, "fail_voice_order_run", { p_run_id: run.runId, p_error_code: code }).catch((e) =>
      log("error", "voice_fail_record_failed", { run_id: run.runId, error: errorMessage(e) })
    );
    return { ok: false, code };
  }

  try {
    const draft = await rpc<CreatedDraft>(deps.admin, "create_order_draft", {
      p_run_id: run.runId,
      p_transcript: transcript,
      p_language: language,
      p_lines: lines,
      p_unmatched: unmatched,
      p_ai_meta: { ...meta, ...(code ? { error_code: code } : {}) },
      p_audio_path: input.kind === "audio" ? input.audioPath : null,
    });
    return { ok: true, draft, errorCode: code, transcript };
  } catch (e) {
    log("error", "voice_create_draft_failed", { run_id: run.runId, error: errorMessage(e) });
    await rpc(deps.admin, "fail_voice_order_run", { p_run_id: run.runId, p_error_code: "DB_ERROR" }).catch(() => {});
    return { ok: false, code: "DB_ERROR" };
  }
}
