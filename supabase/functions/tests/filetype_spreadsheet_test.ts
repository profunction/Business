import { assert, assertEquals, assertFalse, assertStringIncludes, assertThrows } from "@std/assert";
// @deno-types="https://cdn.sheetjs.com/xlsx-0.20.3/package/types/index.d.ts"
import * as XLSX from "xlsx";
import { isImage, isSpreadsheet, sniffFileType } from "../_shared/filetype.ts";
import {
  chunkLines,
  decodeText,
  findHeader,
  isHeaderCell,
  lastFilledLine,
  MAX_LINES,
  MAX_SCAN_ROWS,
  readWorkbook,
  renderChunk,
  type SheetLine,
  splitChunk,
  SpreadsheetError,
  workbookLines,
} from "../_shared/spreadsheet.ts";
import { makeWorkbook } from "./_sheets.ts";

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
  const chunks = chunkLines(lines);
  assertEquals(chunks.length, 2);
  assert(renderChunk(chunks[1]).startsWith("[context] Sheet1!R3: No | Item | Pack (pcs/ctn) | Price (RM) | MOQ\n"));

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
