// Excel / CSV → 一行一行、带行号的文字（Claude 不能直接读 Excel）。
//   Harga!R12: 1 | 16安士 PP杯 95口径 | 箱 | RM85.00
// 表头那一行标 [context]；太长就分段，每段开头重复那张表的表头。
// SheetJS 0.20.3 只放在 cdn.sheetjs.com（npm 的 xlsx 0.18.5 有安全漏洞，不能用）。
// xlsx 交给 SheetJS 之前先过 zipguard.ts（zip 炸弹会让 worker 被杀掉，catch 不会跑）。

// @deno-types="https://cdn.sheetjs.com/xlsx-0.20.3/package/types/index.d.ts"
import * as XLSX from "xlsx";
import { inspectXlsxZip, ZipGuardError } from "./zipguard.ts";

export type SpreadsheetErrorCode = "SPREADSHEET_UNREADABLE" | "TOO_MANY_ROWS" | "EMPTY_SPREADSHEET" | "FILE_TOO_LARGE";

export class SpreadsheetError extends Error {
  constructor(public readonly code: SpreadsheetErrorCode, public readonly detail?: string) {
    super(detail ? `${code}: ${detail}` : code);
    this.name = "SpreadsheetError";
  }
}

/** 文字档：先试 UTF-8（严格），不行再用 gb18030（中文 Excel 存的 CSV 常常是这个）。UTF-16 看 BOM。 */
export function decodeText(bytes: Uint8Array): string {
  if (bytes[0] === 0xff && bytes[1] === 0xfe) return new TextDecoder("utf-16le").decode(bytes);
  if (bytes[0] === 0xfe && bytes[1] === 0xff) return new TextDecoder("utf-16be").decode(bytes);
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes); // 会去掉 BOM
  } catch {
    return new TextDecoder("gb18030").decode(bytes);
  }
}

export type SheetKind = "xlsx" | "xls" | "csv";

/** 整份最多几行商品（不算表头、空行） */
export const MAX_LINES = 1200;
/**
 * 每张表最多读到第几行（SheetJS 的 sheetRows 是从第 1 行算的绝对行号，空行也算）。
 * 中间夹空行、表从下面才开始都没关系；这一行以下还有东西 → TOO_MANY_ROWS（不会悄悄少掉商品）。
 */
export const MAX_SCAN_ROWS = 4 * MAX_LINES;
/** 每行最多看几栏（一行最多 1000 个字，再多栏也用不到；也防止一格放在很右边让每行都变成上万栏） */
export const MAX_SCAN_COLS = 256;
const MAX_LINE_CHARS = 1000;

const BLANK_CSV_CHAR = new Set([0x20, 0x09, 0x2c, 0x3b, 0x7c, 0x22, 0xa0, 0xfeff, 0x3000]); // 空白 , ; | " 全形空白

/** CSV 里最后一行有内容的是第几行（0 起算；照实际换行算，引号里的换行也算一行，所以只会多算不会少算） */
export function lastFilledLine(text: string): number {
  let line = 0;
  let last = -1;
  let filled = false;
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    if (c === 10 || c === 13) {
      if (filled) last = line;
      if (c === 13 && text.charCodeAt(i + 1) === 10) i++;
      line++;
      filled = false;
    } else if (!filled && !BLANK_CSV_CHAR.has(c)) {
      filled = true;
    }
  }
  return filled ? line : last;
}

export function readWorkbook(bytes: Uint8Array, kind: SheetKind): XLSX.WorkBook {
  if (kind === "xlsx") {
    try {
      inspectXlsxZip(bytes); // 解压后太大 / 压缩比太夸张 / zip 坏掉 → 不交给 SheetJS
    } catch (e) {
      if (e instanceof ZipGuardError) throw new SpreadsheetError(e.code, e.detail);
      throw e;
    }
  }
  // sheetRows 多读一行：读到那一行有东西 = 下面还有（workbookLines 会丢 TOO_MANY_ROWS）
  const sheetRows = MAX_SCAN_ROWS + 1;
  let text: string | null = null;
  if (kind === "csv") {
    // type:'array' 会把没有 BOM 的 UTF-8 中文读成乱码，所以先自己转成文字
    text = decodeText(bytes);
    if (lastFilledLine(text) >= MAX_SCAN_ROWS) throw new SpreadsheetError("TOO_MANY_ROWS", "csv longer than scan limit");
  }
  try {
    // raw:true 不把 CSV 的文字乱转成日期 / 数字
    if (text != null) return XLSX.read(text, { type: "string", raw: true, sheetRows });
    return XLSX.read(bytes, { type: "array", dense: true, sheetRows });
  } catch {
    throw new SpreadsheetError("SPREADSHEET_UNREADABLE");
  }
}

export interface SheetLine {
  /** 例如 Harga!R12 */
  ref: string;
  /** 例如 1 | 16安士 PP杯 | 箱 | RM85.00 */
  text: string;
  sheet: string;
  /** 表头（只给 Claude 看懂栏位用，不是商品） */
  header: boolean;
}

/** 栏名常见的字（英文 / 马来文要是完整的字：「PACKAGING」不算 pack、「Postcode」不算 code） */
const HEADER_WORDS_LATIN =
  /\b(items?|names?|products?|descriptions?|desc|prices?|harga|units?|uom|qty|quantity|kuantiti|size|saiz|barang|nama|produk|kod|code|packing|pack|pcs|moq|spec|specs|remarks?|catatan|brand|jenama|rm)\b/i;
const HEADER_WORDS_CJK = /(货品|貨品|品名|名称|名稱|产品|產品|商品|价钱|價錢|价格|價格|售价|售價|单价|單價|单位|單位|规格|規格|包装|包裝|数量|數量|編號|编号|序号|序號|备注|備註)/;
/** 「No」「No.」「#」「Bil」（马来文的序号）整格才算 */
const HEADER_NUMBER_CELL = /^(no\.?|#|bil\.?|s\/?n)$/i;
const NUMERIC_CELL = /^[\s(RM$S¥]*[-+]?\d[\d,]*(\.\d+)?\s*\)?$/i;

function cellsOf(row: unknown[]): string[] {
  const cells = row.map((c) => String(c ?? "").replace(/\s+/g, " ").trim());
  while (cells.length && !cells[cells.length - 1]) cells.pop();
  return cells;
}

/** 这一格像不像栏名：短（最多 4 个字 / 30 个字元，括号里的单位不算）而且有栏名的字 */
export function isHeaderCell(cell: string): boolean {
  if (HEADER_NUMBER_CELL.test(cell)) return true;
  const core = cell.replace(/[(（[].*?[)）\]]/g, " ").trim();
  if (!core || core.length > 30 || core.split(/\s+/).length > 4) return false;
  return HEADER_WORDS_LATIN.test(core) || HEADER_WORDS_CJK.test(core);
}

/**
 * 这张表的表头是第几行（在前 15 行有内容的行里找）；找不到 → -1。
 * 公司名、「PRICE LIST」那种标题行常常也有一两个字像栏名，所以不是取第一个对到的：
 * 每行算有几格像栏名，取最多的（至少 2 格；一样多取上面那行）。
 */
export function findHeader(rows: string[][]): number {
  const candidates = rows.slice(0, 15);
  const isHeaderish = (cells: string[]) => {
    const filled = cells.filter(Boolean);
    return filled.length >= 2 && filled.every((c) => !NUMERIC_CELL.test(c));
  };
  let best = -1;
  let bestScore = 1;
  candidates.forEach((cells, i) => {
    if (!isHeaderish(cells)) return;
    const score = cells.filter((c) => c && isHeaderCell(c)).length;
    if (score > bestScore) {
      best = i;
      bestScore = score;
    }
  });
  if (best >= 0) return best;
  // 只有一格像栏名、或完全没有：取「全是文字」而下一行有数字的那行（数字行正上面的最像表头）
  for (let i = 0; i + 1 < candidates.length; i++) {
    if (isHeaderish(candidates[i]) && candidates[i + 1].some((c) => NUMERIC_CELL.test(c))) return i;
  }
  return -1;
}

/** 整个活页簿 → 文字行（跳过隐藏的表、空行）。商品超过 MAX_LINES 行、或表长过 MAX_SCAN_ROWS 行 → TOO_MANY_ROWS。 */
export function workbookLines(wb: XLSX.WorkBook): SheetLine[] {
  const out: SheetLine[] = [];
  wb.SheetNames.forEach((name, i) => {
    if (wb.Workbook?.Sheets?.[i]?.Hidden) return; // 隐藏的表不看
    const ws = wb.Sheets[name];
    if (!ws?.["!ref"]) return;
    const range = XLSX.utils.decode_range(ws["!ref"]);
    // sheetRows 读不完这张表 → 宁可失败也不要悄悄少了后面的商品
    const full = ws["!fullref"] ? XLSX.utils.decode_range(ws["!fullref"]) : null;
    if (range.e.r >= MAX_SCAN_ROWS || (full && full.e.r > range.e.r && full.e.r >= MAX_SCAN_ROWS)) {
      throw new SpreadsheetError("TOO_MANY_ROWS", `${name}: rows beyond ${MAX_SCAN_ROWS}`);
    }
    const start = range.s.r;
    const rows = XLSX.utils.sheet_to_json<unknown[]>(ws, {
      header: 1,
      raw: false,
      defval: "",
      blankrows: true,
      range: { s: range.s, e: { r: range.e.r, c: Math.min(range.e.c, range.s.c + MAX_SCAN_COLS - 1) } },
    });
    const filled: { rowNo: number; cells: string[] }[] = [];
    rows.forEach((r, idx) => {
      const cells = cellsOf(Array.isArray(r) ? r : []);
      if (cells.some(Boolean)) filled.push({ rowNo: start + idx + 1, cells }); // header:1 没有 __rowNum__，自己算
    });
    const headerIdx = findHeader(filled.map((f) => f.cells));
    filled.forEach((f, idx) => {
      let text = f.cells.join(" | ");
      if (text.length > MAX_LINE_CHARS) text = text.slice(0, MAX_LINE_CHARS) + "…";
      out.push({ ref: `${name.replace(/[\r\n]+/g, " ")}!R${f.rowNo}`, text, sheet: name, header: idx === headerIdx });
    });
  });
  if (out.filter((l) => !l.header).length > MAX_LINES) throw new SpreadsheetError("TOO_MANY_ROWS");
  if (out.length === 0) throw new SpreadsheetError("EMPTY_SPREADSHEET");
  return out;
}

export function renderLine(l: SheetLine): string {
  return `${l.header ? "[context] " : ""}${l.ref}: ${l.text}`;
}

export interface Chunk {
  /** 这一段开头重复的表头（别的段的） */
  context: SheetLine[];
  lines: SheetLine[];
}

export function renderChunk(c: Chunk): string {
  return [...c.context, ...c.lines].map(renderLine).join("\n");
}

export interface ChunkOptions {
  maxLines: number;
  maxChars: number;
}

export const DEFAULT_CHUNK: ChunkOptions = { maxLines: 100, maxChars: 20_000 };

/** 分段：每段最多 maxLines 行商品、maxChars 个字；每段开头补上当时那张表的表头 */
export function chunkLines(lines: SheetLine[], opts: ChunkOptions = DEFAULT_CHUNK): Chunk[] {
  const headers = new Map<string, SheetLine>();
  const chunks: Chunk[] = [];
  let cur: Chunk | null = null;
  let count = 0;
  let chars = 0;
  for (const l of lines) {
    const len = renderLine(l).length + 1;
    if (l.header) headers.set(l.sheet, l);
    const full = cur && !l.header && (count >= opts.maxLines || chars + len > opts.maxChars);
    if (!cur || full) {
      const h = headers.get(l.sheet);
      cur = { context: h && h !== l ? [h] : [], lines: [] };
      chunks.push(cur);
      count = 0;
      chars = cur.context.reduce((n, c) => n + renderLine(c).length + 1, 0);
    }
    cur.lines.push(l);
    if (!l.header) count++;
    chars += len;
  }
  return chunks.filter((c) => c.lines.some((l) => !l.header));
}

/** max_tokens 时把一段切成两半（各自补上表头） */
export function splitChunk(c: Chunk): [Chunk, Chunk] | null {
  const productIdx = c.lines.flatMap((l, i) => (l.header ? [] : [i]));
  if (productIdx.length < 2) return null;
  const mid = productIdx[Math.ceil(productIdx.length / 2)]; // 后半段的第一样商品；两半都至少有一样
  const a = c.lines.slice(0, mid);
  const b = c.lines.slice(mid);
  const header = [...c.context, ...a].filter((l) => l.header && l.sheet === b[0]?.sheet).at(-1);
  return [{ context: c.context, lines: a }, { context: header ? [header] : [], lines: b }];
}
