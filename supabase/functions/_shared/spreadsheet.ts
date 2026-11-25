// Excel / CSV → 一行一行、带行号的文字（Claude 不能直接读 Excel）。
//   Harga!R12: 1 | 16安士 PP杯 95口径 | 箱 | RM85.00
// 表头那一行标 [context]；太长就分段，每段开头重复那张表的表头。
// SheetJS 0.20.3 只放在 cdn.sheetjs.com（npm 的 xlsx 0.18.5 有安全漏洞，不能用）。

// @deno-types="https://cdn.sheetjs.com/xlsx-0.20.3/package/types/index.d.ts"
import * as XLSX from "xlsx";

export class SpreadsheetError extends Error {
  constructor(public readonly code: "SPREADSHEET_UNREADABLE" | "TOO_MANY_ROWS" | "EMPTY_SPREADSHEET") {
    super(code);
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

export const MAX_LINES = 1200;
const MAX_LINE_CHARS = 1000;

export function readWorkbook(bytes: Uint8Array, kind: SheetKind): XLSX.WorkBook {
  try {
    if (kind === "csv") {
      // type:'array' 会把没有 BOM 的 UTF-8 中文读成乱码，所以先自己转成文字；raw:true 不把文字乱转成日期 / 数字
      return XLSX.read(decodeText(bytes), { type: "string", raw: true, sheetRows: MAX_LINES + 50 });
    }
    return XLSX.read(bytes, { type: "array", dense: true, sheetRows: MAX_LINES + 50 });
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

const HEADER_WORDS =
  /(item|name|product|description|desc|price|harga|unit|unit price|qty|quantity|size|saiz|barang|nama|produk|kod|code|packing|pack|货品|品名|名称|产品|商品|价钱|价格|售价|单价|单位|规格|包装|数量|編號|编号)/i;
const NUMERIC_CELL = /^[\s(RM$S¥]*[-+]?\d[\d,]*(\.\d+)?\s*\)?$/i;

function cellsOf(row: unknown[]): string[] {
  const cells = row.map((c) => String(c ?? "").replace(/\s+/g, " ").trim());
  while (cells.length && !cells[cells.length - 1]) cells.pop();
  return cells;
}

/** 这张表的表头是第几行（在前 15 行有内容的行里找）；找不到 → -1 */
function findHeader(rows: string[][]): number {
  const candidates = rows.slice(0, 15);
  const isHeaderish = (cells: string[]) => {
    const filled = cells.filter(Boolean);
    return filled.length >= 2 && filled.every((c) => !NUMERIC_CELL.test(c));
  };
  const byWord = candidates.findIndex((c) => isHeaderish(c) && c.filter((x) => HEADER_WORDS.test(x)).length >= 1);
  if (byWord >= 0) return byWord;
  // 没有关键字：第一行「全是文字」而下一行有数字的
  for (let i = 0; i + 1 < candidates.length; i++) {
    if (isHeaderish(candidates[i]) && candidates[i + 1].some((c) => NUMERIC_CELL.test(c))) return i;
  }
  return -1;
}

/** 整个活页簿 → 文字行（跳过隐藏的表、空行）。超过 MAX_LINES 行 → TOO_MANY_ROWS。 */
export function workbookLines(wb: XLSX.WorkBook): SheetLine[] {
  const out: SheetLine[] = [];
  wb.SheetNames.forEach((name, i) => {
    if (wb.Workbook?.Sheets?.[i]?.Hidden) return; // 隐藏的表不看
    const ws = wb.Sheets[name];
    if (!ws?.["!ref"]) return;
    const start = XLSX.utils.decode_range(ws["!ref"]).s.r;
    const rows = XLSX.utils.sheet_to_json<unknown[]>(ws, { header: 1, raw: false, defval: "", blankrows: true });
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
