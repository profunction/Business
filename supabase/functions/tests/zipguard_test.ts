// xlsx 的 zip 检查：zip 炸弹、谎报大小、跑不完的 deflate、很多笔指同一份资料 → 不交给 SheetJS。

import { assert, assertEquals, assertThrows } from "@std/assert";
import { readWorkbook, SpreadsheetError, workbookLines } from "../_shared/spreadsheet.ts";
import {
  BLOCK_SLACK,
  inspectXlsxZip,
  MAX_COPY_BYTES,
  MAX_XLSX_ENTRIES,
  MAX_XLSX_PARSED,
  scanDeflate,
  ZipGuardError,
} from "../_shared/zipguard.ts";
import { sniffFileType } from "../_shared/filetype.ts";
import {
  bombEntries,
  deflateRaw,
  emptyDynamicBlocks,
  makeWorkbook,
  workbookEntries,
  workbookParts,
  type ZipEntry,
  zipFiles,
} from "./_sheets.ts";

const MB = 1024 * 1024;
const enc = (s: string) => new TextEncoder().encode(s);

function guardCode(bytes: Uint8Array, timeMs?: number): string {
  try {
    inspectXlsxZip(bytes, { timeMs });
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

Deno.test("zip 检查：很多笔中央目录指同一份资料（SheetJS 每笔都会再解压一次）→ SPREADSHEET_UNREADABLE，图片也一样", () => {
  const sheet = new Uint8Array(MB).fill(0x20);
  for (const kind of ["worksheets/sheet", "media/image"]) {
    const entries: ZipEntry[] = [{ name: `xl/${kind}1.xml`, data: sheet }];
    for (let i = 0; i < 20; i++) entries.push({ name: `xl/${kind}${i + 2}.xml`, sameAs: 0 });
    assertEquals(guardCode(zipFiles(entries)), "SPREADSHEET_UNREADABLE", kind);
  }
  // 图片不用解析：只算总量（32 MB），不算 16 MB 的表格上限
  const media: ZipEntry[] = Array.from({ length: 20 }, (_, i) => ({ name: `xl/media/image${i + 1}.png`, data: sheet }));
  assertEquals(guardCode(zipFiles(media)), "ok");
  assert(20 * MB > MAX_XLSX_PARSED);
});

Deno.test("zip 检查：很多个 deflate 的 entry 都在档头（SheetJS 每个都复制到档尾）→ FILE_TOO_LARGE", async () => {
  const tiny = await deflateRaw([enc("<x/>")]);
  const entries: ZipEntry[] = Array.from({ length: 60 }, (_, i) => ({ name: `xl/${i}.xml`, deflated: tiny, usz: 4 }));
  entries.push({ name: "xl/media/big.png", data: new Uint8Array(8 * MB) });
  assert(60 * 8 * MB > MAX_COPY_BYTES);
  assertEquals(guardCode(zipFiles(entries)), "FILE_TOO_LARGE");
  assertEquals(guardCode(zipFiles(entries.slice(-10))), "ok");
});

/** local header（照 zip 规格；CRC 填 0） */
function localHeader(name: string, method: number, csz: number, usz: number): number[] {
  const n = enc(name);
  const u16 = (x: number) => [x & 0xff, x >>> 8];
  const u32 = (x: number) => [x & 0xff, (x >>> 8) & 0xff, (x >>> 16) & 0xff, x >>> 24];
  return [
    0x50,
    0x4b,
    3,
    4,
    20,
    0,
    0,
    0,
    ...u16(method),
    0,
    0,
    0x21,
    0,
    ...u32(0),
    ...u32(csz),
    ...u32(usz),
    ...u16(n.length),
    0,
    0,
    ...n,
  ];
}

/** 中央目录 + 结尾：entries 是 [名字, local header 的位置, method] */
function centralDirectory(entries: [string, number, number][], at: number): number[] {
  const u16 = (x: number) => [x & 0xff, x >>> 8];
  const u32 = (x: number) => [x & 0xff, (x >>> 8) & 0xff, (x >>> 16) & 0xff, x >>> 24];
  const cd: number[] = [];
  for (const [name, offset, method] of entries) {
    const n = enc(name);
    cd.push(0x50, 0x4b, 1, 2, 20, 0, 20, 0, 0, 0, ...u16(method), 0, 0, 0x21, 0, ...u32(0), ...u32(0), ...u32(0));
    cd.push(...u16(n.length), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, ...u32(offset), ...n);
  }
  return [
    ...cd,
    0x50,
    0x4b,
    5,
    6,
    0,
    0,
    0,
    0,
    ...u16(entries.length),
    ...u16(entries.length),
    ...u32(cd.length),
    ...u32(at),
    0,
    0,
  ];
}

Deno.test("zip 检查：一串空的 dynamic block（没有输出、每个都重建 Huffman 表）→ 马上 SPREADSHEET_UNREADABLE，不会跑几百秒", () => {
  const stream = emptyDynamicBlocks(174_000); // 2 MB，以前要扫 3 秒多
  assert(stream.length > 2_000_000, String(stream.length));
  let t = performance.now();
  assertThrows(() => scanDeflate(stream, 0, Infinity), ZipGuardError, "too many blocks for its output");
  assert(performance.now() - t < 100, `${performance.now() - t} ms`);
  // 正常数量的空 block 没问题（有些编码器结尾会多一两个）
  assertEquals(scanDeflate(emptyDynamicBlocks(BLOCK_SLACK), 0, Infinity).size, 0);
  // 整份的 block 上限
  assertThrows(
    () => scanDeflate(emptyDynamicBlocks(20), 0, Infinity, { maxBlocks: 10 }),
    ZipGuardError,
    "too many blocks",
  );

  // 以前：[Content_Types].xml + 40 笔中央目录指同一段 → sniff 说是 xlsx，检查跑 200 多秒后说 OK
  const head = [...localHeader("[Content_Types].xml", 0, 4, 4), ...enc("<x/>")];
  const sheetAt = head.length;
  const body = [...head, ...localHeader("xl/worksheets/sheet1.xml", 8, stream.length, 0)];
  const bytes = new Uint8Array(body.length + stream.length);
  bytes.set(body);
  bytes.set(stream, body.length);
  const cd = centralDirectory(
    [
      ["[Content_Types].xml", 0, 0],
      // 第一笔叫 xl/workbook.xml：sniff 才会当成 xlsx、交给这里检查
      ...Array.from(
        { length: 40 },
        (_, i) => [i === 0 ? "xl/workbook.xml" : `xl/s${i}.xml`, sheetAt, 8] as [string, number, number],
      ),
    ],
    bytes.length,
  );
  const file = new Uint8Array(bytes.length + cd.length);
  file.set(bytes);
  file.set(cd, bytes.length);
  assertEquals(sniffFileType(file), "xlsx");
  t = performance.now();
  assertEquals(guardCode(file), "SPREADSHEET_UNREADABLE");
  assert(performance.now() - t < 200, `${performance.now() - t} ms`);
  const err = assertThrows(() => readWorkbook(file, "xlsx"), SpreadsheetError);
  assertEquals(err.code, "SPREADSHEET_UNREADABLE");
});

Deno.test("zip 检查：两个 entry 的压缩资料重叠（不同 header、后一个扫进前一个）→ SPREADSHEET_UNREADABLE；每个字最多扫一次", async () => {
  const inner = await deflateRaw([enc("<row>" + "1".repeat(3000) + "</row>")]);
  const lh1 = localHeader("xl/b.xml", 8, inner.length, 3011);
  // entry 2 的 deflate：一个不是最后的 stored block 把 entry 1 整个包进去，再接一个空的 final block
  const payload = [...lh1, ...inner];
  const lh2 = localHeader("xl/a.xml", 8, 0, 0);
  const stored = [
    0x00,
    payload.length & 0xff,
    payload.length >>> 8,
    ~payload.length & 0xff,
    (~payload.length >>> 8) & 0xff,
  ];
  const body = [...lh2, ...stored, ...payload, 0x03, 0x00];
  const off1 = lh2.length + stored.length;
  for (const order of [[["xl/b.xml", off1, 8], ["xl/a.xml", 0, 8]], [["xl/a.xml", 0, 8], ["xl/b.xml", off1, 8]]]) {
    const file = new Uint8Array([...body, ...centralDirectory(order as [string, number, number][], body.length)]);
    assertEquals(guardCode(file), "SPREADSHEET_UNREADABLE", JSON.stringify(order));
  }
  // 各自分开就没问题
  const ok = new Uint8Array([...lh1, ...inner, ...centralDirectory([["xl/b.xml", 0, 8]], lh1.length + inner.length)]);
  assertEquals(guardCode(ok), "ok");
});

Deno.test("zip 检查：整个检查超过时间预算 → FILE_TOO_LARGE（最后一道防线）", async () => {
  const rows = Array.from({ length: 60000 }, (_, i) => `<row r="${i + 1}"><c r="A${i + 1}"><v>${i * 7}</v></c></row>`);
  const xml = enc(`<worksheet><sheetData>${rows.join("")}</sheetData></worksheet>`);
  const d = await deflateRaw([xml]);
  const zip = zipFiles([{ name: "xl/worksheets/sheet1.xml", data: xml, deflated: d }]);
  assertEquals(guardCode(zip), "ok");
  assertEquals(guardCode(zip, 0), "FILE_TOO_LARGE");
  assertThrows(() => scanDeflate(d, 0, Infinity, { deadline: performance.now() - 1 }), ZipGuardError, "time budget");
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
    const r = scanDeflate(d, 0, Infinity);
    assertEquals([r.size, r.consumed], [s.length, d.length]);
    assert(r.blocks >= 1 && r.blocks <= BLOCK_SLACK + s.length / 4096, String(r.blocks));
  }
  const big = await deflateRaw([new Uint8Array(3 * MB)]);
  assertThrows(() => scanDeflate(big, 0, MB), ZipGuardError, "FILE_TOO_LARGE");
});
