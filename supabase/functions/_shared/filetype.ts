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
    // zip：要有 xl/ 才是 Excel（docx / ods 之类的也是 zip）
    return containsAscii(b, "[Content_Types].xml") && containsAscii(b, "xl/") ? "xlsx" : "unknown";
  }
  if (startsWith(b, [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1])) return "xls"; // OLE2（旧 Excel）
  return looksLikeText(b) ? "csv" : "unknown";
}
