// Excel / CSV → 一行一行、带行号的文字（Claude 不能直接读 Excel）。
//   Harga!R12: 1 | 16安士 PP杯 95口径 | 箱 | RM85.00
// 表头那一行标 [context]；太长就分段，每段开头重复那张表的表头。
// SheetJS 0.20.3 只放在 cdn.sheetjs.com（npm 的 xlsx 0.18.5 有安全漏洞，不能用）。
// 资源预算（worker 只有 256 MB / 2 秒 CPU，被杀掉时 catch 不会跑，别人的导入也一起断掉）：
//   * xlsx 交给 SheetJS 之前先过 zipguard.ts（zip 炸弹）；
//   * CSV 不交给 SheetJS（它会照开头几个字改用 HTML / zip / DBF 的读法，也会把每一格都放进记忆体）：
//     这里照 SheetJS 的 CSV 规则自己切格，每行只留前 MAX_SCAN_COLS 栏、看得到的 MAX_LINE_CHARS 个字；
//   * xls（BIFF）交给 SheetJS 之前先数记录 / 格子（inspectXls）。
//   有内容的格子超过 MAX_CELLS → FILE_TOO_LARGE。

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
export const MAX_LINE_CHARS = 1000;
/** CSV / xls 最多几格有内容的（1200 样商品 × 50 栏）；超过 → FILE_TOO_LARGE（SheetJS 读 xls 一格大约 3.5 µs、1 KB） */
export const MAX_CELLS = 60_000;
/** xls 的 BIFF 记录最多几笔（SheetJS 每笔大约 2 µs，空白格的记录也要解析） */
export const MAX_XLS_RECORDS = 150_000;
/** xls 只有格式、没有值的格子（BLANK / MULBLANK）最多几格 */
export const MAX_XLS_BLANKS = 1_000_000;

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

// ---------------------------------------------------------------------------
// CSV：照 SheetJS 0.20.3 的 dsv_to_sheet_str（raw:true）切格，但不交给它
// ---------------------------------------------------------------------------

const GUESS_SEPS: Record<number, string> = { 0x2c: ",", 0x09: "\t", 0x3b: ";", 0x7c: "|" };
const SEP_WEIGHT: Record<number, number> = { 0x2c: 3, 0x09: 2, 0x3b: 1, 0x7c: 0 };

/** 跟 SheetJS 的 guess_sep 一样：引号外面哪个分隔符最多（一样多：, > tab > ; > |） */
function guessSep(str: string): number {
  const cnt = new Map<number, number>();
  let instr = false;
  for (let i = 0; i < str.length; i++) {
    const c = str.charCodeAt(i);
    if (c === 0x22) instr = !instr;
    else if (!instr && c in GUESS_SEPS) cnt.set(c, (cnt.get(c) ?? 0) + 1);
  }
  let best = 0x2c;
  let bestN = -1;
  for (const [c, n] of cnt) {
    if (n > bestN || (n === bestN && SEP_WEIGHT[c] > SEP_WEIGHT[best])) [best, bestN] = [c, n];
  }
  return best;
}

/**
 * CSV 文字 → 活页簿（一张 Sheet1，dense）。切格的规则跟 SheetJS 一样（sep= 第一行、猜分隔符、
 * 格子开头是引号才算引号里面、\r\n / \r / \n 换行），但：每行只留前 MAX_SCAN_COLS 栏，
 * 前面的格子已经超过 MAX_LINE_CHARS 个字（workbookLines 也会切掉）就不留；空白合并、只放看得到的字；
 * 有内容的格子超过 MAX_CELLS → FILE_TOO_LARGE。读到第 sheetRows 行就停。
 */
export function csvWorkbook(text: string, sheetRows = MAX_SCAN_ROWS + 1): XLSX.WorkBook {
  let str = text;
  let sepcc: number;
  if (str.slice(0, 4) === "sep=") {
    if (str.charCodeAt(5) === 13 && str.charCodeAt(6) === 10) {
      sepcc = str.charCodeAt(4);
      str = str.slice(7);
    } else if (str.charCodeAt(5) === 13 || str.charCodeAt(5) === 10) {
      sepcc = str.charCodeAt(4);
      str = str.slice(6);
    } else sepcc = guessSep(str.slice(0, 1024));
  } else sepcc = guessSep(str.slice(0, 1024));

  const data: XLSX.CellObject[][] = [];
  let R = 0, C = 0, maxR = 0, maxC = 0;
  let cells = 0;
  let rowLen = 0; // 这一行留下的字数
  let start = 0, end = 0, instr = false, cc = 0;
  let startcc = str.charCodeAt(0);
  const finish = (): boolean => {
    // 后面的栏、看不到的字（workbookLines 会切在 MAX_LINE_CHARS）不用留
    if (C < MAX_SCAN_COLS && rowLen + 3 * C <= MAX_LINE_CHARS) {
      let s = str.slice(start, end);
      if (s.slice(-1) === "\r") s = s.slice(0, -1);
      if (s.charAt(0) === '"' && s.charAt(s.length - 1) === '"') s = s.slice(1, -1).replace(/""/g, '"');
      const v = s.replace(/\s+/g, " ").trim().slice(0, MAX_LINE_CHARS + 1);
      if (v) {
        if (++cells > MAX_CELLS) throw new SpreadsheetError("FILE_TOO_LARGE", `csv over ${MAX_CELLS} cells`);
        (data[R] ??= [])[C] = { t: "s", v, w: v };
        rowLen += v.length;
      }
    }
    start = end + 1;
    startcc = str.charCodeAt(start);
    if (maxC < C) maxC = Math.min(C, MAX_SCAN_COLS - 1);
    if (maxR < R) maxR = R;
    if (cc === sepcc) ++C;
    else {
      C = 0;
      rowLen = 0;
      if (sheetRows <= ++R) return true;
    }
    return false;
  };
  for (; end < str.length; ++end) {
    cc = str.charCodeAt(end);
    if (cc === 0x22) {
      if (startcc === 0x22) instr = !instr;
    } else if (cc === 0x0d) {
      if (instr) continue;
      if (str.charCodeAt(end + 1) === 0x0a) ++end;
      if (finish()) break;
    } else if (cc === sepcc || cc === 0x0a) {
      if (!instr && finish()) break;
    }
  }
  if (end - start > 0) finish();
  const ws: XLSX.WorkSheet = {
    "!data": data,
    "!ref": XLSX.utils.encode_range({ s: { r: 0, c: 0 }, e: { r: maxR, c: maxC } }),
  };
  return { SheetNames: ["Sheet1"], Sheets: { Sheet1: ws } };
}

// ---------------------------------------------------------------------------
// xls（OLE2 / BIFF）：先数记录和格子
// ---------------------------------------------------------------------------

type Cfb = ReturnType<typeof XLSX.CFB.read>;
/** SheetJS 有 export 但 types 没写：解析已经读好的 OLE2（不用再读一次） */
const parseXlsCfb = (XLSX as unknown as { parse_xlscfb: (cfb: Cfb, o: XLSX.ParsingOptions) => XLSX.WorkBook })
  .parse_xlscfb;

/** 有值的格子：NUMBER、LABEL、BOOLERR、LABELSST、RK、RSTRING、FORMULA（BIFF2-8） */
const XLS_VALUE_RECORDS = new Set([
  0x0002,
  0x0003,
  0x0004,
  0x0005,
  0x0006,
  0x0203,
  0x0204,
  0x0205,
  0x00fd,
  0x027e,
  0x00d6,
  0x0206,
  0x0406,
]);

export interface XlsStats {
  records: number;
  cells: number;
  blanks: number;
  sst: number;
}

/** 数 Workbook 资料流里的 BIFF 记录（几毫秒）；超过预算 → FILE_TOO_LARGE；没有资料流 → SPREADSHEET_UNREADABLE */
export function inspectXls(cfb: Cfb): XlsStats {
  const entry = XLSX.CFB.find(cfb, "/Workbook") ?? XLSX.CFB.find(cfb, "/Book");
  const c = entry?.content as ArrayLike<number> | undefined;
  if (!c || c.length < 4) throw new SpreadsheetError("SPREADSHEET_UNREADABLE", "no workbook stream");
  const st: XlsStats = { records: 0, cells: 0, blanks: 0, sst: 0 };
  for (let i = 0; i + 4 <= c.length;) {
    const type = c[i] | (c[i + 1] << 8);
    const len = c[i + 2] | (c[i + 3] << 8);
    i += 4;
    if (++st.records > MAX_XLS_RECORDS) {
      throw new SpreadsheetError("FILE_TOO_LARGE", `xls over ${MAX_XLS_RECORDS} records`);
    }
    if (XLS_VALUE_RECORDS.has(type)) st.cells++;
    else if (type === 0x00bd) st.cells += Math.max(0, Math.floor((len - 6) / 6)); // MULRK
    else if (type === 0x0201 || type === 0x0001) st.blanks++; // BLANK
    else if (type === 0x00be) st.blanks += Math.max(0, Math.floor((len - 6) / 2)); // MULBLANK
    else if (type === 0x00fc && len >= 8) { // SST：cstTotal、cstUnique
      st.sst = (c[i + 4] | (c[i + 5] << 8) | (c[i + 6] << 16)) + c[i + 7] * 0x1000000;
    }
    i += len;
  }
  if (st.cells > MAX_CELLS || st.sst > MAX_CELLS) {
    throw new SpreadsheetError("FILE_TOO_LARGE", `xls over ${MAX_CELLS} cells (${st.cells} cells, ${st.sst} strings)`);
  }
  if (st.blanks > MAX_XLS_BLANKS) {
    throw new SpreadsheetError("FILE_TOO_LARGE", `xls over ${MAX_XLS_BLANKS} blank cells`);
  }
  return st;
}

// ---------------------------------------------------------------------------
// 读活页簿
// ---------------------------------------------------------------------------

/** readWorkbook 读的活页簿 → 「这张表在 MAX_SCAN_ROWS 以下还有没有值」（要重读那张表，不限行数） */
const BEYOND = new WeakMap<XLSX.WorkBook, (sheet: string) => boolean>();

const cellHasValue = (c: XLSX.CellObject | undefined): boolean =>
  !!c && c.t !== "z" && c.v != null && String(c.w ?? c.v).trim() !== "";

/** 这张表第 fromRow 行（0 起算）以下有没有值（dense 或一般的都可以） */
export function hasValuesFrom(ws: XLSX.WorkSheet | undefined, fromRow: number): boolean {
  if (!ws) return false;
  const dense = ws["!data"] as (XLSX.CellObject[] | undefined)[] | undefined;
  if (dense) {
    for (let r = fromRow; r < dense.length; r++) if (dense[r]?.some(cellHasValue)) return true;
    return false;
  }
  for (const k of Object.keys(ws)) {
    if (k[0] !== "!" && XLSX.utils.decode_cell(k).r >= fromRow && cellHasValue(ws[k] as XLSX.CellObject)) return true;
  }
  return false;
}

export function readWorkbook(bytes: Uint8Array, kind: SheetKind): XLSX.WorkBook {
  // sheetRows 多读一行：读到那一行有东西 = 下面还有（workbookLines 会丢 TOO_MANY_ROWS）
  const sheetRows = MAX_SCAN_ROWS + 1;
  if (kind === "csv") {
    // type:'array' 会把没有 BOM 的 UTF-8 中文读成乱码，所以先自己转成文字
    const text = decodeText(bytes);
    if (lastFilledLine(text) >= MAX_SCAN_ROWS) {
      throw new SpreadsheetError("TOO_MANY_ROWS", "csv longer than scan limit");
    }
    return csvWorkbook(text, sheetRows);
  }
  if (kind === "xlsx") {
    try {
      inspectXlsxZip(bytes); // 解压后太大 / 压缩比太夸张 / zip 坏掉 / 拖慢检查 → 不交给 SheetJS
    } catch (e) {
      if (e instanceof ZipGuardError) throw new SpreadsheetError(e.code, e.detail);
      throw e;
    }
    let wb: XLSX.WorkBook;
    try {
      wb = XLSX.read(bytes, { type: "array", dense: true, sheetRows });
    } catch {
      throw new SpreadsheetError("SPREADSHEET_UNREADABLE");
    }
    // 只重读那一张表；zipguard 已经确定整份 XML 不超过 16 MB
    BEYOND.set(wb, (sheet) => {
      try {
        const full = XLSX.read(bytes, { type: "array", dense: true, sheets: [sheet] });
        return hasValuesFrom(full.Sheets[sheet], MAX_SCAN_ROWS);
      } catch {
        return true; // 读不了就当作有（宁可失败）
      }
    });
    return wb;
  }
  let cfb: Cfb;
  try {
    cfb = XLSX.CFB.read(bytes, { type: "array" });
  } catch {
    throw new SpreadsheetError("SPREADSHEET_UNREADABLE");
  }
  inspectXls(cfb); // 格子 / 记录太多 → 不交给 SheetJS
  let wb: XLSX.WorkBook;
  try {
    wb = parseXlsCfb(cfb, { type: "array", dense: true, sheetRows });
  } catch {
    throw new SpreadsheetError("SPREADSHEET_UNREADABLE");
  }
  // inspectXls 已经限制了整份的格子数，重读全部也有上限
  BEYOND.set(wb, (sheet) => {
    try {
      const full = parseXlsCfb(XLSX.CFB.read(bytes, { type: "array" }), { type: "array", dense: true });
      return hasValuesFrom(full.Sheets[sheet], MAX_SCAN_ROWS);
    } catch {
      return true;
    }
  });
  return wb;
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
const HEADER_WORDS_CJK =
  /(货品|貨品|品名|名称|名稱|产品|產品|商品|价钱|價錢|价格|價格|售价|售價|单价|單價|单位|單位|规格|規格|包装|包裝|数量|數量|編號|编号|序号|序號|备注|備註)/;
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

/** 整个活页簿 → 文字行（跳过隐藏的表、空行）。商品超过 MAX_LINES 行、或第 MAX_SCAN_ROWS 行以下还有值 → TOO_MANY_ROWS。 */
export function workbookLines(wb: XLSX.WorkBook): SheetLine[] {
  const out: SheetLine[] = [];
  wb.SheetNames.forEach((name, i) => {
    if (wb.Workbook?.Sheets?.[i]?.Hidden) return; // 隐藏的表不看
    const ws = wb.Sheets[name];
    if (!ws?.["!ref"]) return;
    const range = XLSX.utils.decode_range(ws["!ref"]);
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
    // 「下面还有」看的是有值的格子，不是表自己写的范围（Excel 的 <dimension> / DIMENSIONS 连只有框线、
    // 底色、内容清掉的格子也算进去，几十样商品的表也可能写到第一万行）：
    //   * sheetRows 多读的那一行（第 MAX_SCAN_ROWS + 1 行）有内容 → 下面还有；
    //   * 表写的范围比读到的还长（!fullref）→ 重读那张表、确定 MAX_SCAN_ROWS 以下真的有值；
    //     不是 readWorkbook 读的（不能重读）→ 宁可失败也不要悄悄少了后面的商品
    const full = ws["!fullref"] ? XLSX.utils.decode_range(ws["!fullref"]) : null;
    const beyond = BEYOND.get(wb);
    if (
      filled.some((f) => f.rowNo > MAX_SCAN_ROWS) ||
      (full && full.e.r > range.e.r && full.e.r >= MAX_SCAN_ROWS && (!beyond || beyond(name)))
    ) {
      throw new SpreadsheetError("TOO_MANY_ROWS", `${name}: rows beyond ${MAX_SCAN_ROWS}`);
    }
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

/** 一段 50 行：Opus 读 100-150 行可能超过 150 秒（verifications.json），一段要在时间预算里读完；输出也远低于 max_tokens */
export const DEFAULT_CHUNK: ChunkOptions = { maxLines: 50, maxChars: 10_000 };

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
