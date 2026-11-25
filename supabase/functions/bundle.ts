// 部署用的档案：每个函数在本机照 deno.lock（frozen，有 integrity hash）打包成一个 JS 档 _dist/<函数>/index.js，
// config.toml 的 entrypoint 指到这里。部署工具（supabase functions deploy，不管用 Docker 还是 --use-api）
// 只看到一个没有 npm: / jsr: / https: import 的档案，不会在部署时重新解析间接用到的套件
// （例如 @anthropic-ai/sdk 的 standardwebhooks、json-schema-to-ts 是 ^ 范围，部署时会拿到刚发布的版本）。
//
//   deno task bundle          打包 + 检查（只剩 node: 内建模组、载入得了、有 default.fetch）
//   deno task deploy          打包之后部署三个函数

export const FUNCTIONS = ["dispatch-notifications", "whatsapp-webhook", "parse-price-list"] as const;
export const DIST = "_dist";

/** 打包的指令（照 deno.json 的 frozen lock；lock 对不上就失败） */
export function bundleArgs(fn: string): string[] {
  return [
    "bundle",
    "--config",
    "deno.json",
    "--frozen-lockfile",
    "--platform=deno",
    "--allow-import=cdn.sheetjs.com,jsr.io,registry.npmjs.org",
    "-o",
    `${DIST}/${fn}/index.js`,
    `${fn}/index.ts`,
  ];
}

/** 打包出来的档案还 import 了什么（静态、动态、export from）；只能是 node: 内建模组 */
export function bundleImports(src: string): string[] {
  const out = new Set<string>();
  const patterns = [
    /^\s*import\s+(?:[^'"`;]*?\s+from\s+)?["']([^"']+)["']/gm,
    /^\s*export\s+(?:\*|\{[^}]*\})\s+from\s+["']([^"']+)["']/gm,
    /\bimport\(\s*["']([^"']+)["']\s*\)/g,
  ];
  for (const re of patterns) for (const m of src.matchAll(re)) out.add(m[1]);
  return [...out];
}

/** 不是 node: 内建模组的 import（部署时会被重新解析的） */
export function unpinnedImports(src: string): string[] {
  return bundleImports(src).filter((s) => !/^node:[a-z_/]+$/.test(s));
}

async function main() {
  for (const fn of FUNCTIONS) {
    const out = await new Deno.Command(Deno.execPath(), { args: bundleArgs(fn), stdout: "inherit", stderr: "inherit" })
      .output();
    if (!out.success) throw new Error(`bundle ${fn} failed`);
    const path = `${DIST}/${fn}/index.js`;
    const src = await Deno.readTextFile(path);
    const bad = unpinnedImports(src);
    if (bad.length) throw new Error(`${path} still imports ${bad.join(", ")}`);
    const mod = await import(new URL(path, `file://${Deno.cwd()}/`).href);
    if (typeof mod.default?.fetch !== "function") throw new Error(`${path} has no default.fetch`);
    console.log(`ok ${path} (${(src.length / 1024).toFixed(0)} KB)`);
  }
}

if (import.meta.main) {
  await main();
  // parse-price-list 载入时会挂 beforeunload；检查完就结束
  Deno.exit(0);
}
