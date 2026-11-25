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
