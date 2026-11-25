// 测试里自己做的小 Excel（SheetJS 写出来）。
// @deno-types="https://cdn.sheetjs.com/xlsx-0.20.3/package/types/index.d.ts"
import * as XLSX from "xlsx";

/** 测试里自己做一个小 Excel */
export function makeWorkbook(bookType: "xlsx" | "biff8", hidden = true): Uint8Array {
  const ws = XLSX.utils.aoa_to_sheet([
    ["新山包装批发 JB Packaging Supply"],
    [],
    ["No", "货品 Item", "Unit", "Harga (RM)", "MOQ"],
    [1, "16安士 PP杯 95口径", "箱", 85.5, "5 ctn"],
    [2, "95 平盖", "ctn", 40, ""],
    [3, "Straw 6mm / 8mm", "pkt", "RM3.50 / RM4.00", ""],
  ]);
  ws["D4"].z = '"RM"#,##0.00';
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, "Harga");
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([["secret cost price", 1]]), "Kos");
  if (hidden) wb.Workbook = { Sheets: [{ Hidden: 0 }, { Hidden: 1 }] };
  return new Uint8Array(XLSX.write(wb, { type: "array", bookType }) as ArrayBuffer);
}

/** 测试用的 zip：entry 可以给原始资料（stored / 自己 deflate）、直接给 deflate 好的资料、谎报大小、指到别的 entry 的位置 */
export interface ZipEntry {
  name: string;
  /** 原始资料（method 0 直接放；method 8 用 deflated） */
  data?: Uint8Array;
  /** method 8 的压缩资料 */
  deflated?: Uint8Array;
  /** 写在 header 的解压后大小（默认 data 的长度；可以谎报） */
  usz?: number;
  /** 中央目录指到第几个 entry 的 local header（做「很多笔指同一份资料」用） */
  sameAs?: number;
}

const u16le = (n: number) => [n & 0xff, (n >>> 8) & 0xff];
const u32le = (n: number) => [n & 0xff, (n >>> 8) & 0xff, (n >>> 16) & 0xff, (n >>> 24) & 0xff];

/** 照 zip 规格写（CRC 填 0：SheetJS 不检查）。trailing = 放在中央目录结尾「后面」的 entry（SheetJS 从档尾往前找结尾） */
export function zipFiles(entries: ZipEntry[], trailing: ZipEntry[] = []): Uint8Array {
  const parts: number[][] = [];
  let size = 0;
  const push = (p: number[] | Uint8Array) => {
    parts.push(Array.from(p));
    size += p.length;
  };
  const local = (e: ZipEntry): { offset: number; method: number; csz: number; usz: number } => {
    const name = new TextEncoder().encode(e.name);
    const method = e.deflated ? 8 : 0;
    const body = e.deflated ?? e.data ?? new Uint8Array(0);
    const usz = e.usz ?? e.data?.length ?? 0;
    const offset = size;
    push([0x50, 0x4b, 0x03, 0x04, 20, 0, 0, 0, ...u16le(method), 0, 0, 0x21, 0, ...u32le(0)]);
    push([...u32le(body.length), ...u32le(usz), ...u16le(name.length), 0, 0]);
    push(name);
    push(body);
    return { offset, method, csz: body.length, usz };
  };
  const all = [...entries, ...trailing];
  const locs: ({ offset: number; method: number; csz: number; usz: number } | null)[] = entries.map((e) =>
    e.sameAs === undefined ? local(e) : null
  );
  const writeCd = (from: ZipEntry[], locsOf: typeof locs) => {
    from.forEach((e, i) => {
      const l = e.sameAs === undefined ? locsOf[i]! : locsOf[e.sameAs]!;
      const name = new TextEncoder().encode(e.name);
      push([0x50, 0x4b, 0x01, 0x02, 20, 0, 20, 0, 0, 0, ...u16le(l.method), 0, 0, 0x21, 0, ...u32le(0)]);
      push([...u32le(l.csz), ...u32le(l.usz), ...u16le(name.length), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
      push([...u32le(l.offset)]);
      push(name);
    });
  };
  // trailing 的 local header 要放在结尾后面，所以先算好位置：结尾后面第一个位置
  const cdStart = size;
  const cdSize = all.reduce((n, e) => n + 46 + new TextEncoder().encode(e.name).length, 0);
  const afterEocd = cdStart + cdSize + 22;
  const trailingLocs: { offset: number; method: number; csz: number; usz: number }[] = [];
  let at = afterEocd;
  for (const e of trailing) {
    const body = e.deflated ?? e.data ?? new Uint8Array(0);
    trailingLocs.push({ offset: at, method: e.deflated ? 8 : 0, csz: body.length, usz: e.usz ?? e.data?.length ?? 0 });
    at += 30 + new TextEncoder().encode(e.name).length + body.length;
  }
  writeCd(entries, locs);
  writeCd(trailing, trailingLocs);
  push([0x50, 0x4b, 0x05, 0x06, 0, 0, 0, 0, ...u16le(all.length), ...u16le(all.length)]);
  push([...u32le(cdSize), ...u32le(cdStart), 0, 0]);
  for (const e of trailing) local(e);
  const out = new Uint8Array(size);
  let o = 0;
  for (const p of parts) {
    out.set(p, o);
    o += p.length;
  }
  return out;
}

/** raw deflate（CompressionStream）；chunks 可以是很大的资料分很多段送，不用整份放在记忆体 */
export async function deflateRaw(chunks: Iterable<Uint8Array>): Promise<Uint8Array> {
  const it = chunks[Symbol.iterator]();
  const src = new ReadableStream<Uint8Array<ArrayBuffer>>({
    pull(c) {
      const n = it.next();
      if (n.done) c.close();
      else c.enqueue(n.value as Uint8Array<ArrayBuffer>);
    },
  });
  return new Uint8Array(await new Response(src.pipeThrough(new CompressionStream("deflate-raw"))).arrayBuffer());
}

/** SheetJS 做的 xlsx 拆成一个个 entry（拿来重新包、换掉某个 entry） */
export function workbookParts(bytes: Uint8Array): { name: string; data: Uint8Array }[] {
  const z = XLSX.CFB.read(bytes, { type: "array" }) as {
    FileIndex: { type: number; name: string; content?: ArrayLike<number> }[];
    FullPaths: string[];
  };
  return z.FileIndex.flatMap((f, i) =>
    f.type === 2 && f.content && !f.name.startsWith("\u0001")
      ? [{ name: z.FullPaths[i].replace(/^[^/]*\//, ""), data: new Uint8Array(f.content as ArrayLike<number>) }]
      : []
  );
}

/** makeWorkbook 的 entry，全部 deflate */
export async function workbookEntries(): Promise<ZipEntry[]> {
  return await Promise.all(
    workbookParts(makeWorkbook("xlsx")).map(async (p) => ({
      name: p.name,
      data: p.data,
      deflated: await deflateRaw([p.data]),
    })),
  );
}

/**
 * zip 炸弹：正常的 xlsx，sheet1.xml 中间塞 mb MB 空白（XML 还是合法的；SheetJS 会全部解开才看 sheetRows）。
 * usz：header 写的解压后大小（默认照实写；可以谎报很小或 0）
 */
export async function bombEntries(mb: number, usz?: number): Promise<ZipEntry[]> {
  const entries = await workbookEntries();
  const i = entries.findIndex((e) => e.name === "xl/worksheets/sheet1.xml");
  const xml = new TextDecoder().decode(entries[i].data);
  const cut = xml.indexOf("<sheetData>") + "<sheetData>".length;
  const head = new TextEncoder().encode(xml.slice(0, cut));
  const tail = new TextEncoder().encode(xml.slice(cut));
  const blank = new Uint8Array(1024 * 1024).fill(0x20);
  function* chunks() {
    yield head;
    for (let k = 0; k < mb; k++) yield blank;
    yield tail;
  }
  entries[i] = {
    name: entries[i].name,
    deflated: await deflateRaw(chunks()),
    usz: usz ?? head.length + tail.length + mb * 1024 * 1024,
  };
  return entries;
}

/**
 * 一串「空的 dynamic Huffman block」（每个 92 bit、没有输出，最后一个是 final）：
 * 符合 deflate 规格，但每个 block 解码器都要重建三个 Huffman 表。正常的编码器不会这样写。
 */
export function emptyDynamicBlocks(n: number): Uint8Array {
  const out = new Uint8Array(Math.ceil((n * 92) / 8) + 1);
  let bit = 0;
  const put = (v: number, len: number) => { // 数值：低位先写
    for (let i = 0; i < len; i++, bit++) if ((v >> i) & 1) out[bit >> 3] |= 1 << (bit & 7);
  };
  const code = (c: number, len: number) => { // Huffman 码：高位先写
    for (let i = len - 1; i >= 0; i--, bit++) if ((c >> i) & 1) out[bit >> 3] |= 1 << (bit & 7);
  };
  // 码长的码：18 → 1 bit「0」，0 → 「10」，1 → 「11」；照 CLEN_ORDER 写 18 个（HCLEN = 14）
  const clen: Record<number, number> = { 18: 1, 0: 2, 1: 2 };
  const order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1];
  for (let k = 0; k < n; k++) {
    put(k === n - 1 ? 1 : 0, 1); // BFINAL
    put(2, 2); // BTYPE = dynamic
    put(0, 5); // HLIT = 257
    put(0, 5); // HDIST = 1
    put(14, 4); // HCLEN = 18
    for (const s of order) put(clen[s] ?? 0, 3);
    code(0, 1), put(127, 7); // 18：138 个 0
    code(0, 1), put(107, 7); // 18：118 个 0（字面 0..255 都没有码）
    code(3, 2); // 1：符号 256（block 结束）码长 1
    code(2, 2); // 0：距离码都没有
    code(0, 1); // 马上 block 结束
  }
  return out.subarray(0, Math.ceil(bit / 8));
}

/** 小的 xls（SheetJS 写的），在最后一张表结束（EOF）之前塞进 n 笔 BIFF 记录（make(i) 回传一笔：type、内容） */
export function xlsWithRecords(n: number, make: (i: number) => [number, number[]]): Uint8Array {
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([["Item", "Price"], ["cup", 1]]), "S");
  const cfb = XLSX.CFB.read(new Uint8Array(XLSX.write(wb, { type: "array", bookType: "biff8" }) as ArrayBuffer), {
    type: "array",
  });
  const entry = XLSX.CFB.find(cfb, "/Workbook")!;
  const c = Uint8Array.from(entry.content as ArrayLike<number>);
  let lastEof = -1;
  for (let i = 0; i + 4 <= c.length;) {
    if ((c[i] | (c[i + 1] << 8)) === 0x000a) lastEof = i;
    i += 4 + (c[i + 2] | (c[i + 3] << 8));
  }
  const recs: number[] = [];
  for (let i = 0; i < n; i++) {
    const [type, body] = make(i);
    recs.push(type & 0xff, type >>> 8, body.length & 0xff, body.length >>> 8, ...body);
  }
  const out = new Uint8Array(c.length + recs.length);
  out.set(c.subarray(0, lastEof));
  out.set(recs, lastEof);
  out.set(c.subarray(lastEof), lastEof + recs.length);
  entry.content = out;
  entry.size = out.length;
  return new Uint8Array(XLSX.CFB.write(cfb, { type: "array" }) as ArrayLike<number>);
}
