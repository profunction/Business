// 语音转文字（第六步）：ElevenLabs Scribe（选择的理由和备选见 docs/06-voice-whatsapp.md）。
//   POST https://api.elevenlabs.io/v1/speech-to-text（multipart），头 xi-api-key
//   model_id（STT_MODEL，默认 scribe_v2）、file、language_code 不给（自动判断，华语 / 广东话 / 马来文 / 英文混着讲）、
//   keyterms（这家店的商品名，让「十六安士」「kotak」这类词认得准；每个最多 50 字、5 个词，最多 100 个）、
//   scribe_v3 才送 secondary_language_codes（zh、yue、ms、en）。
//   回应 {language_code, language_probability, text, words, audio_duration_secs}
// 没设 ELEVENLABS_API_KEY → STT_NOT_CONFIGURED（调用的地方显示原因，不会假装成功）。

import { requestTimeoutMs } from "./http.ts";

export const STT_URL = "https://api.elevenlabs.io/v1/speech-to-text";
export const DEFAULT_STT_MODEL = "scribe_v2";
/** 录音最长几秒（App 也是 60 秒自动停；这里多留一点） */
export const MAX_AUDIO_SECONDS = 75;
export const MAX_KEYTERMS = 100;

export interface SttConfig {
  apiKey: string;
  model: string;
}

export interface Transcript {
  text: string;
  language: string | null;
  durationSec: number | null;
}

export type SttResult =
  | { ok: true; transcript: Transcript }
  | {
    ok: false;
    code: "STT_NOT_CONFIGURED" | "STT_FAILED" | "STT_BUSY" | "STT_AUTH_FAILED" | "AUDIO_TOO_LONG";
    message: string;
  };

/** 商品名 → keyterms：去掉不收的字（<>{}[]\），每个最多 50 字 / 5 个词，不重复 */
export function keyterms(names: string[], max = MAX_KEYTERMS): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  for (const raw of names) {
    const t = raw.replace(/[<>{}[\]\\]/g, " ").replace(/\s+/g, " ").trim();
    if (!t || t.length > 50 || t.split(" ").length > 5) continue;
    const k = t.toLowerCase();
    if (seen.has(k)) continue;
    seen.add(k);
    out.push(t);
    if (out.length >= max) break;
  }
  return out;
}

export async function transcribe(
  cfg: SttConfig | null,
  audio: Uint8Array,
  mime: string,
  opts: { terms?: string[]; deadline?: number | null } = {},
): Promise<SttResult> {
  if (!cfg) return { ok: false, code: "STT_NOT_CONFIGURED", message: "ELEVENLABS_API_KEY missing" };
  const form = new FormData();
  form.append("model_id", cfg.model);
  form.append("file", new Blob([audio as BlobPart], { type: mime }), `audio.${mime.split("/")[1] ?? "bin"}`);
  form.append("tag_audio_events", "false");
  if (cfg.model.startsWith("scribe_v3")) {
    for (const c of ["zh", "yue", "ms", "en"]) form.append("secondary_language_codes", c);
  }
  for (const t of opts.terms ?? []) form.append("keyterms", t);

  let res: Response;
  try {
    res = await fetch(STT_URL, {
      method: "POST",
      headers: { "xi-api-key": cfg.apiKey },
      body: form,
      signal: AbortSignal.timeout(Math.max(requestTimeoutMs(opts.deadline), 30_000)),
    });
  } catch (e) {
    return { ok: false, code: "STT_FAILED", message: `NETWORK: ${e instanceof Error ? e.message : e}` };
  }
  const data = await res.json().catch(() => null) as Record<string, unknown> | null;
  if (!res.ok) {
    const message = JSON.stringify(data?.detail ?? data ?? `HTTP ${res.status}`).slice(0, 300);
    if (res.status === 401 || res.status === 403) return { ok: false, code: "STT_AUTH_FAILED", message };
    if (res.status === 429) return { ok: false, code: "STT_BUSY", message };
    return { ok: false, code: "STT_FAILED", message };
  }
  const duration = typeof data?.audio_duration_secs === "number" ? data.audio_duration_secs : null;
  if (duration != null && duration > MAX_AUDIO_SECONDS) {
    return { ok: false, code: "AUDIO_TOO_LONG", message: `${duration}s` };
  }
  return {
    ok: true,
    transcript: {
      text: typeof data?.text === "string" ? data.text.replace(/\s+/g, " ").trim() : "",
      language: typeof data?.language_code === "string" ? data.language_code : null,
      durationSec: duration,
    },
  };
}
