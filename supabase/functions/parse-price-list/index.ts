// parse-price-list：把上传的价目表（照片 / PDF / Excel / CSV）交给 Claude，写成待确认的行。
// App：supabase.functions.invoke('parse-price-list', body: {import_id})（自动带用户 JWT）。
// config.toml 里 verify_jwt = false；这里自己验：auth.getUser(jwt)，再用用户身份读 import（RLS 保证是自己的）。
//
//   回应：202 {import_id, status}（之后 App 每 3 秒查 price_list_imports.status）
//         401 UNAUTHORIZED、400 INVALID_IMPORT_ID、404 IMPORT_NOT_FOUND、
//         409 IMPORT_NOT_PROCESSING（status 不是 processing）/ IMPORT_ALREADY_RUNNING（已经在跑）
//   背景（EdgeRuntime.waitUntil；Opus 读一份价目表可能超过 150 秒）：
//     下载（服务器身份，最多 10 MB）→ 魔术字节判断格式 → 图片 / PDF 直接给 Claude；
//     Excel / CSV → 带行号文字 → 分段给 Claude → 写 price_list_import_rows（row_no 从 1）→
//     suggest_import_matches → status = review。任何错误 → status = failed + error_message（英文代码）。
//
// error_message 代码（App 按这个显示三语原因）：
//   档案问题：UNSUPPORTED_FILE、FILE_TOO_LARGE、EMPTY_FILE、FILE_NOT_FOUND、INVALID_FILE_PATH、
//             SPREADSHEET_UNREADABLE、EMPTY_SPREADSHEET、TOO_MANY_ROWS
//   AI 读不到：AI_REFUSED、AI_TRUNCATED、AI_INVALID_OUTPUT、NO_PRODUCTS_FOUND
//   网络 / 服务：AI_TIMEOUT、AI_BUSY、AI_UNAVAILABLE、AI_FAILED、AI_AUTH_FAILED、AI_REQUEST_REJECTED、
//             AI_NOT_CONFIGURED、DOWNLOAD_FAILED、DB_ERROR、INTERNAL_ERROR

import { encodeBase64 } from "@std/encoding/base64";
import type { SupabaseClient } from "@supabase/supabase-js";
import { anthropicApiKey, ConfigError, intEnv, type SupabaseEnv, supabaseEnv } from "../_shared/env.ts";
import {
  bearerToken,
  CORS_HEADERS,
  errorMessage,
  json,
  log,
  mapLimit,
  runInBackground,
  UUID_RE,
} from "../_shared/http.ts";
import { adminClient, DbError, rpc, unwrap, userClient } from "../_shared/supabase.ts";
import { type FileKind, IMAGE_MEDIA_TYPES, isImage, isSpreadsheet, sniffFileType } from "../_shared/filetype.ts";
import {
  type Chunk,
  chunkLines,
  readWorkbook,
  renderChunk,
  type SheetLine,
  splitChunk,
  SpreadsheetError,
  workbookLines,
} from "../_shared/spreadsheet.ts";
import {
  type CallMeta,
  classifyClaudeError,
  type ExtractedRow,
  type ExtractInput,
  type Extraction,
  type ExtractOutcome,
  extractPriceList,
  PRICE_LIST_MODEL,
  type UnreadableRow,
} from "../_shared/claude.ts";

export const BUCKET = "price-lists";
export const MAX_FILE_BYTES = 10 * 1024 * 1024;
/** Claude：一张图 base64 之后最多 10 MB（原始大约 7.5 MB） */
const MAX_IMAGE_BYTES = 7_000_000;
const CHUNK_CONCURRENCY = 3;
/** 「在跑」超过 10 分钟当成已经死掉（付费方案总时间 400 秒），可以重新跑 */
const STALE_CLAIM_MS = 10 * 60_000;
/** 留给最后写数据库的时间 */
const RESERVE_MS = 15_000;
/** 剩下不到这么多时间就不再叫 Claude */
const MIN_CALL_MS = 20_000;
const INSERT_BATCH = 500;

export class JobError extends Error {
  constructor(public readonly code: string, public readonly detail?: string) {
    super(code);
    this.name = "JobError";
  }
}

interface ImportRecord {
  id: string;
  wholesaler_id: string;
  file_path: string;
  file_type: string;
  status: string;
}

interface CallLog extends CallMeta {
  part: string;
  outcome: string;
}

interface Piece {
  data: Extraction;
  output: unknown;
  /** 这一段第一样商品在整份表里的位置（排序用） */
  baseOrder: number;
}

interface Job {
  admin: SupabaseClient;
  imp: ImportRecord;
  runId: string;
  claimedAt: string;
  deadline: number;
  apiKey: string | null;
  abort: AbortController;
  calls: CallLog[];
  file: Record<string, unknown>;
}

const withCors = (res: Response): Response => {
  for (const [k, v] of Object.entries(CORS_HEADERS)) res.headers.set(k, v);
  return res;
};

// ---------------------------------------------------------------------------
// 档案
// ---------------------------------------------------------------------------

/** file_path 是 bucket 里的路径（也接受前面多了 price-lists/）；第一层一定要是这家批发商的 id */
export function storagePath(filePath: string, wholesalerId: string): string {
  let p = (filePath ?? "").trim().replace(/^\/+/, "");
  if (p.startsWith(`${BUCKET}/`)) p = p.slice(BUCKET.length + 1);
  const parts = p.split("/");
  if (
    parts.length < 2 || parts[0].toLowerCase() !== wholesalerId.toLowerCase() ||
    parts.some((s) => s === "" || s === "." || s === "..")
  ) {
    throw new JobError("INVALID_FILE_PATH");
  }
  return p;
}

async function download(admin: SupabaseClient, path: string): Promise<Uint8Array> {
  const { data, error } = await admin.storage.from(BUCKET).download(path);
  if (error || !data) {
    const e = (error ?? {}) as unknown as Record<string, unknown>;
    const status = String(e.statusCode ?? e.status ?? "");
    const notFound = status === "404" || /not.?found/i.test(String(e.message ?? ""));
    throw new JobError(notFound ? "FILE_NOT_FOUND" : "DOWNLOAD_FAILED", String(e.message ?? ""));
  }
  if (data.size > MAX_FILE_BYTES) throw new JobError("FILE_TOO_LARGE");
  const bytes = new Uint8Array(await data.arrayBuffer());
  if (bytes.length === 0) throw new JobError("EMPTY_FILE");
  if (bytes.length > MAX_FILE_BYTES) throw new JobError("FILE_TOO_LARGE");
  return bytes;
}

// ---------------------------------------------------------------------------
// Claude
// ---------------------------------------------------------------------------

async function callClaude(
  job: Job,
  input: ExtractInput,
  effort: "low" | "medium",
  part: string,
): Promise<ExtractOutcome> {
  if (job.abort.signal.aborted) throw new JobError("ABORTED");
  if (!job.apiKey) throw new JobError("AI_NOT_CONFIGURED");
  const remaining = job.deadline - Date.now() - RESERVE_MS;
  if (remaining < MIN_CALL_MS) throw new JobError("AI_TIMEOUT");
  // SDK 的 timeout 只管到回应开始；streaming 整段也要在时间内，所以另外用 signal 中止
  const timeout = AbortSignal.timeout(remaining);
  let out: ExtractOutcome;
  try {
    out = await extractPriceList(input, {
      apiKey: job.apiKey,
      timeoutMs: remaining,
      effort,
      maxRetries: 1,
      signal: AbortSignal.any([job.abort.signal, timeout]),
    });
  } catch (e) {
    if (timeout.aborted) throw new JobError("AI_TIMEOUT");
    if (job.abort.signal.aborted) throw new JobError("ABORTED");
    throw e;
  }
  job.calls.push({ ...out.meta, part, outcome: out.ok ? "ok" : out.reason });
  if (out.meta.fallback || !out.ok) {
    log(out.ok ? "info" : "warn", "claude_call", {
      import_id: job.imp.id,
      part,
      outcome: out.ok ? "ok" : out.reason,
      model: out.meta.model,
      fallback: out.meta.fallback,
      refusal_category: out.meta.refusal_category,
    });
  }
  return out;
}

function toPiece(out: ExtractOutcome, baseOrder: number): Piece {
  if (out.ok) return { data: out.data, output: out.output, baseOrder };
  if (out.reason === "refusal") throw new JobError("AI_REFUSED", out.meta.refusal_category ?? undefined);
  if (out.reason === "max_tokens") throw new JobError("AI_TRUNCATED");
  throw new JobError("AI_INVALID_OUTPUT");
}

/** 照片 / PDF：一次读完。max_tokens → 用 low effort 再试一次（少想一点，多留位置给 JSON）；格式不对 → 再试一次 */
async function extractDocument(job: Job, input: ExtractInput): Promise<Piece[]> {
  let out = await callClaude(job, input, "medium", "document");
  if (!out.ok && out.reason === "max_tokens") out = await callClaude(job, input, "low", "document-retry");
  else if (!out.ok && out.reason === "invalid_output") out = await callClaude(job, input, "medium", "document-retry");
  return [toPiece(out, 0)];
}

/** Excel / CSV 的一段。max_tokens → 切成两半各试一次；格式不对 → 再试一次 */
async function extractChunk(
  job: Job,
  c: Chunk,
  index: number,
  total: number,
  order: Map<string, number>,
  canSplit: boolean,
): Promise<Piece[]> {
  const input: ExtractInput = { kind: "text", text: renderChunk(c), part: { index, total } };
  const label = `part ${index}/${total}${canSplit ? "" : " (half)"}`;
  let out = await callClaude(job, input, "medium", label);
  if (!out.ok && out.reason === "invalid_output") out = await callClaude(job, input, "medium", `${label} retry`);
  if (!out.ok && out.reason === "max_tokens" && canSplit) {
    const halves = splitChunk(c);
    if (halves) {
      const a = await extractChunk(job, halves[0], index, total, order, false);
      const b = await extractChunk(job, halves[1], index, total, order, false);
      return [...a, ...b];
    }
  }
  const first = c.lines.find((l) => !l.header);
  return [toPiece(out, first ? order.get(first.ref) ?? 0 : 0)];
}

async function extractSheet(job: Job, chunks: Chunk[], order: Map<string, number>): Promise<Piece[]> {
  const results = await mapLimit(chunks, CHUNK_CONCURRENCY, async (c, i) => {
    try {
      return await extractChunk(job, c, i + 1, chunks.length, order, true);
    } catch (e) {
      job.abort.abort(); // 一段失败整份就失败：别的段不用再叫
      throw e;
    }
  });
  return results.flat();
}

// ---------------------------------------------------------------------------
// 写进数据库的行
// ---------------------------------------------------------------------------

export interface DbRow {
  import_id: string;
  row_no: number;
  raw_text: string | null;
  name: string | null;
  unit: string | null;
  pack_qty: number | null;
  price_sen: number | null;
  min_order_qty: number | null;
  confidence: number | null;
  action: "create" | "skip";
}

export interface RowMeta {
  row_no: number;
  source_ref: string;
  unit_raw?: string;
  notes?: string | null;
  unreadable_reason?: string;
}

/** 照片 / PDF 的 source_ref「p2 line 14」→ 排序用的数字 */
function docOrder(ref: string): number | null {
  const m = /p\s*(\d+)\D+?(\d+)/i.exec(ref);
  return m ? Number(m[1]) * 1_000_000 + Number(m[2]) : null;
}

/**
 * 每段的结果合在一起，照原本的位置排（看不清的行也放在原本的位置），row_no 从 1 开始。
 * 看不清的行：只有 raw_text，action = skip。Excel 的 raw_text 没给就用那一行的原文。
 */
export function buildRows(
  importId: string,
  pieces: Piece[],
  lines: SheetLine[] | null,
): { rows: DbRow[]; meta: RowMeta[] } {
  const lineOrder = new Map((lines ?? []).map((l, i) => [l.ref, i]));
  const lineText = new Map((lines ?? []).map((l) => [l.ref, l.text]));
  const headerRefs = new Set((lines ?? []).filter((l) => l.header).map((l) => l.ref));
  type Item = { key: number; seq: number; row?: ExtractedRow; unread?: UnreadableRow };
  const items: Item[] = [];
  let seq = 0;
  for (const p of pieces) {
    let last = p.baseOrder;
    const keyOf = (ref: string) => {
      const k = lines ? lineOrder.get(ref) : docOrder(ref);
      if (k != null) last = k;
      return k ?? last;
    };
    for (const r of p.data.rows) {
      if (headerRefs.has(r.source_ref)) continue; // 表头不是商品
      items.push({ key: keyOf(r.source_ref), seq: seq++, row: r });
    }
    for (const u of p.data.unreadable) {
      if (headerRefs.has(u.source_ref)) continue;
      items.push({ key: keyOf(u.source_ref), seq: seq++, unread: u });
    }
  }
  items.sort((a, b) => a.key - b.key || a.seq - b.seq);

  const rows: DbRow[] = [];
  const meta: RowMeta[] = [];
  items.forEach((it, i) => {
    const row_no = i + 1;
    if (it.row) {
      const r = it.row;
      const raw = r.raw_text || (lineText.get(r.source_ref) ?? "").slice(0, 500) || r.name;
      rows.push({
        import_id: importId,
        row_no,
        raw_text: raw,
        name: r.name,
        unit: r.unit,
        pack_qty: r.pack_qty,
        price_sen: r.price_sen,
        min_order_qty: r.min_order_qty,
        confidence: r.confidence,
        action: "create",
      });
      meta.push({ row_no, source_ref: r.source_ref, unit_raw: r.unit_raw, notes: r.notes });
    } else if (it.unread) {
      const u = it.unread;
      const raw = (u.raw_text && u.raw_text !== "?" ? u.raw_text : lineText.get(u.source_ref)) || u.raw_text || "?";
      rows.push({
        import_id: importId,
        row_no,
        raw_text: raw.slice(0, 500),
        name: null,
        unit: null,
        pack_qty: null,
        price_sen: null,
        min_order_qty: null,
        confidence: null,
        action: "skip",
      });
      meta.push({ row_no, source_ref: u.source_ref, unreadable_reason: u.reason });
    }
  });
  return { rows, meta };
}

function documentInfo(pieces: Piece[]) {
  const notes = [...new Set(pieces.map((p) => p.data.document_notes).filter((n): n is string => !!n))];
  return {
    supplier_name: pieces.map((p) => p.data.supplier_name).find((n) => !!n) ?? null,
    order_min_sen: pieces.map((p) => p.data.order_min_sen).find((n) => n != null) ?? null,
    document_notes: notes,
  };
}

// ---------------------------------------------------------------------------
// 背景工作
// ---------------------------------------------------------------------------

function errorCode(e: unknown): string {
  if (e instanceof JobError) return e.code;
  if (e instanceof SpreadsheetError) return e.code;
  if (e instanceof DbError) return "DB_ERROR";
  if (e instanceof ConfigError) return "INTERNAL_ERROR";
  return classifyClaudeError(e) ?? "INTERNAL_ERROR";
}

export async function processImport(job: Job): Promise<"review" | "failed"> {
  const { admin, imp } = job;
  try {
    const bytes = await download(admin, storagePath(imp.file_path, imp.wholesaler_id));
    const kind: FileKind = sniffFileType(bytes);
    job.file = { kind, bytes: bytes.length };

    let pieces: Piece[];
    let lines: SheetLine[] | null = null;
    if (isImage(kind)) {
      if (bytes.length > MAX_IMAGE_BYTES) throw new JobError("FILE_TOO_LARGE");
      pieces = await extractDocument(job, {
        kind: "image",
        mediaType: IMAGE_MEDIA_TYPES[kind],
        base64: encodeBase64(bytes),
      });
    } else if (kind === "pdf") {
      pieces = await extractDocument(job, { kind: "pdf", base64: encodeBase64(bytes) });
    } else if (isSpreadsheet(kind)) {
      lines = workbookLines(readWorkbook(bytes, kind));
      const chunks = chunkLines(lines);
      job.file = { ...job.file, lines: lines.length, chunks: chunks.length };
      pieces = await extractSheet(job, chunks, new Map(lines.map((l, i) => [l.ref, i])));
    } else {
      throw new JobError("UNSUPPORTED_FILE", kind); // HEIC、Word、zip……
    }

    const { rows, meta } = buildRows(imp.id, pieces, lines);
    if (rows.length === 0) throw new JobError("NO_PRODUCTS_FOUND");

    // 之前跑到一半死掉的话可能留下旧的行
    unwrap("delete rows", await admin.from("price_list_import_rows").delete().eq("import_id", imp.id));
    for (let i = 0; i < rows.length; i += INSERT_BATCH) {
      unwrap("insert rows", await admin.from("price_list_import_rows").insert(rows.slice(i, i + INSERT_BATCH)));
    }
    const matches = await rpc<{ rows?: number; matched?: number; suggested?: number }>(
      admin,
      "suggest_import_matches",
      {
        p_import_id: imp.id,
      },
    );

    const aiRaw = {
      version: 1,
      state: "done",
      run_id: job.runId,
      claimed_at: job.claimedAt,
      finished_at: new Date().toISOString(),
      model: PRICE_LIST_MODEL,
      file: job.file,
      document: documentInfo(pieces),
      matches,
      rows: meta,
      calls: job.calls,
      outputs: pieces.map((p) => p.output),
    };
    const updated = unwrap(
      "update import",
      await admin.from("price_list_imports")
        .update({ status: "review", error_message: null, ai_raw: aiRaw })
        .eq("id", imp.id).eq("status", "processing").eq("ai_raw->>run_id", job.runId)
        .select("id"),
    ) as unknown[] | null;
    if (!updated || updated.length === 0) log("warn", "import_changed_during_run", { import_id: imp.id });
    log("info", "price_list_parsed", {
      import_id: imp.id,
      kind,
      rows: rows.length,
      calls: job.calls.length,
      ...matches,
    });
    return "review";
  } catch (e) {
    const code = errorCode(e);
    log("error", "price_list_failed", {
      import_id: imp.id,
      code,
      detail: e instanceof JobError ? e.detail : errorMessage(e),
    });
    try {
      unwrap("delete rows", await admin.from("price_list_import_rows").delete().eq("import_id", imp.id));
    } catch (e2) {
      log("error", "price_list_cleanup_failed", { import_id: imp.id, error: errorMessage(e2) });
    }
    try {
      unwrap(
        "update import",
        await admin.from("price_list_imports")
          .update({
            status: "failed",
            error_message: code,
            ai_raw: {
              version: 1,
              state: "failed",
              error: code,
              run_id: job.runId,
              claimed_at: job.claimedAt,
              finished_at: new Date().toISOString(),
              file: job.file,
              calls: job.calls,
            },
          })
          .eq("id", imp.id).eq("ai_raw->>run_id", job.runId),
      );
    } catch (e2) {
      log("error", "price_list_mark_failed_failed", { import_id: imp.id, error: errorMessage(e2) });
    }
    return "failed";
  }
}

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------

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
    log("error", "parse_price_list_not_configured", { error: errorMessage(e) });
    return withCors(json({ error: "CONFIG_MISSING" }, 500));
  }

  try {
    // 1. 验用户
    const { data: auth, error: authError } = await uc.auth.getUser(jwt);
    if (authError || !auth?.user) return withCors(json({ error: "UNAUTHORIZED" }, 401));

    // 2. 参数
    const body = await req.json().catch(() => null) as { import_id?: unknown } | null;
    const importId = typeof body?.import_id === "string" ? body.import_id.trim() : "";
    if (!UUID_RE.test(importId)) return withCors(json({ error: "INVALID_IMPORT_ID" }, 400));

    // 3. 用用户身份读（RLS：只看得到自己批发商的；客服全部）
    const res = await uc.from("price_list_imports")
      .select("id, wholesaler_id, file_path, file_type, status")
      .eq("id", importId)
      .maybeSingle();
    if (res.error) {
      if (res.status === 401 || res.status === 403) return withCors(json({ error: "UNAUTHORIZED" }, 401));
      throw new DbError("read import", res.error.message, res.error.code ?? "", res.status);
    }
    const imp = res.data as ImportRecord | null;
    if (!imp) return withCors(json({ error: "IMPORT_NOT_FOUND" }, 404));
    if (imp.status !== "processing") return withCors(json({ error: "IMPORT_NOT_PROCESSING", status: imp.status }, 409));

    // 4. 占位（同一份 import 只跑一次；「在跑」超过 10 分钟的当成死掉，可以重跑）
    const runId = crypto.randomUUID();
    const claimedAt = new Date().toISOString();
    const staleBefore = new Date(Date.now() - STALE_CLAIM_MS).toISOString();
    const claimed = unwrap(
      "claim import",
      await admin.from("price_list_imports")
        .update({
          ai_raw: { version: 1, state: "running", run_id: runId, claimed_at: claimedAt, claimed_by: auth.user.id },
        })
        .eq("id", imp.id)
        .eq("status", "processing")
        .or(`ai_raw.is.null,ai_raw->>claimed_at.lt."${staleBefore}"`)
        .select("id"),
    ) as unknown[] | null;
    if (!claimed || claimed.length === 0) return withCors(json({ error: "IMPORT_ALREADY_RUNNING" }, 409));

    // 5. 背景处理，先回 202
    const job: Job = {
      admin,
      imp,
      runId,
      claimedAt,
      deadline: Date.now() + intEnv("PRICE_LIST_TIME_BUDGET_MS", 380_000, 30_000, 900_000),
      apiKey: anthropicApiKey(),
      abort: new AbortController(),
      calls: [],
      file: {},
    };
    const work = processImport(job);
    if (!runInBackground(work)) await work;
    return withCors(json({ import_id: imp.id, status: "processing" }, 202));
  } catch (e) {
    log("error", "parse_price_list_error", { error: errorMessage(e) });
    return withCors(json({ error: e instanceof DbError ? "DB_ERROR" : "INTERNAL_ERROR" }, 500));
  }
}

export default { fetch: handler };
