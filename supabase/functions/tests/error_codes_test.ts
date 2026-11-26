// 价目表 AI 的错误代码：扫 Edge Function 的代码（和定时任务、App 自己写的），确认 App 的清单
// （packages/core/lib/src/price_list_errors.dart）一个都没漏。App 每个代码都有自己的三语说明（apps/mobile 的测试检查）。
import { assert, assertEquals } from "@std/assert";

const read = (p: string) => Deno.readTextFileSync(new URL(p, import.meta.url));
const codes = (text: string, re: RegExp) => [...text.matchAll(re)].map((m) => m[1]);
const literals = (text: string) => codes(text, /"([A-Z][A-Z0-9_]{2,})"/g);

function dartList(name: string): string[] {
  const src = read("../../../packages/core/lib/src/price_list_errors.dart");
  const start = src.indexOf(`const ${name} = [`);
  assert(start >= 0, name);
  const body = src.slice(start, src.indexOf("];", start));
  return codes(body, /'([A-Z_]+)'/g);
}

/** 写进 error_message 的代码 */
function importErrorCodes(): Set<string> {
  const index = read("../parse-price-list/index.ts");
  const out = new Set<string>();
  // new JobError("X")、new JobError(a ? "X" : "Y")
  for (const line of index.split("\n").filter((l) => l.includes("new JobError("))) {
    for (const c of literals(line)) out.add(c);
  }
  // errorCode()、shutdownCode() 回传的
  for (const fn of ["export function errorCode", "export function shutdownCode"]) {
    const at = index.indexOf(fn);
    assert(at >= 0, fn);
    for (const c of literals(index.slice(at, index.indexOf("\n}", at)))) out.add(c);
  }
  // SheetJS / zip 检查 / Claude SDK 的错误
  const sheet = read("../_shared/spreadsheet.ts");
  for (const c of literals(sheet.match(/export type SpreadsheetErrorCode =[^;]+;/)![0])) out.add(c);
  const zip = read("../_shared/zipguard.ts");
  for (const c of literals(zip.match(/public readonly code: [^,]+,/)![0])) out.add(c);
  const claude = read("../_shared/claude.ts");
  const at = claude.indexOf("export function classifyClaudeError");
  for (const c of literals(claude.slice(at, claude.indexOf("\n}", at)))) out.add(c);
  // 定时任务 fail_stuck_price_list_imports、App 自己写的（price_list_imports_guard 允许的）
  const sql = read("../../migrations/20261127000200_seller_hardening.sql");
  for (const c of codes(sql, /'(AI_TIMEOUT|START_FAILED)'/g)) out.add(c);
  for (const c of codes(sql.match(/not in \('START_FAILED', 'NETWORK', 'AUTH'\)/)![0], /'([A-Z_]+)'/g)) out.add(c);
  out.delete("ABORTED"); // 别段失败时中止用的，不会写进 error_message
  return out;
}

/** HTTP 回应 {"error": "X"} */
function httpErrorCodes(): Set<string> {
  const index = read("../parse-price-list/index.ts");
  const out = new Set(codes(index, /error: "([A-Z_]+)"/g));
  // json({ error: e instanceof DbError ? "DB_ERROR" : "INTERNAL_ERROR" }, 500)
  for (const line of index.split("\n").filter((l) => /json\(\{ error: e instanceof/.test(l))) {
    for (const c of literals(line)) out.add(c);
  }
  return out;
}

Deno.test("价目表：每一个写进 error_message 的代码 App 都有", () => {
  const found = importErrorCodes();
  const app = new Set(dartList("priceListImportErrorCodes"));
  assertEquals([...found].filter((c) => !app.has(c)).sort(), [], "App 的清单漏了");
  assertEquals([...app].filter((c) => !found.has(c)).sort(), [], "App 的清单多了（Edge 已经不用）");
  assert(found.size >= 25, `${found.size}`);
});

Deno.test("价目表：每一个 HTTP 错误代码 App 都有", () => {
  const found = httpErrorCodes();
  const app = new Set(dartList("priceListHttpErrorCodes"));
  assertEquals([...found].filter((c) => !app.has(c)).sort(), [], "App 的清单漏了");
  assertEquals([...app].filter((c) => !found.has(c)).sort(), [], "App 的清单多了");
  for (const c of ["INVALID_IMPORT_ID", "UNAUTHORIZED", "TOO_MANY_IMPORTS", "QUOTA_UNAVAILABLE", "CONFIG_MISSING"]) {
    assert(found.has(c), c);
  }
});
