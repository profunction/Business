// 用文件开头的「魔术字节」判断真正的格式（不信档名和 MIME）。
// Claude 只收 jpeg / png / gif / webp 图片和 PDF；Excel / CSV 先转成文字。HEIC 等其他格式不支持。

export type FileKind = "jpeg" | "png" | "webp" | "gif" | "pdf" | "xlsx" | "xls" | "csv" | "heic" | "unknown";

export const IMAGE_MEDIA_TYPES = {
  jpeg: "image/jpeg",
  png: "image/png",
  webp: "image/webp",
  gif: "image/gif",
} as const;

export type ImageKind = keyof typeof IMAGE_MEDIA_TYPES;

export function isImage(k: FileKind): k is ImageKind {
  return k in IMAGE_MEDIA_TYPES;
}

export function isSpreadsheet(k: FileKind): k is "xlsx" | "xls" | "csv" {
  return k === "xlsx" || k === "xls" || k === "csv";
}

function ascii(b: Uint8Array, start: number, len: number): string {
  return String.fromCharCode(...b.subarray(start, start + len));
}

function startsWith(b: Uint8Array, sig: number[], offset = 0): boolean {
  if (b.length < offset + sig.length) return false;
  return sig.every((x, i) => b[offset + i] === x);
}

/** 在 bytes 里找一段 ASCII 字（zip 的档名不压缩，看得到） */
function containsAscii(b: Uint8Array, needle: string): boolean {
  const n = new TextEncoder().encode(needle);
  outer: for (let i = 0; i + n.length <= b.length; i++) {
    for (let j = 0; j < n.length; j++) if (b[i + j] !== n[j]) continue outer;
    return true;
  }
  return false;
}

function u16(b: Uint8Array, i: number): number {
  return b[i] | (b[i + 1] << 8);
}
function u32(b: Uint8Array, i: number): number {
  return (u16(b, i) + u16(b, i + 2) * 0x10000) >>> 0;
}

interface ZipName {
  name: string;
  /** 0 = 没压缩（stored），8 = deflate */
  method: number;
  /** 没压缩的资料在 b 里的位置（只有 stored、而且找得到 local header 时有） */
  data: Uint8Array | null;
}

const latin1 = (b: Uint8Array) => String.fromCharCode(...b);

/** 没压缩（stored）的 entry 的资料：从 local header 找（档名、额外资料后面就是资料） */
function storedData(b: Uint8Array, localAt: number, size: number): Uint8Array | null {
  if (localAt + 30 > b.length || !startsWith(b, [0x50, 0x4b, 0x03, 0x04], localAt)) return null;
  const start = localAt + 30 + u16(b, localAt + 26) + u16(b, localAt + 28);
  if (start + size > b.length) return null;
  return b.subarray(start, start + size);
}

/**
 * zip 里每个档案的名字：先看最后面的中央目录（End of Central Directory → 每一笔记录）；
 * 找不到（档案被截掉、ZIP64）就从头一个一个读 local header（档名在 header 后面，不压缩）
 */
export function zipEntryNames(b: Uint8Array): ZipName[] {
  // EOCD：最后 22 字节起往前找（后面可能有最多 65535 字节的注解），签名 PK\x05\x06
  for (let i = b.length - 22; i >= Math.max(0, b.length - 22 - 0xffff); i--) {
    if (!startsWith(b, [0x50, 0x4b, 0x05, 0x06], i)) continue;
    const count = u16(b, i + 10);
    let at = u32(b, i + 16);
    const out: ZipName[] = [];
    let ok = true;
    for (let k = 0; k < count; k++) {
      // 中央目录的一笔：PK\x01\x02，压缩方式 +10，压缩后大小 +20，档名长度 +28，额外 +30，注解 +32，
      // local header 位置 +42，档名从 +46 开始
      if (at + 46 > b.length || !startsWith(b, [0x50, 0x4b, 0x01, 0x02], at)) {
        ok = false;
        break;
      }
      const n = u16(b, at + 28);
      if (at + 46 + n > b.length) {
        ok = false;
        break;
      }
      const method = u16(b, at + 10);
      out.push({
        name: latin1(b.subarray(at + 46, at + 46 + n)),
        method,
        data: method === 0 ? storedData(b, u32(b, at + 42), u32(b, at + 20)) : null,
      });
      at += 46 + n + u16(b, at + 30) + u16(b, at + 32);
    }
    if (ok) return out;
    break;
  }
  // local header：PK\x03\x04，压缩方式 +8，压缩后大小 +18，档名长度 +26，额外 +28，档名从 +30。
  // 压缩后的大小可能是 0（后面才写），所以不跳过资料，只往后找下一个签名，而且档名要印得出来
  const out: ZipName[] = [];
  for (let at = 0; at + 30 <= b.length; at++) {
    if (!startsWith(b, [0x50, 0x4b, 0x03, 0x04], at)) continue;
    const n = u16(b, at + 26);
    if (n === 0 || n > 512 || at + 30 + n > b.length) continue;
    const raw = b.subarray(at + 30, at + 30 + n);
    if (!raw.every((c) => c >= 0x20 && c < 0x7f)) continue;
    const method = u16(b, at + 8);
    out.push({ name: latin1(raw), method, data: method === 0 ? storedData(b, at, u32(b, at + 18)) : null });
  }
  return out;
}

/**
 * xlsx = zip 里有一个档案的名字正好是 xl/workbook.xml，或 [Content_Types].xml（没压缩时看得到内容）
 * 说是 spreadsheetml 的工作簿。只是内容里出现 "xl/" 不算
 */
export function isXlsxZip(b: Uint8Array): boolean {
  const entries = zipEntryNames(b);
  if (entries.some((e) => e.name === "xl/workbook.xml")) return true;
  const types = entries.find((e) => e.name === "[Content_Types].xml");
  return !!types?.data && containsAscii(types.data, "spreadsheetml.sheet.main+xml");
}

const HEIF_BRANDS = new Set(["heic", "heix", "hevc", "hevx", "heim", "heis", "hevm", "hevs", "mif1", "msf1"]);

/** 看起来是文字（CSV / TSV）：没有 NUL，大部分是可以印的字；UTF-16 要有 BOM */
function looksLikeText(b: Uint8Array): boolean {
  if (startsWith(b, [0xff, 0xfe]) || startsWith(b, [0xfe, 0xff])) return true;
  const n = Math.min(b.length, 8192);
  if (n === 0) return false;
  let control = 0;
  for (let i = 0; i < n; i++) {
    const c = b[i];
    if (c === 0) return false;
    if (c < 0x09 || (c > 0x0d && c < 0x20) || c === 0x7f) control++;
  }
  return control / n < 0.01;
}

export function sniffFileType(b: Uint8Array): FileKind {
  if (b.length < 4) return b.length > 0 && looksLikeText(b) ? "csv" : "unknown";
  if (startsWith(b, [0xff, 0xd8, 0xff])) return "jpeg";
  if (startsWith(b, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return "png";
  if (ascii(b, 0, 4) === "RIFF" && ascii(b, 8, 4) === "WEBP") return "webp";
  if (ascii(b, 0, 6) === "GIF87a" || ascii(b, 0, 6) === "GIF89a") return "gif";
  // PDF 规格允许 %PDF- 前面有一点别的东西（1024 字以内）
  if (containsAscii(b.subarray(0, 1024), "%PDF-")) return "pdf";
  if (ascii(b, 4, 4) === "ftyp") {
    return HEIF_BRANDS.has(ascii(b, 8, 4)) ? "heic" : "unknown"; // HEIC / AVIF / MP4……都不收
  }
  if (startsWith(b, [0x50, 0x4b, 0x03, 0x04])) {
    // zip（docx / ods / 普通 zip 也是）：只看 zip 里的档名，不在整个档案里搜 "xl/"
    // （压缩过的资料、照片里随便都会出现这三个字，大的 Word 档会被当成 Excel）
    return isXlsxZip(b) ? "xlsx" : "unknown";
  }
  if (startsWith(b, [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1])) return "xls"; // OLE2（旧 Excel）
  return looksLikeText(b) ? "csv" : "unknown";
}

/** 录音的格式（语音下单）：看魔术字节，不信档名。回传副档名和 MIME；不认得 → null */
export function sniffAudio(b: Uint8Array): { ext: "wav" | "ogg" | "m4a" | "webm" | "mp3"; mime: string } | null {
  if (b.length < 12) return null;
  if (ascii(b, 0, 4) === "RIFF" && ascii(b, 8, 4) === "WAVE") return { ext: "wav", mime: "audio/wav" };
  if (ascii(b, 0, 4) === "OggS") return { ext: "ogg", mime: "audio/ogg" };
  if (ascii(b, 4, 4) === "ftyp" && !HEIF_BRANDS.has(ascii(b, 8, 4))) return { ext: "m4a", mime: "audio/mp4" };
  if (startsWith(b, [0x1a, 0x45, 0xdf, 0xa3])) return { ext: "webm", mime: "audio/webm" };
  if (ascii(b, 0, 3) === "ID3" || (b[0] === 0xff && (b[1] & 0xe0) === 0xe0)) return { ext: "mp3", mime: "audio/mpeg" };
  return null;
}
