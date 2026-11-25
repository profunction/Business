import { assert, assertEquals, assertStringIncludes, assertThrows } from "@std/assert";
import { isImage, isSpreadsheet, sniffFileType } from "../_shared/filetype.ts";
import {
  chunkLines,
  decodeText,
  MAX_LINES,
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
