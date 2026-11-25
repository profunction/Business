// 部署：每个函数用 deno task bundle 照 deno.lock 打包好的 _dist/<函数>/index.js（config.toml 的 entrypoint），
// 部署工具不会再解析套件版本。各函数目录的 deno.json 也检查：用到的套件都有写、版本跟根目录的一样。

import { assert, assertEquals } from "@std/assert";
import { bundleArgs, DIST, FUNCTIONS, unpinnedImports } from "../bundle.ts";

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

Deno.test("deno.lock：frozen；直接用到的套件、间接用到的 npm 套件和 SheetJS 档案都有 hash；各函数目录没有 lock 档", async () => {
  const cfg = JSON.parse(await Deno.readTextFile(new URL("deno.json", root)));
  assertEquals(cfg.lock, { path: "./deno.lock", frozen: true });
  const lock = JSON.parse(await Deno.readTextFile(new URL("deno.lock", root)));
  const map = await imports("deno.json");
  for (const [k, v] of Object.entries(map)) {
    if (v.startsWith("https://")) {
      assert(/^[0-9a-f]{64}$/.test(lock.remote?.[v] ?? ""), `remote hash for ${k}`);
      continue;
    }
    const spec = v.replace(/\/[^@]*$/, ""); // jsr:@std/encoding@1.0.11/base64 → jsr:@std/encoding@1.0.11
    const version = spec.slice(spec.lastIndexOf("@") + 1);
    assertEquals(lock.specifiers?.[spec], version, `${k} pinned in deno.lock`);
  }
  // 间接依赖（例如 @anthropic-ai/sdk 的 @opentelemetry/api、standardwebhooks）也锁住、有 integrity
  const npm = Object.entries(lock.npm ?? {}) as [string, { integrity?: string }][];
  for (const name of ["@opentelemetry/api", "standardwebhooks", "json-schema-to-ts", "iceberg-js"]) {
    assert(npm.some(([k]) => k.startsWith(`${name}@`)), `${name} locked`);
  }
  for (const [k, v] of npm) assert(/^sha512-/.test(v.integrity ?? ""), `${k} integrity`);
  for (const [k, v] of Object.entries(lock.jsr ?? {}) as [string, { integrity?: string }][]) {
    assert(/^[0-9a-f]{64}$/.test(v.integrity ?? ""), `${k} integrity`);
  }
  // 部署用各函数自己的 deno.json：那里不能有 lock 档（新格式 edge-runtime 读不懂），也不能指到这一份
  for (const fn of ["dispatch-notifications", "whatsapp-webhook", "parse-price-list"]) {
    const fnCfg = JSON.parse(await Deno.readTextFile(new URL(`${fn}/deno.json`, root)));
    assert(!("lock" in fnCfg), `${fn}/deno.json must not configure a lockfile`);
    let exists = true;
    try {
      await Deno.stat(new URL(`${fn}/deno.lock`, root));
    } catch {
      exists = false;
    }
    assert(!exists, `${fn}/deno.lock must not exist`);
  }
});

Deno.test("部署的是照 frozen lock 打包好的单一档案：config.toml 的 entrypoint 指到 _dist、打包用根目录的 deno.json + --frozen-lockfile", async () => {
  const toml = await Deno.readTextFile(new URL("../config.toml", root));
  for (const fn of FUNCTIONS) {
    const section = toml.split(`[functions.${fn}]`)[1]?.split(/\n\[/)[0] ?? "";
    assert(section.includes("verify_jwt = false"), `${fn}: verify_jwt`);
    assert(
      section.includes(`entrypoint = "./functions/${DIST}/${fn}/index.js"`),
      `${fn}: entrypoint must be the bundle`,
    );
    const args = bundleArgs(fn);
    assert(args.includes("--frozen-lockfile"), "bundle must use the frozen lock");
    assertEquals(args[args.indexOf("--config") + 1], "deno.json");
    assertEquals(args.slice(-3), ["-o", `${DIST}/${fn}/index.js`, `${fn}/index.ts`]);
  }
  const cfg = JSON.parse(await Deno.readTextFile(new URL("deno.json", root)));
  assert(String(cfg.tasks.bundle).includes("bundle.ts"));
  assert(String(cfg.tasks.deploy).startsWith("deno task bundle && "), "deploy must bundle first");
  for (const fn of FUNCTIONS) assert(String(cfg.tasks.deploy).includes(fn), `deploy ${fn}`);
  assert((cfg.exclude ?? []).includes(`${DIST}/`), "bundles are not linted / formatted");
  assert((await Deno.readTextFile(new URL(".gitignore", root))).includes(`${DIST}/`), "bundles are not committed");
});

Deno.test("打包的档案只能 import node: 内建模组（其他的部署时会重新解析）", async () => {
  assertEquals(
    unpinnedImports([
      'import * as fs from "node:fs";',
      'import { once } from "node:events";',
      'export * from "node:path";',
      'const x = await import("node:fs/promises");',
      ' * import AsyncStorage from "@react-native-async-storage/async-storage";', // 注解
      'import Anthropic from "npm:@anthropic-ai/sdk@1.13.0";',
      'import "https://cdn.sheetjs.com/xlsx-0.20.3/package/xlsx.mjs";',
      'export { a } from "jsr:@std/encoding@1.0.11";',
      'const y = await import("xlsx");',
      'import { b } from "./chunk-1.js";',
    ].join("\n")),
    [
      "npm:@anthropic-ai/sdk@1.13.0",
      "https://cdn.sheetjs.com/xlsx-0.20.3/package/xlsx.mjs",
      "./chunk-1.js",
      "jsr:@std/encoding@1.0.11",
      "xlsx",
    ],
  );
  // 本机打包过的话也检查打包出来的档案
  for (const fn of FUNCTIONS) {
    let src: string;
    try {
      src = await Deno.readTextFile(new URL(`${DIST}/${fn}/index.js`, root));
    } catch {
      continue;
    }
    assertEquals(unpinnedImports(src), [], `${DIST}/${fn}/index.js`);
  }
});
