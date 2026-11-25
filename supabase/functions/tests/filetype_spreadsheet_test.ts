import { assert, assertEquals, assertFalse, assertStringIncludes, assertThrows } from "@std/assert";
// @deno-types="https://cdn.sheetjs.com/xlsx-0.20.3/package/types/index.d.ts"
import * as XLSX from "xlsx";
import { isImage, isSpreadsheet, sniffFileType } from "../_shared/filetype.ts";
import {
  chunkLines,
  csvWorkbook,
  decodeText,
  findHeader,
  isHeaderCell,
  lastFilledLine,
  MAX_CELLS,
  MAX_LINE_CHARS,
  MAX_LINES,
  MAX_SCAN_COLS,
  MAX_SCAN_ROWS,
  MAX_XLS_RECORDS,
  readWorkbook,
  renderChunk,
  type SheetLine,
  splitChunk,
  SpreadsheetError,
  workbookLines,
} from "../_shared/spreadsheet.ts";
import { makeWorkbook, workbookParts, xlsWithRecords, zipFiles } from "./_sheets.ts";

const bytes = (...xs: number[]) => new Uint8Array(xs);
const pad = (head: Uint8Array, n = 64) => {
  const b = new Uint8Array(Math.max(n, head.length));
  b.set(head);
  return b;
};
const ascii = (s: string) => new TextEncoder().encode(s);
const hex = (h: string) => Uint8Array.from(h.match(/../g)!.map((x) => parseInt(x, 16)));

Deno.test("魔术字节：图片、PDF、HEIC、zip、OLE、文字", () => {
  assertEquals(sniffFileType(pad(bytes(0xff, 0xd8, 0xff, 0xe0))), "jpeg");
  assertEquals(sniffFileType(pad(bytes(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a))), "png");
  assertEquals(sniffFileType(pad(ascii("RIFF\x10\x00\x00\x00WEBPVP8 "))), "webp");
  assertEquals(sniffFileType(pad(ascii("GIF89a"))), "gif");
  assertEquals(sniffFileType(pad(ascii("%PDF-1.7\n"))), "pdf");
  assertEquals(sniffFileType(pad(ascii("\r\n%PDF-1.4"))), "pdf"); // 前面多一点东西也认得
  assertEquals(sniffFileType(pad(ascii("\x00\x00\x00\x18ftypheic\x00\x00\x00\x00"))), "heic");
  assertEquals(sniffFileType(pad(ascii("\x00\x00\x00\x18ftypmif1\x00\x00\x00\x00"))), "heic");
  assertEquals(sniffFileType(pad(ascii("\x00\x00\x00\x18ftypavif\x00\x00\x00\x00"))), "unknown");
  assertEquals(sniffFileType(pad(bytes(0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1))), "xls");
  assertEquals(sniffFileType(pad(bytes(0x50, 0x4b, 0x03, 0x04, 1, 2, 3))), "unknown"); // 普通 zip / docx
  assertEquals(sniffFileType(ascii("Item,Unit,Price\n16oz cup,ctn,85.00\n")), "csv");
  assertEquals(sniffFileType(hex("3136b0b2cabf205050b1ad2ccfe42c3835")), "csv"); // gb18030
  assertEquals(sniffFileType(bytes(0xff, 0xfe, 0x41, 0x00)), "csv"); // UTF-16 LE
  assertEquals(sniffFileType(bytes(0, 1, 2, 3, 4, 5, 6, 7)), "unknown");
  assertEquals(sniffFileType(new Uint8Array(0)), "unknown");
  assert(isImage("gif") && !isImage("pdf"));
  assert(isSpreadsheet("csv") && !isSpreadsheet("heic"));
});

Deno.test("魔术字节：真的 xlsx / xls", () => {
  assertEquals(sniffFileType(makeWorkbook("xlsx")), "xlsx");
  assertEquals(sniffFileType(makeWorkbook("biff8")), "xls");
});

Deno.test("CSV 编码：UTF-8（有 / 没有 BOM）、gb18030、UTF-16", () => {
  assertEquals(decodeText(ascii("塑料盒,1")), "塑料盒,1");
  assertEquals(decodeText(new Uint8Array([0xef, 0xbb, 0xbf, ...ascii("盒")])), "盒");
  assertEquals(decodeText(hex("cbdcc1cfbad02c31")), "塑料盒,1"); // gb18030 的「塑料盒,1」
  assertEquals(decodeText(new Uint8Array([0xff, 0xfe, 0xd2, 0x76, 0x2c, 0x00])), "盒,");
});

Deno.test("gb18030 的 CSV → 带行号的文字", () => {
  const csv = new Uint8Array([
    ...ascii("Item,Unit,Price\n"),
    ...hex("3136b0b2cabf205050b1ad2ccfe42c3835"), // 16安士 PP杯,箱,85
    ...ascii("\n0123 lid,ctn,1/2\n"),
  ]);
  const lines = workbookLines(readWorkbook(csv, "csv"));
  assertEquals(lines.map((l) => [l.ref, l.text, l.header]), [
    ["Sheet1!R1", "Item | Unit | Price", true],
    ["Sheet1!R2", "16安士 PP杯 | 箱 | 85", false],
    ["Sheet1!R3", "0123 lid | ctn | 1/2", false], // raw：不会变成日期、不会去掉 0
  ]);
});

Deno.test("xlsx（测试里做的）→ 行号、格式化的价钱、表头 [context]、隐藏的表不看", () => {
  for (const kind of ["xlsx", "biff8"] as const) {
    const lines = workbookLines(readWorkbook(makeWorkbook(kind), kind === "xlsx" ? "xlsx" : "xls"));
    assertEquals(lines.map((l) => l.ref), ["Harga!R1", "Harga!R3", "Harga!R4", "Harga!R5", "Harga!R6"]);
    assertEquals(lines[1].header, true);
    assertEquals(lines[2].text, "1 | 16安士 PP杯 95口径 | 箱 | RM85.50 | 5 ctn");
    assert(!lines.some((l) => l.text.includes("secret")), "hidden sheet must be skipped");
    const [chunk] = chunkLines(lines);
    assertEquals(
      renderChunk(chunk),
      [
        "Harga!R1: 新山包装批发 JB Packaging Supply",
        "[context] Harga!R3: No | 货品 Item | Unit | Harga (RM) | MOQ",
        "Harga!R4: 1 | 16安士 PP杯 95口径 | 箱 | RM85.50 | 5 ctn",
        "Harga!R5: 2 | 95 平盖 | ctn | 40",
        "Harga!R6: 3 | Straw 6mm / 8mm | pkt | RM3.50 / RM4.00",
      ].join("\n"),
    );
  }
});

Deno.test("看不懂的 Excel / 空的 → SpreadsheetError", () => {
  assertThrows(
    () => readWorkbook(bytes(0x50, 0x4b, 3, 4, 9, 9, 9), "xlsx"),
    SpreadsheetError,
    "SPREADSHEET_UNREADABLE",
  );
  assertThrows(() => workbookLines(readWorkbook(ascii("\n\n"), "csv")), SpreadsheetError, "EMPTY_SPREADSHEET");
});

Deno.test("太多行 → TOO_MANY_ROWS", () => {
  const csv = "Item,Price\n" + Array.from({ length: MAX_LINES + 5 }, (_, i) => `item ${i},${i + 1}`).join("\n");
  assertThrows(() => workbookLines(readWorkbook(ascii(csv), "csv")), SpreadsheetError, "TOO_MANY_ROWS");
  // 刚好 MAX_LINES 样商品可以
  const ok = "Item,Price\n" + Array.from({ length: MAX_LINES }, (_, i) => `item ${i},${i + 1}`).join("\n");
  assertEquals(workbookLines(readWorkbook(ascii(ok), "csv")).filter((l) => !l.header).length, MAX_LINES);
});

/** 1066 样商品放在第 1 到 1600 行，每 3 行有 1 行空白（排版用的） */
function spacedRows(): unknown[][] {
  const rows: unknown[][] = [["Item", "Price"]];
  let n = 0;
  while (rows.length < 1600) rows.push(rows.length % 3 === 2 ? [] : [`item ${++n}`, `${n}.50`]);
  return rows;
}

function xlsxOf(sheet: XLSX.WorkSheet, bookType: "xlsx" | "biff8" = "xlsx"): Uint8Array {
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, sheet, "S");
  return new Uint8Array(XLSX.write(wb, { type: "array", bookType }) as ArrayBuffer);
}

Deno.test("中间有空行、超过第 1250 行的表：全部商品都读到（以前会在第 1250 行悄悄切掉）", () => {
  const rows = spacedRows();
  const products = rows.filter((r) => r.length && r[0] !== "Item").length;
  assertEquals(products, 1066);
  const csv = ascii(rows.map((r) => r.join(",")).join("\n"));
  for (
    const [kind, bytes] of [
      ["csv", csv],
      ["xlsx", xlsxOf(XLSX.utils.aoa_to_sheet(rows))],
      ["xls", xlsxOf(XLSX.utils.aoa_to_sheet(rows), "biff8")],
    ] as const
  ) {
    const lines = workbookLines(readWorkbook(bytes, kind));
    assertEquals(lines.filter((l) => !l.header).length, products, kind);
    assertEquals(lines.at(-1)!.ref.replace(/^.*!/, ""), "R1600", kind);
  }
});

Deno.test("表从很下面才开始（第 2000 行）也读得到", () => {
  const ws = XLSX.utils.aoa_to_sheet([]);
  XLSX.utils.sheet_add_aoa(ws, [["Item", "Price"], ...Array.from({ length: 300 }, (_, i) => [`item ${i}`, i + 1])], {
    origin: "B2000",
  });
  const lines = workbookLines(readWorkbook(xlsxOf(ws), "xlsx"));
  assertEquals(lines.length, 301);
  assertEquals([lines[0].ref, lines[0].header, lines.at(-1)!.ref], ["S!R2000", true, "S!R2300"]);
});

Deno.test("表长过 MAX_SCAN_ROWS（就算商品不到 1200 样）→ TOO_MANY_ROWS，不会悄悄少掉后面的", () => {
  // CSV：1000 样商品，每样中间隔 4 行空白 → 5000 行
  const csv = "Item,Price\n" + Array.from({ length: 1000 }, (_, i) => `item ${i},${i + 1}\n,,\n\n\n\n`).join("");
  assert(lastFilledLine(csv) >= MAX_SCAN_ROWS);
  assertThrows(() => workbookLines(readWorkbook(ascii(csv), "csv")), SpreadsheetError, "TOO_MANY_ROWS");
  // xlsx：前面 10 样，第 5000 行还有一样（中间全空）
  const ws = XLSX.utils.aoa_to_sheet(Array.from({ length: 10 }, (_, i) => [`item ${i}`, i + 1]));
  XLSX.utils.sheet_add_aoa(ws, [["late item", 9]], { origin: "A5000" });
  for (const bookType of ["xlsx", "biff8"] as const) {
    assertThrows(
      () => workbookLines(readWorkbook(xlsxOf(ws, bookType), bookType === "xlsx" ? "xlsx" : "xls")),
      SpreadsheetError,
      "TOO_MANY_ROWS",
    );
  }
  // 刚好最后一行在 MAX_SCAN_ROWS 以内：可以
  const edge = XLSX.utils.aoa_to_sheet([["item", 1]]);
  XLSX.utils.sheet_add_aoa(edge, [["last", 2]], { origin: `A${MAX_SCAN_ROWS}` });
  assertEquals(workbookLines(readWorkbook(xlsxOf(edge), "xlsx")).map((l) => l.ref), ["S!R1", `S!R${MAX_SCAN_ROWS}`]);
});

Deno.test("lastFilledLine：空白、只有逗号的行不算；\r\n / \r 都算换行", () => {
  assertEquals(lastFilledLine(""), -1);
  assertEquals(lastFilledLine("a\n\n,,\n  \n"), 0);
  assertEquals(lastFilledLine("a\r\nb\rc"), 2);
  assertEquals(lastFilledLine(",,\n;\t\nx,\n"), 2);
});

Deno.test("很宽的行（一格放在第 5000 栏）：只看前面 256 栏，不会每行都变成几千栏", () => {
  const csv = ascii("Item,Price" + ",".repeat(5000) + "far away\nitem 1,1\nitem 2,2\n");
  const lines = workbookLines(readWorkbook(csv, "csv"));
  assertEquals(lines.map((l) => l.text), ["Item | Price", "item 1 | 1", "item 2 | 2"]);
});

Deno.test("表头：公司名 / PRICE LIST 那种标题行不会被当成表头；后面的段落重复真正的表头", () => {
  const csv = [
    "JB PACKAGING SUPPLY SDN BHD,Tel: 07-3345678",
    "PRICE LIST,Effective Nov 2026",
    "No,Item,Pack (pcs/ctn),Price (RM),MOQ",
    ...Array.from({ length: 150 }, (_, i) => `${i + 1},Item ${i + 1},1000,${(i + 1) * 0.5 + 0.25},5`),
  ].join("\n");
  const lines = workbookLines(readWorkbook(ascii(csv), "csv"));
  assertEquals(lines.filter((l) => l.header).map((l) => l.ref), ["Sheet1!R3"]);
  const chunks = chunkLines(lines); // 一段 50 行（标题那两行也算）：50 + 50 + 50 + 2
  assertEquals(chunks.length, 4);
  for (const c of chunks.slice(1)) {
    assert(renderChunk(c).startsWith("[context] Sheet1!R3: No | Item | Pack (pcs/ctn) | Price (RM) | MOQ\n"));
  }

  assertFalse(isHeaderCell("JB PACKAGING SUPPLY SDN BHD"));
  assertFalse(isHeaderCell("Tel: 07-3345678"));
  assertFalse(isHeaderCell("No. 12, Jalan Perindustrian, 81100 Johor Bahru (Postcode)"));
  assert(isHeaderCell("PRICE LIST")); // 只有一格：分数不够当表头
  for (
    const c of [
      "No",
      "No.",
      "#",
      "Bil",
      "Item",
      "货品 Item",
      "Pack (pcs/ctn)",
      "Harga (RM)",
      "Unit Price",
      "MOQ",
      "单价",
    ]
  ) {
    assert(isHeaderCell(c), c);
  }
  // 只有一格像栏名：退回「全是文字而下一行有数字」的那行
  assertEquals(findHeader([["Company", "Tel"], ["Description", "Amount"], ["cup", "85"]]), 1);
  assertEquals(findHeader([["Description", "Price"], ["cup", "85"]]), 0);
  assertEquals(findHeader([["cup", "85"]]), -1);
});

function lines(n: number, sheets = 1): SheetLine[] {
  const out: SheetLine[] = [];
  for (let s = 0; s < sheets; s++) {
    const sheet = `S${s + 1}`;
    out.push({ ref: `${sheet}!R1`, text: "Item | Price", sheet, header: true });
    for (let i = 0; i < n; i++) out.push({ ref: `${sheet}!R${i + 2}`, text: `item ${i} | ${i}`, sheet, header: false });
  }
  return out;
}

Deno.test("分段：每段重复表头；跨表时换成那张表的表头；字数上限", () => {
  const chunks = chunkLines(lines(250), { maxLines: 100, maxChars: 100_000 });
  assertEquals(chunks.length, 3);
  assertEquals(chunks.map((c) => c.lines.filter((l) => !l.header).length), [100, 100, 50]);
  assertEquals(chunks[0].context, []);
  assertEquals(chunks[0].lines[0].header, true);
  for (const c of chunks.slice(1)) {
    assertEquals(c.context.map((l) => l.ref), ["S1!R1"]);
    assert(renderChunk(c).startsWith("[context] S1!R1: Item | Price\n"));
  }

  const two = chunkLines(lines(3, 2), { maxLines: 4, maxChars: 100_000 });
  assertEquals(two.length, 2);
  assertStringIncludes(renderChunk(two[0]), "[context] S2!R1");
  assertEquals(two[1].context.map((l) => l.ref), ["S2!R1"]);

  const small = chunkLines(lines(10), { maxLines: 1000, maxChars: 120 });
  assert(small.length > 1);
  for (const c of small) assert(renderChunk(c).length <= 120 + 40, String(renderChunk(c).length));
});

Deno.test("切成两半：两半都有商品，后半补上表头", () => {
  const [c] = chunkLines(lines(5), { maxLines: 100, maxChars: 100_000 });
  const halves = splitChunk(c)!;
  const products = (x: typeof c) => x.lines.filter((l) => !l.header).length;
  assertEquals([products(halves[0]), products(halves[1])], [3, 2]);
  assertEquals(halves[1].context.map((l) => l.ref), ["S1!R1"]);
  const [one] = chunkLines(lines(1), { maxLines: 100, maxChars: 100_000 });
  assertEquals(splitChunk(one), null);
});

const MB = 1024 * 1024;

function code(f: () => unknown): string {
  try {
    f();
    return "ok";
  } catch (e) {
    assert(e instanceof SpreadsheetError, String(e));
    return e.code;
  }
}

Deno.test("CSV：自己切格的结果跟 SheetJS（raw）一样（引号、换行、sep=、各种分隔符）", () => {
  const samples = [
    'Item,Price\n"16oz cup, PP",85\n"say ""hi""",1\n',
    'Item,Note\r\n"line 1\nline 2",x\r\ncup,"a,b,c"\r\n',
    "sep=;\nItem;Price\ncup;8,50\n",
    "Item\tPrice\tUnit\ncup\t1\tctn\n",
    "a|b|c\nd|e|f",
    'Item,Price\n a"b ,  1 \n,,\n   ,  \nlast,"unterminated\nnext,2\n',
    "Item,Price\rcup,1\rlid,2",
    "货品,价钱,备注\n16安士 PP杯,RM85.00,\n平盖,40,缺货\n",
    'x,"",y\n"",z',
  ];
  for (const csv of samples) {
    const ours = workbookLines(csvWorkbook(csv)).map((l) => [l.ref, l.text, l.header]);
    const sheetjs = workbookLines(XLSX.read(csv, { type: "string", raw: true })).map((l) => [l.ref, l.text, l.header]);
    assertEquals(ours, sheetjs, JSON.stringify(csv));
  }
});

Deno.test("CSV：开头像 HTML / SYLK / zip / 换行的文字不会被 SheetJS 换成别的读法（没有预算的路）", () => {
  const cases: [string, string[]][] = [
    ["<b>Item</b>,Price\ncup,1\n", ["<b>Item</b> | Price", "cup | 1"]],
    ["ID;PWXL\nItem,Price\ncup,1\n", ["ID;PWXL", "Item | Price", "cup | 1"]],
    ["PK\x01\x02,Price\ncup,1\n", ["PK\x01\x02 | Price", "cup | 1"]],
    ["\n货品,价钱\n杯,1\n", ["货品 | 价钱", "杯 | 1"]], // 以前：开头是换行 → 当成 binary 字串，中文变乱码
  ];
  for (const [csv, want] of cases) {
    assertEquals(workbookLines(readWorkbook(ascii(csv), "csv")).map((l) => l.text), want, JSON.stringify(csv));
  }
});

Deno.test("很宽的 CSV（10 MB、262 行、每行 2 万格）→ 很快就停（不会把几百万格放进记忆体）", () => {
  const wide = "x,".repeat(20_000);
  const big = ascii("name,price\n" + Array.from({ length: 262 }, () => wide).join("\n"));
  assert(big.length > 10_000_000, String(big.length));
  assertEquals(sniffFileType(big), "csv");
  const before = Deno.memoryUsage().heapUsed;
  let t = performance.now();
  // 每行只留看得到的 250 格，262 行合计超过 MAX_CELLS → FILE_TOO_LARGE（以前：SheetJS 6.6 秒、635 MB）
  assertEquals(code(() => workbookLines(readWorkbook(big, "csv"))), "FILE_TOO_LARGE");
  assert(performance.now() - t < 1500, `${performance.now() - t} ms`);
  assert(Deno.memoryUsage().heapUsed - before < 64 * MB, "csv must not be materialized");
  // 少一点行就读得到，每行最多 MAX_SCAN_COLS 栏、MAX_LINE_CHARS 个字
  const ok = ascii("name,price\n" + Array.from({ length: 200 }, (_, i) => `item ${i},${wide}`).join("\n"));
  t = performance.now();
  const lines = workbookLines(readWorkbook(ok, "csv"));
  assert(performance.now() - t < 1500, `${performance.now() - t} ms`);
  assertEquals(lines.length, 201);
  assert(lines.every((l) => l.text.length <= MAX_LINE_CHARS + 1));
  assert(lines[1].text.startsWith("item 0 | x | x | "), lines[1].text);
  // 栏数：一格一个字也最多 MAX_SCAN_COLS 栏
  const ws = csvWorkbook("a" + ",b".repeat(1000)).Sheets.Sheet1;
  assertEquals(XLSX.utils.decode_range(ws["!ref"]!).e.c, MAX_SCAN_COLS - 1);
});

Deno.test("CSV：有内容的格子超过 MAX_CELLS → FILE_TOO_LARGE（就算行数、商品数都没超过）", () => {
  const row = Array.from({ length: 60 }, (_, i) => `v${i}`).join(",");
  const csv = "Item,Price\n" + Array.from({ length: 1100 }, () => row).join("\n");
  assert(1100 * 60 > MAX_CELLS);
  assertEquals(code(() => readWorkbook(ascii(csv), "csv")), "FILE_TOO_LARGE");
  const fewer = "Item,Price\n" + Array.from({ length: 900 }, () => row).join("\n");
  assertEquals(workbookLines(readWorkbook(ascii(fewer), "csv")).length, 901);
});

function xlsOf(aoa: unknown[][]): Uint8Array {
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(aoa), "S");
  return new Uint8Array(XLSX.write(wb, { type: "array", bookType: "biff8" }) as ArrayBuffer);
}

Deno.test("xls：格子太多（1100 行 × 64 栏数字）→ 先数 BIFF 记录就 FILE_TOO_LARGE，不交给 SheetJS", () => {
  const dense = xlsOf(Array.from({ length: 1100 }, (_, r) => Array.from({ length: 64 }, (_, c) => r * 100 + c + 0.5)));
  assertEquals(sniffFileType(dense), "xls");
  const t = performance.now();
  assertEquals(code(() => readWorkbook(dense, "xls")), "FILE_TOO_LARGE");
  assert(performance.now() - t < 500, `${performance.now() - t} ms`);
  // 1100 行 × 40 栏（44000 格）读得到
  const ok = xlsOf(Array.from({ length: 1100 }, (_, r) => ["item " + r, ...Array.from({ length: 39 }, (_, c) => c)]));
  assertEquals(workbookLines(readWorkbook(ok, "xls")).length, 1100);
});

Deno.test("xls：只有格式的空白格、很多笔小记录 → FILE_TOO_LARGE（SheetJS 每笔都要解析）", () => {
  // BLANK：row、col、ixfe
  const blanks = xlsWithRecords(MAX_XLS_RECORDS + 10, (i) => [0x0201, [i & 0xff, (i >> 8) & 0xff, 3, 0, 15, 0]]);
  const t = performance.now();
  assertEquals(code(() => readWorkbook(blanks, "xls")), "FILE_TOO_LARGE");
  assert(performance.now() - t < 500, `${performance.now() - t} ms`);
  // MULBLANK：一笔 250 格
  const mul = xlsWithRecords(5000, (i) => [0x00be, [i & 0xff, i >> 8, 0, 0, ...new Array(500).fill(0), 249, 0]]);
  assertEquals(code(() => readWorkbook(mul, "xls")), "FILE_TOO_LARGE");
  // 少量的空白格没关系
  const few = xlsWithRecords(100, (i) => [0x0201, [2 + i, 0, 5, 0, 15, 0]]);
  assertEquals(workbookLines(readWorkbook(few, "xls")).map((l) => l.text), ["Item | Price", "cup | 1"]);
  // 不是 xls 的 OLE2（没有 Workbook 资料流）
  const ole = XLSX.CFB.utils.cfb_new();
  XLSX.CFB.utils.cfb_add(ole, "/WordDocument", new Uint8Array(100));
  const doc = new Uint8Array(XLSX.CFB.write(ole, { type: "array" }) as ArrayLike<number>);
  assertEquals(code(() => readWorkbook(doc, "xls")), "SPREADSHEET_UNREADABLE");
});

/** 把 xlsx 里 sheet1.xml 的 XML 换掉（edit 收原本的 XML） */
function editSheetXml(bytes: Uint8Array, edit: (xml: string) => string): Uint8Array {
  return zipFiles(
    workbookParts(bytes).map((p) => ({
      name: p.name,
      data: p.name === "xl/worksheets/sheet1.xml" ? ascii(edit(new TextDecoder().decode(p.data))) : p.data,
    })),
  );
}

Deno.test("表写的范围（<dimension>）比内容长：只有格式的尾巴不算 TOO_MANY_ROWS；真的有值才算", () => {
  const small = xlsxOf(XLSX.utils.aoa_to_sheet([["Item", "Unit", "Price"], ["cup", "ctn", 85], ["lid", "ctn", 40]]));
  // Excel 框线画到第一万行：<dimension ref="A1:F10000"/>
  const framed = editSheetXml(small, (x) => x.replace(/<dimension ref="[^"]+"\/>/, '<dimension ref="A1:F10000"/>'));
  const wb = readWorkbook(framed, "xlsx");
  assertEquals(wb.Sheets.S["!fullref"], "A1:F10000");
  assertEquals(workbookLines(wb).map((l) => l.text), ["Item | Unit | Price", "cup | ctn | 85", "lid | ctn | 40"]);
  // 第 4801 行有一格只有格式（<c r="D4801" s="0"/>）
  const styled = editSheetXml(small, (x) =>
    x.replace(/<dimension ref="[^"]+"\/>/, '<dimension ref="A1:D4801"/>')
      .replace("</sheetData>", '<row r="4801"><c r="D4801" s="0"/></row></sheetData>'));
  assertEquals(workbookLines(readWorkbook(styled, "xlsx")).length, 3);
  // 第 4801 行真的有值 → TOO_MANY_ROWS
  const filled = editSheetXml(small, (x) =>
    x.replace(/<dimension ref="[^"]+"\/>/, '<dimension ref="A1:D4801"/>')
      .replace("</sheetData>", '<row r="4801"><c r="D4801"><v>1</v></c></row></sheetData>'));
  assertEquals(code(() => workbookLines(readWorkbook(filled, "xlsx"))), "TOO_MANY_ROWS");
  // 框线到第一万行，第 6000 行真的有一样商品 → TOO_MANY_ROWS（重读那张表才看得到）
  const late = editSheetXml(small, (x) =>
    x.replace(/<dimension ref="[^"]+"\/>/, '<dimension ref="A1:F10000"/>')
      .replace("</sheetData>", '<row r="6000"><c r="A6000" t="inlineStr"><is><t>late</t></is></c></row></sheetData>'));
  assertEquals(code(() => workbookLines(readWorkbook(late, "xlsx"))), "TOO_MANY_ROWS");
  // xls：DIMENSIONS 写到第一万行（!ref 比内容大）
  const ws = XLSX.utils.aoa_to_sheet([["Item", "Price"], ["cup", 85], ["lid", 40]]);
  ws["!ref"] = "A1:F10000";
  const xls = xlsxOf(ws, "biff8");
  const xwb = readWorkbook(xls, "xls");
  assert(xwb.Sheets.S["!fullref"], "xls should report the declared range");
  assertEquals(workbookLines(xwb).length, 3);
  // 不是 readWorkbook 读的（不能重读）：照旧宁可失败
  const raw = XLSX.read(framed, { type: "array", dense: true, sheetRows: MAX_SCAN_ROWS + 1 });
  assertEquals(code(() => workbookLines(raw)), "TOO_MANY_ROWS");
});
