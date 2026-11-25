// 部署时每个函数用自己目录的 deno.json：检查它有用到的套件都有写、版本跟根目录（本机测试用）的一样。

import { assert, assertEquals } from "@std/assert";

const root = new URL("../", import.meta.url);

async function imports(path: string): Promise<Record<string, string>> {
  const cfg = JSON.parse(await Deno.readTextFile(new URL(path, root)));
  return cfg.imports ?? {};
}

/** 从入口开始，沿着相对路径 import 找出所有用到的「裸」套件名 */
async function bareSpecifiers(entry: URL): Promise<Set<string>> {
  const seen = new Set<string>();
  const bare = new Set<string>();
  const walk = async (file: URL) => {
    if (seen.has(file.href)) return;
    seen.add(file.href);
    const src = await Deno.readTextFile(file);
    for (const m of src.matchAll(/(?:from|import)\s+["']([^"']+)["']/g)) {
      const spec = m[1];
      if (spec.startsWith(".")) await walk(new URL(spec, file));
      else if (!/^(npm|jsr|node|https?):/.test(spec)) bare.add(spec);
    }
  };
  await walk(entry);
  return bare;
}

for (const fn of ["dispatch-notifications", "whatsapp-webhook", "parse-price-list"]) {
  Deno.test(`${fn}/deno.json：用到的套件都有，版本跟根目录一样`, async () => {
    const rootMap = await imports("deno.json");
    const fnMap = await imports(`${fn}/deno.json`);
    for (const [k, v] of Object.entries(fnMap)) assertEquals(v, rootMap[k], `${fn}: ${k}`);
    for (const spec of await bareSpecifiers(new URL(`${fn}/index.ts`, root))) {
      assert(spec in fnMap, `${fn}/deno.json is missing "${spec}"`);
    }
  });
}

Deno.test("版本都钉死（不用 ^ / latest）；SheetJS 是 0.20.3（npm 的 xlsx 有漏洞）", async () => {
  const map = await imports("deno.json");
  for (const [k, v] of Object.entries(map)) {
    assert(!/[\^~*]|@latest/.test(v), `${k} -> ${v}`);
    if (v.startsWith("npm:") || v.startsWith("jsr:")) assert(/@\d+\.\d+\.\d+/.test(v), `${k} -> ${v}`);
  }
  assertEquals(map["xlsx"], "https://cdn.sheetjs.com/xlsx-0.20.3/package/xlsx.mjs");
  assertEquals(map["@anthropic-ai/sdk"], "npm:@anthropic-ai/sdk@1.13.0");
});
