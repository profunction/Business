// xlsx 的 zip 检查：zip 炸弹、谎报大小、跑不完的 deflate、很多笔指同一份资料 → 不交给 SheetJS。

import { assert, assertEquals, assertThrows } from "@std/assert";
import { readWorkbook, SpreadsheetError, workbookLines } from "../_shared/spreadsheet.ts";
import { inspectXlsxZip, MAX_XLSX_ENTRIES, MAX_XLSX_PARSED, scanDeflate, ZipGuardError } from "../_shared/zipguard.ts";
import {
  bombEntries,
  deflateRaw,
  makeWorkbook,
  workbookEntries,
  workbookParts,
  type ZipEntry,
  zipFiles,
} from "./_sheets.ts";

const MB = 1024 * 1024;
const enc = (s: string) => new TextEncoder().encode(s);

function guardCode(bytes: Uint8Array): string {
  try {
    inspectXlsxZip(bytes);
    return "ok";
  } catch (e) {
    assert(e instanceof ZipGuardError, String(e));
    return e.code;
  }
}

Deno.test("zip 检查：正常的 xlsx 通过，大小跟实际一样；重新包过的也读得到", async () => {
  const entries = inspectXlsxZip(makeWorkbook("xlsx")); // SheetJS 默认不压缩（stored）
  assert(entries.some((e) => e.name === "xl/worksheets/sheet1.xml" && e.method === 0 && e.bytes > 0));
  const parts = workbookParts(makeWorkbook("xlsx"));
  const rezipped = zipFiles(await workbookEntries());
  const info = inspectXlsxZip(rezipped);
  assertEquals(info.map((e) => [e.name, e.bytes]), parts.map((p) => [p.name, p.data.length]));
  assertEquals(workbookLines(readWorkbook(rezipped, "xlsx")).length, 5);
  // stored（不压缩）也可以
  assertEquals(
    workbookLines(readWorkbook(zipFiles(parts.map((p) => ({ name: p.name, data: p.data }))), "xlsx")).length,
    5,
  );
});

Deno.test("zip 炸弹：160 KB 的 xlsx 解开是 150 MB → FILE_TOO_LARGE，很快、不交给 SheetJS", async () => {
  for (const usz of [undefined, 1000, 0]) { // 照实写 / 谎报很小 / 没写（data descriptor 那种）
    const bomb = zipFiles(await bombEntries(150, usz));
    assert(bomb.length < 400_000, String(bomb.length));
    const before = Deno.memoryUsage().rss;
    const t = performance.now();
    const err = assertThrows(() => readWorkbook(bomb, "xlsx"), SpreadsheetError);
    const ms = performance.now() - t;
    assertEquals(err.code, "FILE_TOO_LARGE", err.message);
    // SheetJS 读这份要 1 秒多、300 多 MB；检查只数到上限就停，也不产生资料
    assert(ms < 1000, `${ms} ms`);
    assert(Deno.memoryUsage().rss - before < 64 * MB, "guard must not inflate into memory");
  }
});

Deno.test("zip 检查：单一 entry 压缩比超过 100:1（就算没超过总量）→ FILE_TOO_LARGE；正常压缩比不算", async () => {
  assertEquals(guardCode(zipFiles(await bombEntries(2))), "FILE_TOO_LARGE");
  // 2 MB 普通的表格 XML（压缩比大约 5:1）没问题
  const rows = Array.from({ length: 60000 }, (_, i) => `<row r="${i + 1}"><c r="A${i + 1}"><v>${i * 7}</v></c></row>`);
  const xml = enc(`<worksheet><sheetData>${rows.join("")}</sheetData></worksheet>`);
  assert(xml.length > 2 * MB, String(xml.length));
  assertEquals(
    guardCode(zipFiles([{ name: "xl/worksheets/sheet1.xml", data: xml, deflated: await deflateRaw([xml]) }])),
    "ok",
  );
});

Deno.test("zip 检查：header 写的大小太大（SheetJS 会先开那么大的 buffer）→ FILE_TOO_LARGE", async () => {
  const entries = await workbookEntries();
  entries[0] = { ...entries[0], usz: 0xfffffff0 };
  assertEquals(guardCode(zipFiles(entries)), "FILE_TOO_LARGE");
});

Deno.test("zip 检查：很多笔中央目录指同一份资料（每笔 SheetJS 都会复制一份）→ FILE_TOO_LARGE", () => {
  const sheet = new Uint8Array(MB).fill(0x20);
  const entries: ZipEntry[] = [{ name: "xl/worksheets/sheet1.xml", data: sheet }];
  for (let i = 0; i < 20; i++) entries.push({ name: `xl/worksheets/sheet${i + 2}.xml`, sameAs: 0 });
  assertEquals(guardCode(zipFiles(entries)), "FILE_TOO_LARGE");
  // 图片不用解析：只算总量（32 MB），不算 16 MB 的表格上限
  const media: ZipEntry[] = [{ name: "xl/media/image1.png", data: sheet }];
  for (let i = 0; i < 20; i++) media.push({ name: `xl/media/image${i + 2}.png`, sameAs: 0 });
  assertEquals(guardCode(zipFiles(media)), "ok");
  assert(21 * MB > MAX_XLSX_PARSED);
});

Deno.test("zip 检查：deflate 资料到档尾都没结束（SheetJS 会一直跑下去）、坏掉的 deflate、太多 entry → SPREADSHEET_UNREADABLE", async () => {
  // 不是最后一块的空 stored block，后面就没东西了：SheetJS 的 inflate 会把档尾之后当成 0 一直读（测试过：卡住不会回来）
  const hang = zipFiles(await workbookEntries(), [{
    name: "xl/x.xml",
    deflated: new Uint8Array([0, 0, 0, 0xff, 0xff]),
    usz: 0,
  }]);
  // 这两份真的交给 SheetJS 都会卡住（测试过，30 秒都不回来），所以这里只检查 guard；
  // readWorkbook 会先叫 guard（上面炸弹的测试有验）
  assertEquals(guardCode(hang), "SPREADSHEET_UNREADABLE");
  // deflate 资料在中间断掉、后面接着别的东西
  const cut = zipFiles([...(await workbookEntries()), {
    name: "xl/y.xml",
    deflated: (await deflateRaw([enc("<x>" + "y".repeat(5000) + "</x>")])).subarray(0, 10),
    usz: 5007,
  }]);
  assertEquals(guardCode(cut), "SPREADSHEET_UNREADABLE");
  // block type 3 不存在
  assertEquals(
    guardCode(zipFiles([{ name: "xl/a.xml", deflated: new Uint8Array([0x07, 0, 0]), usz: 1 }])),
    "SPREADSHEET_UNREADABLE",
  );
  // stored block 的 NLEN 不对
  assertEquals(
    guardCode(zipFiles([{ name: "xl/a.xml", deflated: new Uint8Array([1, 3, 0, 0, 0, 1, 2, 3]), usz: 3 }])),
    "SPREADSHEET_UNREADABLE",
  );
  // 第一个符号就是「往回 1 个字复制 3 个字」（前面什么都还没有）：固定 Huffman，257 + 距离码 0
  assertEquals(
    guardCode(zipFiles([{ name: "xl/a.xml", deflated: new Uint8Array([0x03, 0x02, 0, 0]), usz: 3 }])),
    "SPREADSHEET_UNREADABLE",
  );
  assertThrows(() => scanDeflate(new Uint8Array([0x03, 0x02, 0, 0]), 0, 100), ZipGuardError, "distance too far back");
  const many: ZipEntry[] = Array.from(
    { length: MAX_XLSX_ENTRIES + 1 },
    (_, i) => ({ name: `xl/${i}.xml`, data: enc("x") }),
  );
  assertEquals(guardCode(zipFiles(many)), "SPREADSHEET_UNREADABLE");
  assertEquals(guardCode(enc("PK\x03\x04 not really a zip")), "SPREADSHEET_UNREADABLE");
});

Deno.test("deflate 扫描器：大小、用掉的字数跟 CompressionStream 一致（各种资料）", async () => {
  const samples = [
    enc(""),
    enc("a"),
    enc("hello hello hello hello"),
    crypto.getRandomValues(new Uint8Array(60_000)), // 几乎不能压缩（stored / 很长的 Huffman）
    enc('<c r="A1"><v>1</v></c>'.repeat(50_000)),
    Uint8Array.from({ length: 200_000 }, (_, i) => (i * 2654435761) >>> 27),
  ];
  for (const s of samples) {
    const d = await deflateRaw([s]);
    assertEquals(scanDeflate(d, 0, Infinity), { size: s.length, consumed: d.length });
  }
  const big = await deflateRaw([new Uint8Array(3 * MB)]);
  assertThrows(() => scanDeflate(big, 0, MB), ZipGuardError, "FILE_TOO_LARGE");
});
