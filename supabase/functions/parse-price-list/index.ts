// parse-price-list：把上传的价目表（照片 / PDF / Excel / CSV）交给 Claude，写成待确认的行。
// App：supabase.functions.invoke('parse-price-list', body: {import_id})（自动带用户 JWT）。
// config.toml 里 verify_jwt = false；这里自己验：auth.getUser(jwt)，再用用户身份读 import（RLS 保证是自己的）。
// 然后叫数据库函数 reserve_price_list_run（服务器身份）：成员、停权、状态、在跑、用量在一个交易里检查完再占位
// （20261127000200_seller_hardening.sql；用量记在 price_list_runs，批发商碰不到）。
//
//   回应：202 {import_id, status}（之后 App 每 3 秒查 price_list_imports.status）
//         400 INVALID_IMPORT_ID、401 UNAUTHORIZED、
//         404 IMPORT_NOT_FOUND（RLS 读不到 / not_found / not_member）、403 WHOLESALER_SUSPENDED（suspended）、
//         409 IMPORT_NOT_PROCESSING（not_processing，带 status）/ IMPORT_ALREADY_RUNNING（already_running）、
//         429 TOO_MANY_IMPORTS（quota；retry_after 秒、window、Retry-After 头）、
//         503 QUOTA_UNAVAILABLE（叫不到 reserve_price_list_run：暂时的，import 没动）、
//         503 AUTH_UNAVAILABLE（Auth 服务暂时出错 / 断线 / 太忙，验不了 JWT：暂时的，不是登录过期，import 没动）、
//         500 CONFIG_MISSING / DB_ERROR / INTERNAL_ERROR、405 METHOD_NOT_ALLOWED
//   背景（EdgeRuntime.waitUntil；Opus 读一份价目表可能超过 150 秒）：
//     下载（服务器身份，最多 10 MB）→ 魔术字节判断格式 → 图片 / PDF 直接给 Claude；
//     Excel / CSV → 带行号文字 → 分段给 Claude → 写 price_list_import_rows（row_no 从 1）→
//     suggest_import_matches → status = review。任何错误 → status = failed + error_message（英文代码）。
//   时间：平台的总时间是按 worker 算的（一个 worker 会接很多个请求），所以期限 = 这个 worker 开始的时间 + 预算，
//         不是请求进来的时间 + 预算。worker 要被关掉时（beforeunload：总时间到、CPU / 记忆体超过）
//         先中止正在跑的工作、马上把 import 标成 failed，不会一直卡在 processing。
//         Excel 每段 50 行、PDF 每段 4 页，最多同时 8 段；开始叫 Claude 之前先估计跑得完跑不完
//         （一段估 90 秒）：整个预算都不够 → TOO_MANY_ROWS，这个 worker 剩下的不够 → AI_TIMEOUT，不白花钱。
//         失败时写数据库暂时失败 → 隔 0.5 / 2 / 5 秒再试（不然会一直卡在 processing）。
//   用量：每家批发商 10 分钟 / 1 小时 / 1 天最多跑几次（数字在数据库的 _price_list_run_limits；还没审核的更少），
//         超过 → 429；停权 → 403。之后写回 import 都要 status = processing、ai_raw->>run_id = 这一次的 run_id。
//         卡住的（worker 被杀掉、beforeunload 也没跑到）由定时任务 fail_stuck_price_list_imports 收拾（15 分钟）。
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
import { type PageRange, pageRanges, pdfPageCount, splitRange } from "../_shared/pdf.ts";
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
  randomTag,
  type UnreadableRow,
} from "../_shared/claude.ts";

export const BUCKET = "price-lists";
export const MAX_FILE_BYTES = 10 * 1024 * 1024;
/** Claude：一张图 base64 之后最多 10 MB（原始大约 7.5 MB） */
const MAX_IMAGE_BYTES = 7_000_000;
/** PDF 超过这么多页就分段读（每段这么多页） */
export const PDF_PAGES_PER_CALL = 4;
/**
 * 时间预算（PRICE_LIST_TIME_BUDGET_MS）最多 9 分钟：reserve_price_list_run 把「在跑」超过 10 分钟的当成死掉
 * （可以重新占位，两个 worker 会一起跑），定时任务 15 分钟标 AI_TIMEOUT。再大就用默认值。
 */
export const MAX_BUDGET_MS = 540_000;
const INSERT_BATCH = 500;

export const TIMING = {
  /** 留给最后写数据库的时间 */
  reserveMs: 15_000,
  /** 剩下不到这么多时间就不再叫 Claude */
  minCallMs: 20_000,
  /** 同时叫几个 Claude（一份 Excel / PDF 的几段） */
  concurrency: 8,
  /** 估计一段（50 行 / 4 页）Claude 要读多久：Opus medium 读 100-150 行可能超过 150 秒（verifications.json） */
  partEstimateMs: 90_000,
  /** 失败时写数据库暂时失败：隔多久再试（不超过期限） */
  failRetryMs: [500, 2_000, 5_000],
  /** PDF 分段：第一段开始回应（快取写好）之前，别段最多等多久 */
  cacheWarmMs: 30_000,
};

/** 这个 worker（isolate）什么时候开始的：Supabase 的总时间（免费 150 秒、付费 400 秒）从这里算 */
export const isolate = { startedAt: Date.now() };

/** 工作期限：请求进来 + 预算，也不能超过 worker 开始 + 预算（晚进来的请求分到的时间比较少） */
export function jobDeadline(now: number, budgetMs: number, isolateStartedAt = isolate.startedAt): number {
  return Math.min(now + budgetMs, isolateStartedAt + budgetMs);
}

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
  /** 设定的时间预算（PRICE_LIST_TIME_BUDGET_MS）：估计跑不跑得完用 */
  budgetMs: number;
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

/** 被中止时丢的错：worker 要关掉（beforeunload）时带着原因；别段失败时是 ABORTED（不会变成 error_message） */
function abortError(job: Job): JobError {
  const reason = job.abort.signal.reason;
  return reason instanceof JobError ? reason : new JobError("ABORTED");
}

async function callClaude(
  job: Job,
  input: ExtractInput,
  effort: "low" | "medium",
  part: string,
  onStart?: () => void,
): Promise<ExtractOutcome> {
  if (job.abort.signal.aborted) throw abortError(job);
  if (!job.apiKey) throw new JobError("AI_NOT_CONFIGURED");
  const remaining = job.deadline - Date.now() - TIMING.reserveMs;
  if (remaining < TIMING.minCallMs) throw new JobError("AI_TIMEOUT");
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
      onStart,
    });
  } catch (e) {
    if (job.abort.signal.aborted) throw abortError(job);
    if (timeout.aborted) throw new JobError("AI_TIMEOUT");
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

/**
 * 开始叫 Claude 之前：照「几段、同时几段、一段估计多久」算要几轮，跑不完就不要开始（不然花了钱最后还是 AI_TIMEOUT）。
 * 整个预算都不够（换新的 worker 也一样）→ TOO_MANY_ROWS（请批发商把档案分开）；这个 worker 剩下的不够 → AI_TIMEOUT。
 */
export function checkPlan(job: Pick<Job, "deadline" | "budgetMs">, parts: number, now = Date.now()): void {
  const rounds = Math.ceil(parts / TIMING.concurrency);
  const need = rounds * TIMING.partEstimateMs;
  if (need > job.budgetMs - TIMING.reserveMs) {
    throw new JobError("TOO_MANY_ROWS", `${parts} parts need ${rounds} rounds of Claude calls`);
  }
  if (need > job.deadline - now - TIMING.reserveMs) {
    throw new JobError("AI_TIMEOUT", `${parts} parts need ${rounds} rounds; not enough time left in this worker`);
  }
}

/** 照片：一次读完。max_tokens → 用 low effort 再试一次（少想一点，多留位置给 JSON）；格式不对 → 再试一次 */
async function extractImage(job: Job, input: ExtractInput): Promise<Piece[]> {
  let out = await callClaude(job, input, "medium", "document");
  if (!out.ok && out.reason === "max_tokens") out = await callClaude(job, input, "low", "document-retry");
  else if (!out.ok && out.reason === "invalid_output") out = await callClaude(job, input, "medium", "document-retry");
  return [toPiece(out, 0)];
}

interface PdfJob {
  base64: string;
  /** 每段都一样（开头标签 + PDF 一模一样才读得到快取） */
  tag: string;
  total: number;
}

/**
 * PDF 的一段页面（range = null：整份一次读，页数少或数不出来）。格式不对 → 再试一次。
 * max_tokens → 页面切两半、同时读（只切一次）；只有一页或不知道几页 → low effort 再试一次。
 */
async function extractPdfPart(
  job: Job,
  pdf: PdfJob,
  range: PageRange | null,
  index: number,
  pages: number | null,
  canSplit: boolean,
  onStart?: () => void,
): Promise<Piece[]> {
  const input: ExtractInput = range
    ? {
      kind: "pdf",
      base64: pdf.base64,
      tag: pdf.tag,
      pages: { from: range.from, to: range.to, index, total: pdf.total },
    }
    : { kind: "pdf", base64: pdf.base64 };
  const label = range ? `pages ${range.from}-${range.to ?? "end"}${canSplit ? "" : " (half)"}` : "document";
  let out = await callClaude(job, input, "medium", label, onStart);
  if (!out.ok && out.reason === "invalid_output") out = await callClaude(job, input, "medium", `${label} retry`);
  if (!out.ok && out.reason === "max_tokens") {
    const whole = range ?? (pages && pages > 1 ? { from: 1, to: null, last: pages } : null);
    const halves = canSplit && whole ? splitRange(whole) : null;
    if (halves) {
      const total = range ? pdf.total : 2;
      const parts = await Promise.all(
        halves.map((h, i) => extractPdfPart(job, { ...pdf, total }, h, range ? index : i + 1, pages, false)),
      );
      return parts.flat();
    }
    // 只有一页（或不知道几页）：少想一点再试一次
    if (canSplit) out = await callClaude(job, input, "low", `${label} low`);
  }
  return [toPiece(out, (range?.from ?? 0) * 1_000_000)];
}

/** PDF：超过 PDF_PAGES_PER_CALL 页就分段（每段同一个 document block + cache_control，只读那几页） */
async function extractPdf(job: Job, base64: string, pages: number | null): Promise<Piece[]> {
  const ranges = pageRanges(pages, PDF_PAGES_PER_CALL);
  const pdf: PdfJob = { base64, tag: randomTag(), total: ranges?.length ?? 1 };
  if (!ranges) return await extractPdfPart(job, pdf, null, 1, pages, true);
  checkPlan(job, ranges.length);
  // 第一段先送：PDF 写进快取（回应开始）之后别段再送，不然同时送的每段都要付整份 PDF 的钱
  let warmUp: () => void = () => {};
  let timer: ReturnType<typeof setTimeout> | undefined;
  const warm = new Promise<void>((resolve) => {
    warmUp = resolve;
    timer = setTimeout(resolve, TIMING.cacheWarmMs);
  });
  try {
    const results = await mapLimit(ranges, TIMING.concurrency, async (r, i) => {
      try {
        if (i > 0) await warm;
        if (job.abort.signal.aborted) throw abortError(job);
        return await extractPdfPart(job, pdf, r, i + 1, pages, true, i === 0 ? warmUp : undefined);
      } catch (e) {
        job.abort.abort(); // 一段失败整份就失败：别的段不用再叫
        throw e;
      } finally {
        if (i === 0) warmUp();
      }
    });
    return results.flat();
  } finally {
    clearTimeout(timer);
  }
}

/** Excel / CSV 的一段。max_tokens → 切成两半同时各试一次；格式不对 → 再试一次 */
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
      // 同时读两半：一个接一个的话，max_tokens 之后剩下的时间通常不够
      const parts = await Promise.all(halves.map((h) => extractChunk(job, h, index, total, order, false)));
      return parts.flat();
    }
  }
  const first = c.lines.find((l) => !l.header);
  return [toPiece(out, first ? order.get(first.ref) ?? 0 : 0)];
}

async function extractSheet(job: Job, chunks: Chunk[], order: Map<string, number>): Promise<Piece[]> {
  checkPlan(job, chunks.length);
  const results = await mapLimit(chunks, TIMING.concurrency, async (c, i) => {
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

export function errorCode(e: unknown): string {
  if (e instanceof JobError) return e.code;
  if (e instanceof SpreadsheetError) return e.code;
  if (e instanceof DbError) return "DB_ERROR";
  if (e instanceof ConfigError) return "INTERNAL_ERROR";
  return classifyClaudeError(e) ?? "INTERNAL_ERROR";
}

/** 这个 worker 里正在跑的工作（beforeunload 时要处理） */
const RUNNING = new Set<Job>();

/** worker 要被关掉的原因 → error_message：总时间到 → AI_TIMEOUT；CPU / 记忆体超过 → INTERNAL_ERROR */
export function shutdownCode(reason: string): string {
  return /cpu|mem/i.test(reason) ? "INTERNAL_ERROR" : "AI_TIMEOUT";
}

/**
 * worker 要被关掉了（Supabase 的 beforeunload，ev.detail.reason）：中止正在跑的工作，马上把 import 标成 failed
 * （只改还是 processing、而且是这一次 run_id 的）。之后 worker 就没了，processImport 的 catch 不一定跑得到。
 */
export async function handleShutdown(reason: string): Promise<void> {
  const jobs = [...RUNNING];
  if (jobs.length === 0) return;
  const code = shutdownCode(reason);
  log("error", "price_list_worker_shutdown", { reason, code, jobs: jobs.length });
  await Promise.all(jobs.map(async (job) => {
    job.abort.abort(new JobError(code, `worker shutdown: ${reason}`));
    try {
      const updated = unwrap(
        "mark interrupted",
        await job.admin.from("price_list_imports")
          .update({
            status: "failed",
            error_message: code,
            ai_raw: {
              version: 1,
              state: "failed",
              error: code,
              interrupted: reason,
              run_id: job.runId,
              claimed_at: job.claimedAt,
              finished_at: new Date().toISOString(),
              file: job.file,
              calls: job.calls,
            },
          })
          .eq("id", job.imp.id).eq("status", "processing").eq("ai_raw->>run_id", job.runId)
          .select("id"),
      ) as unknown[] | null;
      if (updated && updated.length > 0) {
        unwrap("delete rows", await job.admin.from("price_list_import_rows").delete().eq("import_id", job.imp.id));
      }
    } catch (e) {
      log("error", "price_list_mark_failed_failed", { import_id: job.imp.id, error: errorMessage(e) });
    }
  }));
}

(globalThis as { addEventListener?: typeof addEventListener }).addEventListener?.("beforeunload", (ev: Event) => {
  const detail = (ev as CustomEvent<{ reason?: unknown } | undefined>).detail;
  handleShutdown(String(detail?.reason ?? "unknown")).catch(() => {});
});

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** 写数据库；暂时失败（网络、5xx……）→ 隔 TIMING.failRetryMs 再试，不超过期限、worker 要关掉就不再试 */
async function retryDb(job: Job, what: string, op: () => Promise<unknown>): Promise<void> {
  for (let attempt = 0;; attempt++) {
    try {
      await op();
      return;
    } catch (e) {
      const transient = e instanceof DbError ? e.transient : true;
      const wait = TIMING.failRetryMs[attempt];
      const shuttingDown = job.abort.signal.reason instanceof JobError;
      if (!transient || wait === undefined || shuttingDown || Date.now() + wait > job.deadline) throw e;
      log("warn", "price_list_write_retry", { import_id: job.imp.id, what, attempt, error: errorMessage(e) });
      await sleep(wait);
    }
  }
}

export async function processImport(job: Job): Promise<"review" | "failed"> {
  RUNNING.add(job);
  try {
    return await runImport(job);
  } finally {
    RUNNING.delete(job);
  }
}

async function runImport(job: Job): Promise<"review" | "failed"> {
  const { admin, imp } = job;
  try {
    const bytes = await download(admin, storagePath(imp.file_path, imp.wholesaler_id));
    const kind: FileKind = sniffFileType(bytes);
    job.file = { kind, bytes: bytes.length };

    let pieces: Piece[];
    let lines: SheetLine[] | null = null;
    if (isImage(kind)) {
      if (bytes.length > MAX_IMAGE_BYTES) throw new JobError("FILE_TOO_LARGE");
      pieces = await extractImage(job, {
        kind: "image",
        mediaType: IMAGE_MEDIA_TYPES[kind],
        base64: encodeBase64(bytes),
      });
    } else if (kind === "pdf") {
      const pages = await pdfPageCount(bytes);
      job.file = { ...job.file, pages };
      pieces = await extractPdf(job, encodeBase64(bytes), pages);
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
    if (job.abort.signal.aborted) throw abortError(job); // worker 要关掉了：不要再写

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
    // 先把状态改成 failed（最要紧：不然 App 一直显示「AI 在读」），再删行（下次重跑也会先删）。
    // 数据库暂时连不上的话隔一下再试（同一个问题常常让上面的错误跟这两个写入一起失败）
    try {
      await retryDb(job, "mark failed", async () =>
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
            // 还是 processing 才改：定时任务已经标了 AI_TIMEOUT、App 已经标了失败的，不要盖掉
            .eq("id", imp.id).eq("status", "processing").eq("ai_raw->>run_id", job.runId),
        ));
    } catch (e2) {
      log("error", "price_list_mark_failed_failed", { import_id: imp.id, error: errorMessage(e2) });
    }
    try {
      await retryDb(
        job,
        "cleanup",
        async () => unwrap("delete rows", await admin.from("price_list_import_rows").delete().eq("import_id", imp.id)),
      );
    } catch (e2) {
      log("error", "price_list_cleanup_failed", { import_id: imp.id, error: errorMessage(e2) });
    }
    return "failed";
  }
}

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------

/** 时间预算：PRICE_LIST_TIME_BUDGET_MS（30 秒到 MAX_BUDGET_MS），没设或超过范围就用 380 秒（付费方案 400 秒） */
export function timeBudgetMs(): number {
  return intEnv("PRICE_LIST_TIME_BUDGET_MS", 380_000, 30_000, MAX_BUDGET_MS);
}

/**
 * auth.getUser 的错误是不是 Auth 服务自己的问题（断线、逾时、5xx、429 太忙、回的不是 JSON）：
 * 这时候 JWT 可能是好的，不能回 401（App 会当成登录过期、把导入标 AUTH 失败）。
 * auth-js 不会丢错，是回 {error}：断线 / 5xx 是 AuthRetryableFetchError（status 0 / 5xx），
 * 回的不是 JSON 是 AuthUnknownError；JWT 不对（401 / 403、session 不在了）才是真的 UNAUTHORIZED。
 */
export function authUnavailable(e: unknown): boolean {
  if (!e || typeof e !== "object") return false;
  const { name, status } = e as { name?: unknown; status?: unknown };
  if (name === "AuthRetryableFetchError" || name === "AuthUnknownError") return true;
  return typeof status === "number" && (status === 0 || status === 429 || status >= 500);
}

/** reserve_price_list_run 会回的「不跑」结果 */
const REFUSALS = new Set(["not_found", "not_member", "suspended", "not_processing", "already_running", "quota"]);

/**
 * reserve_price_list_run 不是 ok 的结果 → HTTP 回应（数据库什么都没改：没占位、没算次数）。
 * 认不得的结果（迁移跟代码对不上）当成叫不到 → 503。
 */
export function refusalResponse(r: Record<string, unknown>): Response {
  switch (r.result) {
    case "not_found":
    case "not_member": // 不是这家的成员：跟读不到一样，不说有没有这份导入
      return json({ error: "IMPORT_NOT_FOUND" }, 404);
    case "suspended":
      return json({ error: "WHOLESALER_SUSPENDED" }, 403);
    case "not_processing":
      return json({ error: "IMPORT_NOT_PROCESSING", status: typeof r.status === "string" ? r.status : null }, 409);
    case "already_running":
      return json({ error: "IMPORT_ALREADY_RUNNING" }, 409);
    case "quota": {
      const n = Number(r.retry_after_sec);
      const sec = Number.isFinite(n) && n >= 1 ? Math.ceil(n) : 60;
      const window = typeof r.window === "string" ? r.window : null;
      return json({ error: "TOO_MANY_IMPORTS", retry_after: sec, window }, 429, { "Retry-After": String(sec) });
    }
  }
  return json({ error: "QUOTA_UNAVAILABLE" }, 503);
}

const str = (v: unknown): string | null => (typeof v === "string" && v !== "" ? v : null);

export async function handler(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return withCors(new Response(null, { status: 204 }));
  if (req.method !== "POST") return withCors(json({ error: "METHOD_NOT_ALLOWED" }, 405));

  const jwt = bearerToken(req);
  if (!jwt) return withCors(json({ error: "UNAUTHORIZED" }, 401));

  // 设定全部先读好：占位之后才出错的话，import 会卡在「在跑」、还算掉一次用量
  let env: SupabaseEnv;
  let uc: SupabaseClient;
  let admin: SupabaseClient;
  let budgetMs: number;
  let apiKey: string | null;
  try {
    env = supabaseEnv();
    uc = userClient(jwt, env);
    admin = adminClient(env);
    budgetMs = timeBudgetMs();
    apiKey = anthropicApiKey(); // 没设：照样占位、背景标 failed AI_NOT_CONFIGURED（App 显示原因）
  } catch (e) {
    log("error", "parse_price_list_not_configured", { error: errorMessage(e) });
    return withCors(json({ error: "CONFIG_MISSING" }, 500));
  }

  try {
    // 1. 验用户
    const { data: auth, error: authError } = await uc.auth.getUser(jwt);
    if (authError && authUnavailable(authError)) {
      log("warn", "price_list_auth_unavailable", {
        name: authError.name,
        status: (authError as { status?: unknown }).status ?? null,
        error: errorMessage(authError),
      });
      return withCors(json({ error: "AUTH_UNAVAILABLE" }, 503));
    }
    if (authError || !auth?.user) return withCors(json({ error: "UNAUTHORIZED" }, 401));

    // 2. 参数
    const body = await req.json().catch(() => null) as { import_id?: unknown } | null;
    const importId = typeof body?.import_id === "string" ? body.import_id.trim() : "";
    if (!UUID_RE.test(importId)) return withCors(json({ error: "INVALID_IMPORT_ID" }, 400));

    // 3. 用用户身份读（RLS：只看得到自己批发商的；客服全部）。读不到 → 404，不叫 reserve
    const res = await uc.from("price_list_imports")
      .select("id, wholesaler_id, file_path, file_type")
      .eq("id", importId)
      .maybeSingle();
    if (res.error) {
      if (res.status === 401 || res.status === 403) return withCors(json({ error: "UNAUTHORIZED" }, 401));
      throw new DbError("read import", res.error.message, res.error.code ?? "", res.status);
    }
    const seen = res.data as ImportRecord | null;
    if (!seen) return withCors(json({ error: "IMPORT_NOT_FOUND" }, 404));

    // 4. 占位 + 用量：一个数据库函数、一个交易（服务器身份；price_list_runs 批发商碰不到）。
    //    状态不对、已经在跑、停权、用量满了都在这里挡（顺序照 SQL），挡下来的什么都没改
    const runId = crypto.randomUUID();
    let r: Record<string, unknown>;
    try {
      const out = await rpc<unknown>(admin, "reserve_price_list_run", {
        p_import_id: seen.id,
        p_user_id: auth.user.id,
        p_run_id: runId,
      });
      r = out && typeof out === "object" ? out as Record<string, unknown> : {};
    } catch (e) {
      log("error", "price_list_reserve_failed", { import_id: seen.id, error: errorMessage(e) });
      return withCors(json({ error: "QUOTA_UNAVAILABLE" }, 503));
    }
    if (r.result !== "ok") {
      const known = REFUSALS.has(String(r.result));
      log(
        known ? (r.result === "quota" ? "warn" : "info") : "error",
        known ? "price_list_not_started" : "price_list_reserve_unexpected",
        {
          import_id: seen.id,
          wholesaler_id: seen.wholesaler_id,
          result: r.result ?? null,
          window: r.window,
          retry_after_sec: r.retry_after_sec,
        },
      );
      return withCors(refusalResponse(r));
    }

    // 5. 背景处理，先回 202。档案路径、批发商用 reserve 锁住时读到的（RLS 读的当备用）；
    //    run_id、claimed_at 照数据库写进 ai_raw 的，之后写回都用 run_id 过滤
    const job: Job = {
      admin,
      imp: {
        id: seen.id,
        wholesaler_id: str(r.wholesaler_id) ?? seen.wholesaler_id,
        file_path: str(r.file_path) ?? seen.file_path,
        file_type: str(r.file_type) ?? seen.file_type,
      },
      runId: str(r.run_id) ?? runId,
      claimedAt: str(r.claimed_at) ?? new Date().toISOString(),
      deadline: jobDeadline(Date.now(), budgetMs),
      budgetMs,
      apiKey,
      abort: new AbortController(),
      calls: [],
      file: {},
    };
    const work = processImport(job);
    if (!runInBackground(work)) await work;
    return withCors(json({ import_id: seen.id, status: "processing" }, 202));
  } catch (e) {
    log("error", "parse_price_list_error", { error: errorMessage(e) });
    return withCors(json({ error: e instanceof DbError ? "DB_ERROR" : "INTERNAL_ERROR" }, 500));
  }
}

export default { fetch: handler };
