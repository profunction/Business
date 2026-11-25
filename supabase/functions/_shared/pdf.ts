// PDF 有几页（分段给 Claude 用）。不是完整的 PDF 解析器：找页面树根节点的 /Count
// （PDF 1.5 以后常常放在压缩过的物件流 /ObjStm 里，解开再找）、linearized 的 /N，都没有就数 /Type /Page。
// 数不出来 → null（整份一次给 Claude）。分段的最后一段一定是「到最后一页」，所以少算不会漏掉页面。

const latin1 = new TextDecoder("latin1");

/** 物件流解压后合计最多看多少字（防 zip 炸弹那种） */
const MAX_INFLATED = 8 * 1024 * 1024;
const MAX_PAGES = 2000;

/** i 所在的那个字典 << ... >>（往前往后最多看 limit 个字；找不到就回传附近一段） */
function enclosingDict(t: string, i: number, limit = 4000): string {
  let depth = 0;
  let s = i;
  const stopS = Math.max(0, i - limit);
  for (; s > stopS + 1; s--) {
    if (t[s - 1] === ">" && t[s - 2] === ">") {
      depth++;
      s--;
    } else if (t[s - 1] === "<" && t[s - 2] === "<") {
      if (depth === 0) {
        s -= 2;
        break;
      }
      depth--;
      s--;
    }
  }
  let e = i;
  depth = 0;
  const stopE = Math.min(t.length - 1, i + limit);
  for (; e < stopE; e++) {
    if (t[e] === "<" && t[e + 1] === "<") {
      depth++;
      e++;
    } else if (t[e] === ">" && t[e + 1] === ">") {
      if (depth === 0) {
        e += 2;
        break;
      }
      depth--;
      e++;
    }
  }
  return t.slice(s, e);
}

/** 一段 PDF 文字里的页数线索：页面树节点 /Count 的最大值（= 根节点）；没有 → 0 */
function treeCount(t: string): number {
  let best = 0;
  for (const m of t.matchAll(/\/Type\s*\/Pages(?![A-Za-z])/g)) {
    const c = /\/Count\s+(\d+)/.exec(enclosingDict(t, m.index));
    if (c) best = Math.max(best, Number(c[1]));
  }
  return best;
}

function pageObjects(t: string): number {
  return [...t.matchAll(/\/Type\s*\/Page(?![A-Za-z])/g)].length;
}

/** FlateDecode 的物件流解开（最多 budget 个字）；解不开 → null */
async function inflate(data: Uint8Array, budget: number): Promise<Uint8Array | null> {
  try {
    const stream = new Blob([data as Uint8Array<ArrayBuffer>]).stream().pipeThrough(new DecompressionStream("deflate"));
    const reader = stream.getReader();
    const parts: Uint8Array[] = [];
    let n = 0;
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      n += value.length;
      if (n > budget) {
        await reader.cancel().catch(() => {});
        break;
      }
      parts.push(value);
    }
    const out = new Uint8Array(Math.min(n, budget));
    let o = 0;
    for (const p of parts) {
      out.set(p.subarray(0, out.length - o), o);
      o += p.length;
      if (o >= out.length) break;
    }
    return out;
  } catch {
    return null;
  }
}

/** 物件流（/Type /ObjStm、/FlateDecode）解开后的文字 */
async function objectStreams(bytes: Uint8Array, t: string): Promise<string[]> {
  const out: string[] = [];
  let budget = MAX_INFLATED;
  for (const m of t.matchAll(/\/Type\s*\/ObjStm(?![A-Za-z])/g)) {
    if (budget <= 0) break;
    const dict = enclosingDict(t, m.index);
    if (!/\/Filter\s*\/FlateDecode/.test(dict) || /\/DecodeParms/.test(dict)) continue;
    const kw = t.indexOf("stream", m.index);
    if (kw < 0) continue;
    let start = kw + "stream".length;
    if (t[start] === "\r") start++;
    if (t[start] === "\n") start++;
    const len = /\/Length\s+(\d+)(?!\s+\d+\s+R)/.exec(dict);
    let end = len ? start + Number(len[1]) : t.indexOf("endstream", start);
    if (end < start || end > bytes.length) end = t.indexOf("endstream", start);
    if (end < start) continue;
    const data = await inflate(bytes.subarray(start, end), budget);
    if (!data) continue;
    budget -= data.length;
    out.push(latin1.decode(data));
  }
  return out;
}

/** PDF 有几页；数不出来 → null */
export async function pdfPageCount(bytes: Uint8Array): Promise<number | null> {
  const t = latin1.decode(bytes);
  const ok = (n: number) => (n >= 1 && n <= MAX_PAGES ? n : null);
  const linearized = /\/Linearized\s[^>]*?\/N\s+(\d+)/.exec(t.slice(0, 2048));
  let n = treeCount(t);
  if (n) return ok(n);
  const streams = await objectStreams(bytes, t);
  for (const s of streams) n = Math.max(n, treeCount(s));
  if (n) return ok(n);
  if (linearized) return ok(Number(linearized[1]));
  n = pageObjects(t) + streams.reduce((k, s) => k + pageObjects(s), 0);
  return n ? ok(n) : null;
}

export interface PageRange {
  /** 第几页开始（1 起算） */
  from: number;
  /** 到第几页；null = 到最后一页（页数可能算少） */
  to: number | null;
  /** 估计的最后一页（切两半用） */
  last: number;
}

/** 每段最多 perCall 页；最后一段「到最后一页」。页数不知道或只有一段 → 一段（null） */
export function pageRanges(pages: number | null, perCall: number): PageRange[] | null {
  if (!pages || pages <= perCall) return null;
  const out: PageRange[] = [];
  for (let from = 1; from <= pages; from += perCall) {
    const to = from + perCall - 1;
    out.push({ from, to: to >= pages ? null : to, last: pages });
  }
  return out;
}

/** max_tokens 时把一段页面切两半；只有一页 → null */
export function splitRange(r: PageRange): [PageRange, PageRange] | null {
  const end = r.to ?? r.last;
  if (end <= r.from) return null;
  const mid = Math.floor((r.from + end) / 2);
  return [{ from: r.from, to: mid, last: r.last }, { from: mid + 1, to: r.to, last: r.last }];
}
