// xlsx（zip）交给 SheetJS 之前先检查：SheetJS 会把每个 entry 整个解压到记忆体（sheetRows 管不到），
// 解压用的是纯 JS 的 inflate，坏掉的 deflate 资料还会让它一直跑下去。150 KB 的「zip 炸弹」就能把 worker
// 的 256 MB 记忆体 / 2 秒 CPU 用完，worker 被杀掉时 catch 不会跑，import 会一直卡在 processing。
//
// 这里照 SheetJS 0.20.3 读 zip 的方式（parse_zip / parse_local_file）走一次中央目录，用自己写的 deflate 扫描器
// 算出每个 entry 真正解压后的大小（只数，不产生资料；超过上限马上停），确认每段 deflate 资料在档案里正常结束。
// 超过预算 → FILE_TOO_LARGE；格式不对（SheetJS 可能当掉或跑不完）→ SPREADSHEET_UNREADABLE。

/** 全部 entry 解压后（SheetJS 会放进记忆体的）合计上限（图片也算） */
export const MAX_XLSX_UNCOMPRESSED = 32 * 1024 * 1024;
/**
 * 要 SheetJS 解析的部分（图片 / 内嵌档以外：工作表 XML、sharedStrings……）合计上限。
 * 正常的价目表不到 2 MB；16 MB 的工作表 SheetJS 大约 0.4 秒 CPU、110 MB 记忆体。
 */
export const MAX_XLSX_PARSED = 16 * 1024 * 1024;
/** 一个 entry 解压后超过 1 MB 而且压缩比超过 100:1 → 当成炸弹 */
export const MAX_XLSX_RATIO = 100;
const RATIO_MIN_BYTES = 1024 * 1024;
/** 正常的 xlsx 几十个 entry */
export const MAX_XLSX_ENTRIES = 1000;
/** SheetJS 解压每个 entry 前会复制「从这里到档尾」：合计上限（不然几千个 entry 指同一个位置就是几十 GB 的复制） */
const MAX_COPY_BYTES = 400 * 1024 * 1024;

export class ZipGuardError extends Error {
  constructor(public readonly code: "FILE_TOO_LARGE" | "SPREADSHEET_UNREADABLE", public readonly detail: string) {
    super(`${code}: ${detail}`);
    this.name = "ZipGuardError";
  }
}

const tooLarge = (d: string) => new ZipGuardError("FILE_TOO_LARGE", d);
const unreadable = (d: string) => new ZipGuardError("SPREADSHEET_UNREADABLE", d);

// SheetJS 的 read_shift 读超过结尾时当 0（undefined | 0 === 0）；这里照做
function u16(b: Uint8Array, i: number, end = b.length): number {
  return (i < end ? b[i] : 0) | (i + 1 < end ? b[i + 1] << 8 : 0);
}
function u32(b: Uint8Array, i: number, end = b.length): number {
  return (u16(b, i, end) + u16(b, i + 2, end) * 0x10000) >>> 0;
}

/** 照 SheetJS parse_extra_field：只看 ZIP64（0x0001）给的 usz / csz（0 = 没有） */
function zip64Sizes(b: Uint8Array, start: number, len: number): { usz: number; csz: number } {
  const end = Math.min(b.length, start + len);
  let l = start;
  let usz = 0, csz = 0;
  while (l <= end - 4) {
    const type = u16(b, l, end);
    const sz = u16(b, l + 2, end);
    if (type === 0x0001) {
      usz = u32(b, l + 4, end) + u32(b, l + 8, end) * 2 ** 32;
      csz = u32(b, l + 12, end) + u32(b, l + 16, end) * 2 ** 32;
    }
    l += 4 + sz;
  }
  return { usz, csz };
}

/** SheetJS 只放着不解析的 entry（图片、内嵌的档案、缩图、打印设定） */
function isBinaryPart(name: string): boolean {
  return /^(xl\/(media|embeddings|printerSettings)\/|docProps\/thumbnail)/i.test(name);
}

export interface ZipEntryInfo {
  name: string;
  method: number;
  /** SheetJS 会留在记忆体的大小 */
  bytes: number;
  compressed: number;
}

/**
 * 检查一个 xlsx 交给 SheetJS 安不安全。合格 → 回传每个 entry 的大小；不合格 → 丢 ZipGuardError。
 * 跟 SheetJS 一样：从档尾往前找中央目录结尾（PK\x05\x06），中央目录每一笔都去读它的 local header。
 */
export function inspectXlsxZip(b: Uint8Array): ZipEntryInfo[] {
  let eocd = b.length - 4;
  while (eocd >= 0 && !(b[eocd] === 0x50 && b[eocd + 1] === 0x4b && b[eocd + 2] === 0x05 && b[eocd + 3] === 0x06)) {
    eocd--;
  }
  if (eocd < 0 || eocd + 22 > b.length) throw unreadable("no end of central directory");
  const count = u16(b, eocd + 8);
  let p = u32(b, eocd + 16);
  if (count === 0) throw unreadable("empty zip");
  if (count > MAX_XLSX_ENTRIES) throw unreadable(`${count} entries`);

  const out: ZipEntryInfo[] = [];
  let total = 0;
  let parsed = 0;
  let copied = 0;
  for (let n = 0; n < count; n++) {
    if (p + 46 > b.length) throw unreadable("central directory out of range");
    let csz = u32(b, p + 20);
    let usz = u32(b, p + 24);
    const nameLen = u16(b, p + 28);
    const extraLen = u16(b, p + 30);
    const commentLen = u16(b, p + 32);
    const offset = u32(b, p + 42);
    const cdExtra = p + 46 + nameLen;
    const cd64 = zip64Sizes(b, cdExtra, extraLen);
    if (cd64.usz) usz = cd64.usz;
    if (cd64.csz) csz = cd64.csz;
    p = cdExtra + extraLen + commentLen;

    // local header（SheetJS 不看签名，直接跳过 4 个字）
    const h = offset + 4;
    if (h + 26 > b.length) throw unreadable("local header out of range");
    const flags = u16(b, h + 2);
    const method = u16(b, h + 4);
    let lcsz = u32(b, h + 14);
    let lusz = u32(b, h + 18);
    const lNameLen = u16(b, h + 22);
    const lExtraLen = u16(b, h + 24);
    const name = String.fromCharCode(...b.subarray(h + 26, Math.min(b.length, h + 26 + lNameLen)));
    if (lExtraLen) {
      const l64 = zip64Sizes(b, h + 26 + lNameLen, lExtraLen);
      if (l64.usz) lusz = l64.usz;
      if (l64.csz) lcsz = l64.csz;
      if (cd64.usz) lusz = cd64.usz;
      if (cd64.csz) lcsz = cd64.csz;
    }
    const data = h + 26 + lNameLen + lExtraLen;
    if (flags & 0x2041) throw unreadable(`${name}: encrypted`);
    if (data > b.length) throw unreadable(`${name}: data out of range`);
    if (Math.max(usz, lusz) > MAX_XLSX_UNCOMPRESSED) throw tooLarge(`${name}: declared ${Math.max(usz, lusz)} bytes`);

    let bytes: number;
    let compressed: number;
    if (method === 0) {
      bytes = Math.min(lcsz, b.length - data);
      compressed = bytes;
    } else if (method === 8) {
      copied += b.length - data;
      if (copied > MAX_COPY_BYTES) throw tooLarge("too many deflated entries");
      const scan = scanDeflate(b, data, Math.min(MAX_XLSX_UNCOMPRESSED - total, isBinaryPart(name) ? Infinity : MAX_XLSX_PARSED - parsed));
      // SheetJS：有写大小就先开那么大的 buffer（写不下的丢掉），没写就边解边加大
      bytes = Math.max(scan.size, lusz);
      compressed = scan.consumed;
    } else {
      throw unreadable(`${name}: compression method ${method}`);
    }
    total += bytes;
    if (total > MAX_XLSX_UNCOMPRESSED) throw tooLarge(`uncompressed total over ${MAX_XLSX_UNCOMPRESSED}`);
    if (!isBinaryPart(name)) {
      parsed += bytes;
      if (parsed > MAX_XLSX_PARSED) throw tooLarge(`sheets / XML over ${MAX_XLSX_PARSED}`);
    }
    if (bytes >= RATIO_MIN_BYTES && bytes > MAX_XLSX_RATIO * Math.max(1, compressed)) {
      throw tooLarge(`${name}: compression ratio ${Math.round(bytes / Math.max(1, compressed))}:1`);
    }
    out.push({ name, method, bytes, compressed });
  }
  return out;
}

// ---------------------------------------------------------------------------
// deflate（RFC 1951）扫描器：照规格解码每个符号，只数输出多少字，不产生资料。
// 跟 zlib 一样严格：不完整 / 超额的 Huffman 码、距离超过已经输出的、stored block 的 NLEN 不对、
// 档案结束了 deflate 还没结束（SheetJS 遇到这种会一直跑下去）→ 丢错。
// ---------------------------------------------------------------------------

class DeflateError extends Error {}

interface Huffman {
  counts: Uint16Array;
  symbols: Uint16Array;
}

const LEN_BASE = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258];
const LEN_EXTRA = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];
const DIST_BASE = [
  1,
  2,
  3,
  4,
  5,
  7,
  9,
  13,
  17,
  25,
  33,
  49,
  65,
  97,
  129,
  193,
  257,
  385,
  513,
  769,
  1025,
  1537,
  2049,
  3073,
  4097,
  6145,
  8193,
  12289,
  16385,
  24577,
];
const DIST_EXTRA = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13];
const CLEN_ORDER = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];

/** 标准 Huffman 码；allowIncomplete：zlib 只接受「只有一个长度 1 的码」这种不完整（或完全没有码） */
function buildHuffman(lengths: ArrayLike<number>, n: number, allowIncomplete: boolean): Huffman {
  const counts = new Uint16Array(16);
  for (let i = 0; i < n; i++) counts[lengths[i]]++;
  counts[0] = 0;
  let left = 1;
  let maxLen = 0;
  for (let len = 1; len <= 15; len++) {
    left = (left << 1) - counts[len];
    if (left < 0) throw new DeflateError("over-subscribed code");
    if (counts[len]) maxLen = len;
  }
  if (left > 0 && maxLen > 0 && !(allowIncomplete && maxLen === 1)) throw new DeflateError("incomplete code");
  const offs = new Uint16Array(16);
  for (let len = 1; len < 15; len++) offs[len + 1] = offs[len] + counts[len];
  const symbols = new Uint16Array(n);
  for (let i = 0; i < n; i++) if (lengths[i]) symbols[offs[lengths[i]]++] = i;
  return { counts, symbols };
}

const FIXED_LIT = (() => {
  const l = new Uint8Array(288);
  l.fill(8, 0, 144);
  l.fill(9, 144, 256);
  l.fill(7, 256, 280);
  l.fill(8, 280, 288);
  return buildHuffman(l, 288, false);
})();
const FIXED_DIST = buildHuffman(new Uint8Array(32).fill(5), 32, false); // 30、31 不能用（下面会挡）

/**
 * 从 start 开始扫一段 raw deflate：回传解压后多少字、用了多少字的压缩资料。
 * 输出超过 cap → FILE_TOO_LARGE；资料不对或档案先结束 → SPREADSHEET_UNREADABLE。
 */
export function scanDeflate(b: Uint8Array, start: number, cap: number): { size: number; consumed: number } {
  let pos = start; // 下一个还没读进 bitbuf 的字
  let bitbuf = 0;
  let bitcnt = 0;
  let size = 0;

  const bits = (need: number): number => {
    while (bitcnt < need) {
      if (pos >= b.length) throw new DeflateError("unexpected end of data");
      bitbuf |= b[pos++] << bitcnt;
      bitcnt += 8;
    }
    const v = bitbuf & ((1 << need) - 1);
    bitbuf >>>= need;
    bitcnt -= need;
    return v;
  };

  const decode = (h: Huffman): number => {
    let code = 0, first = 0, index = 0;
    for (let len = 1; len <= 15; len++) {
      if (bitcnt === 0) {
        if (pos >= b.length) throw new DeflateError("unexpected end of data");
        bitbuf = b[pos++];
        bitcnt = 8;
      }
      code |= bitbuf & 1;
      bitbuf >>>= 1;
      bitcnt--;
      const count = h.counts[len];
      if (code - count < first) return h.symbols[index + (code - first)];
      index += count;
      first = (first + count) << 1;
      code <<= 1;
    }
    throw new DeflateError("invalid Huffman code");
  };

  try {
    let last = 0;
    while (!last) {
      last = bits(1);
      const type = bits(2);
      if (type === 0) {
        bitbuf = 0; // 跳到下一个字
        bitcnt = 0;
        if (pos + 4 > b.length) throw new DeflateError("unexpected end of data");
        const len = b[pos] | (b[pos + 1] << 8);
        const nlen = b[pos + 2] | (b[pos + 3] << 8);
        if ((len ^ 0xffff) !== nlen) throw new DeflateError("stored block length mismatch");
        pos += 4;
        if (pos + len > b.length) throw new DeflateError("unexpected end of data");
        pos += len;
        size += len;
        if (size > cap) throw tooLarge("uncompressed size over budget");
        continue;
      }
      let lit: Huffman, dist: Huffman;
      if (type === 1) {
        lit = FIXED_LIT;
        dist = FIXED_DIST;
      } else if (type === 2) {
        const nlen = bits(5) + 257;
        const ndist = bits(5) + 1;
        const ncode = bits(4) + 4;
        if (nlen > 286 || ndist > 30) throw new DeflateError("bad counts");
        const cl = new Uint8Array(19);
        for (let i = 0; i < ncode; i++) cl[CLEN_ORDER[i]] = bits(3);
        const clh = buildHuffman(cl, 19, false);
        const lengths = new Uint8Array(nlen + ndist);
        for (let i = 0; i < nlen + ndist;) {
          const sym = decode(clh);
          if (sym < 16) {
            lengths[i++] = sym;
            continue;
          }
          let rep: number, val = 0;
          if (sym === 16) {
            if (i === 0) throw new DeflateError("repeat with no previous length");
            val = lengths[i - 1];
            rep = 3 + bits(2);
          } else if (sym === 17) {
            rep = 3 + bits(3);
          } else {
            rep = 11 + bits(7);
          }
          if (i + rep > nlen + ndist) throw new DeflateError("too many lengths");
          while (rep--) lengths[i++] = val;
        }
        if (lengths[256] === 0) throw new DeflateError("no end-of-block code");
        lit = buildHuffman(lengths.subarray(0, nlen), nlen, true);
        dist = buildHuffman(lengths.subarray(nlen), ndist, true);
      } else {
        throw new DeflateError("invalid block type");
      }
      for (;;) {
        const sym = decode(lit);
        if (sym < 256) {
          size++;
        } else if (sym === 256) {
          break;
        } else {
          const li = sym - 257;
          if (li >= 29) throw new DeflateError("invalid length code");
          const len = LEN_BASE[li] + bits(LEN_EXTRA[li]);
          const di = decode(dist);
          if (di >= 30) throw new DeflateError("invalid distance code");
          const d = DIST_BASE[di] + bits(DIST_EXTRA[di]);
          if (d > size) throw new DeflateError("distance too far back");
          size += len;
        }
        if (size > cap) throw tooLarge("uncompressed size over budget");
      }
    }
  } catch (e) {
    if (e instanceof DeflateError) throw unreadable(`deflate: ${e.message}`);
    throw e;
  }
  return { size, consumed: pos - start };
}
