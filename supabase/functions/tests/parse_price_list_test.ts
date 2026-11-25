import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import Anthropic from "@anthropic-ai/sdk";
import fn, {
  checkPlan,
  errorCode,
  handleShutdown,
  isolate,
  jobDeadline,
  JobError,
  PDF_PAGES_PER_CALL,
  shutdownCode,
  storagePath,
  TIMING,
} from "../parse-price-list/index.ts";
import { QUOTA } from "../parse-price-list/quota.ts";
import { pageRanges, pdfPageCount, splitRange } from "../_shared/pdf.ts";
import { DEFAULT_CHUNK, SpreadsheetError } from "../_shared/spreadsheet.ts";
import { DbError } from "../_shared/supabase.ts";
import { ConfigError } from "../_shared/env.ts";
import {
  type Call,
  claudeStream,
  delayed,
  extractionJson,
  fakeEdgeRuntime,
  fakeFetch,
  hang,
  isAnthropic,
  isService,
  PUBLISHABLE,
  rpcName,
  SB_URL,
  setEnv,
  SUPABASE_ENV,
  waitFor,
} from "./_helpers.ts";
import { bombEntries, makeWorkbook, zipFiles } from "./_sheets.ts";

const W = "aaaaaaaa-0000-4000-8000-000000000001";
const OTHER_W = "bbbbbbbb-0000-4000-8000-000000000002";
const IMP = "cccccccc-0000-4000-8000-000000000003";
const USER_JWT = "user.jwt.token";
const URL_ = `${SB_URL}/functions/v1/parse-price-list`;
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, ...new Array(60).fill(1)]);

interface ImportRow {
  id: string;
  wholesaler_id: string;
  file_path: string;
  file_type: string;
  status: string;
  error_message: string | null;
  ai_raw: Record<string, unknown> | null;
}

interface State {
  imp: ImportRow;
  visible: boolean;
  files: Record<string, Uint8Array>;
  rows: Record<string, unknown>[];
  suggestCalls: unknown[];
  claude: (c: Call, n: number) => Response | Promise<Response>;
  claudeCalls: Record<string, unknown>[];
  deletes: number;
  /** 写进去过几行（就算之后被删掉） */
  inserted: number;
  /** suggest_import_matches 回 500 */
  suggestError?: boolean;
  /** wholesalers.status（服务器身份读） */
  wholesalerStatus: string;
  /** Storage 里 _runs/ 的用量记录：路径 → 内容 */
  runs: Map<string, string>;
  /** Storage 的 list / upload 回 500 */
  storageDown?: boolean;
  /** 这时候 PostgREST 全部回 503（数据库暂时连不上） */
  restDown?: (c: Call) => boolean;
}

/** 假的 Supabase（Auth、PostgREST、Storage）+ Anthropic */
function backend(s: State) {
  return (c: Call): Response | Promise<Response> | undefined => {
    const p = c.url.pathname;
    if (isAnthropic(c)) {
      s.claudeCalls.push(c.json());
      return s.claude(c, s.claudeCalls.length);
    }
    if (c.url.origin !== SB_URL) return undefined;
    if (p.startsWith("/rest/v1/") && s.restDown?.(c)) {
      return Response.json({ message: "upstream unavailable", code: "" }, { status: 503 });
    }
    if (p === "/rest/v1/wholesalers" && c.method === "GET") {
      assert(isService(c)); // 批发商的状态用服务器身份读（批发商自己改不了）
      return Response.json(c.url.searchParams.get("id") === `eq.${W}` ? [{ status: s.wholesalerStatus }] : []);
    }
    if (p === "/storage/v1/object/list/price-lists") {
      assert(isService(c));
      if (s.storageDown) {
        return Response.json({ statusCode: "500", error: "x", message: "storage down" }, { status: 500 });
      }
      const prefix = `${c.json().prefix}/`;
      const names = [...s.runs.keys()].filter((k) => k.startsWith(prefix)).map((k) => k.slice(prefix.length));
      names.sort().reverse();
      return Response.json(names.map((name) => ({ name, id: name, created_at: new Date().toISOString() })));
    }
    if (p === "/storage/v1/object/price-lists" && c.method === "DELETE") {
      assert(isService(c));
      for (const k of c.json().prefixes as string[]) s.runs.delete(k);
      return Response.json([]);
    }
    if (p.startsWith("/storage/v1/object/price-lists/_runs/") && c.method === "POST") {
      assert(isService(c));
      if (s.storageDown) {
        return Response.json({ statusCode: "500", error: "x", message: "storage down" }, { status: 500 });
      }
      const key = decodeURIComponent(p.slice("/storage/v1/object/price-lists/".length));
      assertEquals(c.headers.get("x-upsert"), "false");
      s.runs.set(key, c.text);
      return Response.json({ Id: key, Key: `price-lists/${key}` });
    }
    if (p === "/auth/v1/user") {
      if (c.headers.get("authorization") !== `Bearer ${USER_JWT}`) {
        return Response.json({ code: 401, error_code: "bad_jwt", msg: "invalid JWT" }, { status: 401 });
      }
      return Response.json({ id: "user-1", aud: "authenticated", role: "authenticated", email: "w@x.my" });
    }
    if (p === "/rest/v1/price_list_imports" && c.method === "GET") {
      // 用户身份：publishable key + 用户 JWT；RLS 只看得到自己的
      assertEquals(c.headers.get("apikey"), PUBLISHABLE);
      assertEquals(c.headers.get("authorization"), `Bearer ${USER_JWT}`);
      const id = c.url.searchParams.get("id");
      return Response.json(s.visible && id === `eq.${s.imp.id}` ? [{ ...s.imp }] : []);
    }
    if (p === "/rest/v1/price_list_imports" && c.method === "PATCH") {
      assert(isService(c));
      const q = c.url.searchParams;
      if (q.get("id") !== `eq.${s.imp.id}`) return Response.json([]);
      if (q.get("status") && q.get("status") !== `eq.${s.imp.status}`) return Response.json([]);
      if (q.get("or")) {
        // 占位：ai_raw 是空的，或 claimed_at 太旧
        const m = /ai_raw->>claimed_at\.lt\."([^"]+)"/.exec(q.get("or")!);
        const claimedAt = s.imp.ai_raw?.claimed_at as string | undefined;
        if (s.imp.ai_raw && !(claimedAt && m && claimedAt < m[1])) return Response.json([]);
      }
      const runFilter = q.get("ai_raw->>run_id");
      if (runFilter && runFilter !== `eq.${s.imp.ai_raw?.run_id}`) return Response.json([]);
      Object.assign(s.imp, c.json());
      return Response.json([{ id: s.imp.id }]);
    }
    if (p === "/rest/v1/price_list_import_rows" && c.method === "DELETE") {
      assert(isService(c));
      s.rows = [];
      s.deletes++;
      return new Response(null, { status: 204 });
    }
    if (p === "/rest/v1/price_list_import_rows" && c.method === "POST") {
      assert(isService(c));
      s.rows.push(...c.json());
      s.inserted += c.json().length;
      return new Response(null, { status: 201 });
    }
    if (rpcName(c) === "suggest_import_matches") {
      assert(isService(c));
      s.suggestCalls.push(c.json());
      if (s.suggestError) return Response.json({ message: "boom", code: "XX000" }, { status: 500 });
      return Response.json({ rows: s.rows.length, matched: 1, suggested: 2 });
    }
    if (p.startsWith("/storage/v1/object/price-lists/") && c.method === "GET") {
      assert(isService(c));
      const key = decodeURIComponent(p.slice("/storage/v1/object/price-lists/".length));
      const f = s.files[key];
      if (!f) {
        return Response.json({ statusCode: "404", error: "not_found", message: "Object not found" }, { status: 400 });
      }
      return new Response(f as Uint8Array<ArrayBuffer>, { headers: { "content-type": "application/octet-stream" } });
    }
    return undefined;
  };
}

function setup(over: Partial<State> = {}, env: Record<string, string | undefined> = {}) {
  const s: State = {
    imp: {
      id: IMP,
      wholesaler_id: W,
      file_path: `${W}/list.png`, // 档名说 png，其实是 jpeg：照魔术字节
      file_type: "image",
      status: "processing",
      error_message: null,
      ai_raw: null,
    },
    visible: true,
    files: { [`${W}/list.png`]: JPEG },
    rows: [],
    suggestCalls: [],
    claudeCalls: [],
    deletes: 0,
    inserted: 0,
    wholesalerStatus: "active",
    runs: new Map(),
    claude: () =>
      claudeStream({
        blocks: [{ type: "thinking" }, {
          type: "text",
          text: extractionJson(
            [
              { name: "16oz PP cup", source_ref: "p1 line 3" },
              { name: "95mm flat lid", unit: "CARTON", price_sen: 4000, pack_qty: 1000, source_ref: "p1 line 7" },
            ],
            [{ raw_text: "??? 8oz RM?.50", source_ref: "p1 line 5", reason: "blurred" }],
          ),
        }],
      }),
    ...over,
  };
  const restoreEnv = setEnv({
    ...SUPABASE_ENV,
    ANTHROPIC_API_KEY: "sk-ant-test",
    PRICE_LIST_TIME_BUDGET_MS: undefined,
    ...env,
  });
  const net = fakeFetch(backend(s));
  return {
    s,
    net,
    restore: () => {
      net.restore();
      restoreEnv();
    },
  };
}

const call = (body: unknown = { import_id: IMP }, auth: string | null = `Bearer ${USER_JWT}`) =>
  fn.fetch(
    new Request(URL_, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: PUBLISHABLE, ...(auth ? { Authorization: auth } : {}) },
      body: JSON.stringify(body),
    }),
  );

Deno.test("parse-price-list：身份、参数、找不到、状态不对、已经在跑", async () => {
  const t = setup();
  try {
    const opt = await fn.fetch(new Request(URL_, { method: "OPTIONS" }));
    assertEquals(opt.status, 204);
    assertEquals(opt.headers.get("access-control-allow-origin"), "*");
    assertEquals((await call(undefined, null)).status, 401);
    assertEquals((await call(undefined, "Bearer someone.else")).status, 401);
    const bad = await call({ import_id: "../../etc" });
    assertEquals([bad.status, (await bad.json()).error], [400, "INVALID_IMPORT_ID"]);
    t.s.visible = false; // RLS：别家的 import 看不到
    const nf = await call();
    assertEquals([nf.status, (await nf.json()).error], [404, "IMPORT_NOT_FOUND"]);
    t.s.visible = true;
    t.s.imp.status = "review";
    const conflict = await call();
    assertEquals([conflict.status, await conflict.json()], [409, { error: "IMPORT_NOT_PROCESSING", status: "review" }]);
    t.s.imp.status = "processing";
    t.s.imp.ai_raw = { state: "running", run_id: "other", claimed_at: new Date().toISOString() };
    const running = await call();
    assertEquals([running.status, (await running.json()).error], [409, "IMPORT_ALREADY_RUNNING"]);
    assertEquals(t.s.claudeCalls.length, 0);
  } finally {
    t.restore();
  }
});

Deno.test("parse-price-list：照片 → 202，背景跑 Claude → 写行（看不清的 = skip）→ suggest_import_matches → review", async () => {
  const t = setup();
  const rt = fakeEdgeRuntime();
  try {
    const res = await call();
    assertEquals(res.status, 202);
    assertEquals(await res.json(), { import_id: IMP, status: "processing" });
    assertEquals(res.headers.get("access-control-allow-origin"), "*");
    assertEquals(rt.pending.length, 1);
    assertEquals(t.s.imp.ai_raw?.state, "running"); // 先占位才回 202
    await Promise.all(rt.pending);

    assertEquals(t.net.unexpected, []);
    assertEquals(t.s.imp.status, "review");
    assertEquals(t.s.imp.error_message, null);
    // Claude 收到的是 jpeg（档名 .png 不算数）
    const content = (t.s.claudeCalls[0].messages as { content: Record<string, unknown>[] }[])[0].content;
    assertEquals((content[1].source as Record<string, unknown>).media_type, "image/jpeg");
    // 照原本的位置排：line 3、line 5（看不清）、line 7
    assertEquals(t.s.rows.map((r) => [r.row_no, r.name, r.action]), [
      [1, "16oz PP cup", "create"],
      [2, null, "skip"],
      [3, "95mm flat lid", "create"],
    ]);
    assertEquals(t.s.rows[1], {
      import_id: IMP,
      row_no: 2,
      raw_text: "??? 8oz RM?.50",
      name: null,
      unit: null,
      pack_qty: null,
      price_sen: null,
      min_order_qty: null,
      confidence: null,
      action: "skip",
    });
    assertEquals([t.s.rows[2].unit, t.s.rows[2].price_sen, t.s.rows[2].confidence], ["carton", 4000, 0.95]);
    assertEquals(t.s.suggestCalls, [{ p_import_id: IMP }]);
    const ai = t.s.imp.ai_raw!;
    assertEquals(ai.state, "done");
    assertEquals((ai.file as Record<string, unknown>).kind, "jpeg");
    assertEquals((ai.document as Record<string, unknown>).supplier_name, "JB Packaging Supply");
    assertEquals((ai.rows as Record<string, unknown>[])[1], {
      row_no: 2,
      source_ref: "p1 line 5",
      unreadable_reason: "blurred",
    });
    assertEquals((ai.outputs as unknown[]).length, 1);
    assertEquals((ai.calls as Record<string, unknown>[])[0].outcome, "ok");
  } finally {
    rt.restore();
    t.restore();
  }
});

/** 假的 Claude：读请求里的 Excel 行，每一行回一样商品（raw_text 留空，让函数自己补）；太多行就 max_tokens */
function sheetClaude(maxLines: number) {
  return (c: Call): Response => {
    const text = (c.json().messages[0].content[0] as { text: string }).text;
    const lines = [...text.matchAll(/^(?!\[context\])(\S+!R\d+): (.*)$/gm)];
    if (lines.length > maxLines) {
      return claudeStream({ blocks: [{ type: "text", text: '{"rows":[' }], stopReason: "max_tokens" });
    }
    const products = lines.filter((m) => /\d/.test(m[2].split(" | ")[0] ?? ""));
    return claudeStream({
      blocks: [{
        type: "text",
        text: extractionJson(
          products.map((m) => ({ name: m[2].split(" | ")[1], source_ref: m[1], raw_text: "", unit: "Pack" })),
        ),
      }],
    });
  };
}

Deno.test("parse-price-list：Excel → 分段给 Claude、max_tokens 切两半再试、raw_text 用原文补（没有 EdgeRuntime 就等做完）", async () => {
  const csv = "No,Item,Unit,Price\n" +
    Array.from({ length: 150 }, (_, i) => `${i + 1},item ${i + 1},pkt,${i + 1}.00`).join("\n");
  const t = setup({ claude: sheetClaude(30) });
  t.s.imp.file_path = `price-lists/${W}/list.csv`; // 前面多了 bucket 名字也接受
  t.s.files = { [`${W}/list.csv`]: new TextEncoder().encode(csv) };
  try {
    const res = await call();
    assertEquals(res.status, 202);
    assertEquals(t.s.imp.status, "review");
    assertEquals(t.s.rows.length, 150);
    assertEquals(t.s.rows.map((r) => r.row_no), Array.from({ length: 150 }, (_, i) => i + 1));
    assertEquals(t.s.rows.map((r) => r.name), Array.from({ length: 150 }, (_, i) => `item ${i + 1}`)); // 顺序照表
    assertEquals(t.s.rows[0].raw_text, "1 | item 1 | pkt | 1.00");
    assertEquals(t.s.rows[0].unit, "pack");
    // 150 行 → 3 段（各 50 行）；每段 max_tokens → 切成 25 + 25
    const parts = (t.s.imp.ai_raw!.calls as Record<string, unknown>[]).map((c) => `${c.part}:${c.outcome}`).sort();
    assertEquals(
      parts,
      [1, 2, 3].flatMap((i) => [`part ${i}/3 (half):ok`, `part ${i}/3 (half):ok`, `part ${i}/3:max_tokens`]),
    );
    // 每段都有表头
    for (const call of t.s.claudeCalls) {
      const text = (call.messages as { content: { text: string }[] }[])[0].content[0].text;
      assertStringIncludes(text, "[context] Sheet1!R1: No | Item | Unit | Price");
    }
    assertEquals(t.s.imp.ai_raw!.file, { kind: "csv", bytes: csv.length, lines: 151, chunks: 3 });
  } finally {
    t.restore();
  }
});

Deno.test("parse-price-list：测试里做的 xlsx 也读得到", async () => {
  const t = setup({ claude: sheetClaude(100) });
  t.s.imp.file_path = `${W}/list.xlsx`;
  t.s.files = { [`${W}/list.xlsx`]: makeWorkbook("xlsx") };
  try {
    await call();
    assertEquals(t.s.imp.status, "review");
    assertEquals(t.s.rows.map((r) => r.name), ["16安士 PP杯 95口径", "95 平盖", "Straw 6mm / 8mm"]);
    assertEquals(t.s.rows[0].raw_text, "1 | 16安士 PP杯 95口径 | 箱 | RM85.50 | 5 ctn");
  } finally {
    t.restore();
  }
});

async function expectFailure(
  code: string,
  arrange: (t: ReturnType<typeof setup>) => void,
  env: Record<string, string | undefined> = {},
) {
  const t = setup({}, env);
  arrange(t);
  const rt = fakeEdgeRuntime();
  try {
    const res = await call();
    assertEquals(res.status, 202);
    await Promise.all(rt.pending);
    assertEquals([t.s.imp.status, t.s.imp.error_message], ["failed", code]);
    assertEquals(t.s.rows, []);
    assertEquals(t.s.imp.ai_raw?.state, "failed");
    assertEquals(t.s.imp.ai_raw?.error, code);
    assertEquals(t.net.unexpected, []);
    return t;
  } finally {
    rt.restore();
    t.restore();
  }
}

Deno.test("parse-price-list 失败：HEIC 不支持（不叫 Claude）", async () => {
  const t = await expectFailure("UNSUPPORTED_FILE", (t) => {
    t.s.files[`${W}/list.png`] = new TextEncoder().encode("\x00\x00\x00\x18ftypheic\x00\x00\x00\x00" + "x".repeat(40));
  });
  assertEquals(t.s.claudeCalls.length, 0);
});

Deno.test("parse-price-list 失败：Claude 拒绝 → AI_REFUSED", async () => {
  await expectFailure("AI_REFUSED", (t) => {
    t.s.claude = () =>
      claudeStream({
        blocks: [],
        stopReason: "refusal",
        stopDetails: { type: "refusal", category: "general_harms", explanation: null },
      });
  });
});

Deno.test("parse-price-list 失败：照片两次 max_tokens（第二次 effort low）→ AI_TRUNCATED", async () => {
  const t = await expectFailure("AI_TRUNCATED", (t) => {
    t.s.claude = () => claudeStream({ blocks: [{ type: "text", text: '{"rows":[' }], stopReason: "max_tokens" });
  });
  assertEquals(
    t.s.claudeCalls.map((c) => (c.output_config as Record<string, unknown>).effort),
    ["medium", "low"],
  );
});

Deno.test("parse-price-list 失败：别家批发商的档案路径 / 档案不存在 / 没设 Claude 钥匙 / AI 什么都没读到", async () => {
  await expectFailure("INVALID_FILE_PATH", (t) => {
    t.s.imp.file_path = `${OTHER_W}/list.png`;
    t.s.files[`${OTHER_W}/list.png`] = JPEG;
  });
  await expectFailure("INVALID_FILE_PATH", (t) => {
    t.s.imp.file_path = `${W}/../${OTHER_W}/list.png`;
  });
  await expectFailure("FILE_NOT_FOUND", (t) => {
    t.s.files = {};
  });
  await expectFailure("AI_NOT_CONFIGURED", () => {}, { ANTHROPIC_API_KEY: undefined });
  // 时间预算不够叫 Claude（免费方案可以设 PRICE_LIST_TIME_BUDGET_MS=140000）
  const slow = await expectFailure("AI_TIMEOUT", () => {}, { PRICE_LIST_TIME_BUDGET_MS: "30000" });
  assertEquals(slow.s.claudeCalls.length, 0);
  await expectFailure("NO_PRODUCTS_FOUND", (t) => {
    t.s.claude = () => claudeStream({ blocks: [{ type: "text", text: extractionJson([]) }] });
  });
  await expectFailure("AI_UNAVAILABLE", (t) => {
    t.s.claude = () =>
      Response.json({ type: "error", error: { type: "overloaded_error", message: "x" } }, { status: 529 });
  });
});

Deno.test("storagePath：只接受这家批发商的资料夹", () => {
  assertEquals(storagePath(`${W}/a.jpg`, W), `${W}/a.jpg`);
  assertEquals(storagePath(`/price-lists/${W}/a.jpg`, W), `${W}/a.jpg`);
  for (const bad of [`${OTHER_W}/a.jpg`, `${W}`, `${W}//a.jpg`, `${W}/./a.jpg`, "", "a.jpg"]) {
    let code = "";
    try {
      storagePath(bad, W);
    } catch (e) {
      code = (e as Error).message;
    }
    assertEquals(code, "INVALID_FILE_PATH", bad);
  }
});

/** 改 isolate.startedAt / TIMING，跑完还原 */
async function withTiming(
  over: { startedAt?: number; reserveMs?: number; minCallMs?: number },
  f: () => Promise<void>,
) {
  const before = { startedAt: isolate.startedAt, ...TIMING };
  if (over.startedAt !== undefined) isolate.startedAt = over.startedAt;
  if (over.reserveMs !== undefined) TIMING.reserveMs = over.reserveMs;
  if (over.minCallMs !== undefined) TIMING.minCallMs = over.minCallMs;
  try {
    await f();
  } finally {
    isolate.startedAt = before.startedAt;
    TIMING.reserveMs = before.reserveMs;
    TIMING.minCallMs = before.minCallMs;
  }
}

Deno.test("期限：从 worker 开始算（一个 worker 接很多个请求），不是从请求进来算", () => {
  assertEquals(jobDeadline(1_000_000, 380_000, 1_000_000), 1_380_000);
  assertEquals(jobDeadline(1_300_000, 380_000, 1_000_000), 1_380_000); // 300 秒后才进来：只剩 80 秒
  assertEquals(jobDeadline(1_300_000, 140_000, 1_250_000), 1_390_000);
});

Deno.test("parse-price-list 失败：worker 已经跑了很久，剩下的时间不够叫 Claude → AI_TIMEOUT（不会叫到一半被平台杀掉）", async () => {
  await withTiming({ startedAt: Date.now() - 370_000 }, async () => {
    const t = await expectFailure("AI_TIMEOUT", () => {});
    assertEquals(t.s.claudeCalls.length, 0);
  });
});

Deno.test("parse-price-list 失败：Claude 读到一半超过期限 → 中止那个请求、AI_TIMEOUT", async () => {
  await withTiming({ startedAt: Date.now() - 380_000 + 300, reserveMs: 0, minCallMs: 10 }, async () => {
    const t = await expectFailure("AI_TIMEOUT", (t) => {
      // 期限（300 ms）有用的话会先中止；没用的话 3 秒后回 529（测试会失败，不会卡住）
      t.s.claude = (c) =>
        delayed(c, 3000, () => Response.json({ type: "error", error: { type: "overloaded_error" } }, { status: 529 }));
    });
    assertEquals(t.s.claudeCalls.length, 1);
    assertEquals(((t.s.imp.ai_raw?.calls as unknown[]) ?? []).length, 0);
  });
});

Deno.test("worker 要被关掉（beforeunload）：马上把 import 标成 failed，不会一直卡在 processing", async () => {
  const t = setup();
  let release: (r: Response) => void = () => {};
  // Claude 一直不回、也不理中止（像 worker 已经死掉一样）：只有 beforeunload 的处理会改状态
  t.s.claude = () => new Promise<Response>((r) => (release = r));
  const rt = fakeEdgeRuntime();
  try {
    assertEquals((await call()).status, 202);
    await waitFor(() => t.s.claudeCalls.length === 1);
    assertEquals(t.s.imp.status, "processing");
    globalThis.dispatchEvent(new CustomEvent("beforeunload", { detail: { reason: "WallClockTime" } }));
    await waitFor(() => t.s.imp.status === "failed");
    assertEquals(t.s.imp.error_message, "AI_TIMEOUT");
    assertEquals(t.s.imp.ai_raw?.state, "failed");
    assertEquals(t.s.imp.ai_raw?.interrupted, "WallClockTime");
    assertEquals(t.s.rows, []);
    // 之后就算那个请求回来了，也不会再改成 review
    release(claudeStream({ blocks: [{ type: "text", text: extractionJson([{ name: "late" }]) }] }));
    await Promise.all(rt.pending);
    assertEquals([t.s.imp.status, t.s.imp.error_message], ["failed", "AI_TIMEOUT"]);
    assertEquals(t.s.rows, []);
  } finally {
    rt.restore();
    t.restore();
  }
  // 没有在跑的工作：什么都不做
  await handleShutdown("WallClockTime");
  assertEquals(shutdownCode("CPUTime"), "INTERNAL_ERROR");
  assertEquals(shutdownCode("Memory"), "INTERNAL_ERROR");
  assertEquals(shutdownCode("EarlyDrop"), "AI_TIMEOUT");
});

Deno.test("worker 要被关掉时 Claude 请求会被中止（catch 跑得到的话写同一个代码）", async () => {
  const t = setup();
  t.s.claude = (c) => hang(c);
  const rt = fakeEdgeRuntime();
  try {
    assertEquals((await call()).status, 202);
    await waitFor(() => t.s.claudeCalls.length === 1);
    await handleShutdown("Memory");
    await Promise.all(rt.pending);
    assertEquals([t.s.imp.status, t.s.imp.error_message], ["failed", "INTERNAL_ERROR"]);
    assertEquals(t.s.imp.ai_raw?.error, "INTERNAL_ERROR");
  } finally {
    rt.restore();
    t.restore();
  }
});

Deno.test("parse-price-list 失败：一段失败 → 别段马上中止，还没开始的段不叫 Claude", async () => {
  const csv = "No,Item,Unit,Price\n" +
    Array.from({ length: 600 }, (_, i) => `${i + 1},item ${i + 1},pkt,${i + 1}.00`).join("\n");
  const t = setup();
  t.s.imp.file_path = `${W}/list.csv`;
  t.s.files = { [`${W}/list.csv`]: new TextEncoder().encode(csv) };
  const ok = sheetClaude(1000);
  t.s.claude = (c) => {
    const text = (c.json().messages[0].content[1] as { text: string }).text;
    if (text.includes("part 1 of 12")) {
      return claudeStream({ blocks: [], stopReason: "refusal", stopDetails: { type: "refusal", category: "cyber" } });
    }
    return delayed(c, 50, () => ok(c));
  };
  try {
    await call();
    assertEquals([t.s.imp.status, t.s.imp.error_message], ["failed", "AI_REFUSED"]);
    await new Promise((r) => setTimeout(r, 300)); // 没中止的话，另外七段 50 ms 后做完就会接着叫第 9 到 12 段
    assertEquals(t.s.claudeCalls.length, TIMING.concurrency); // 同时最多 8 段
    assertEquals(t.s.rows, []);
  } finally {
    t.restore();
  }
});

Deno.test("parse-price-list 失败：行写进去之后 suggest_import_matches 失败 → 行删掉、DB_ERROR", async () => {
  const t = await expectFailure("DB_ERROR", (t) => {
    t.s.suggestError = true;
  });
  assertEquals(t.s.inserted, 3); // 真的写进去过
  assertEquals(t.s.rows, []); // 又删掉了
  assertEquals(t.s.deletes, 2); // 写之前清一次、失败后清一次
});

Deno.test("parse-price-list：之前跑到一半死掉（占位超过 10 分钟）→ 可以重跑", async () => {
  const t = setup();
  t.s.imp.ai_raw = {
    state: "running",
    run_id: "dead-run",
    claimed_at: new Date(Date.now() - 11 * 60_000).toISOString(),
  };
  try {
    assertEquals((await call()).status, 202);
    assertEquals(t.s.imp.status, "review");
    assert(t.s.imp.ai_raw?.run_id !== "dead-run");
    assertEquals(t.s.rows.length, 3);
  } finally {
    t.restore();
  }
});

Deno.test("parse-price-list 失败：zip 炸弹的 xlsx → FILE_TOO_LARGE，不叫 Claude、worker 不会被撑爆", async () => {
  const bomb = zipFiles(await bombEntries(150));
  const t = await expectFailure("FILE_TOO_LARGE", (t) => {
    t.s.imp.file_path = `${W}/list.xlsx`;
    t.s.files = { [`${W}/list.xlsx`]: bomb };
  });
  assertEquals(t.s.claudeCalls.length, 0);
  assertEquals((t.s.imp.ai_raw?.file as Record<string, unknown>).kind, "xlsx");
});

Deno.test("errorCode：各种错误 → error_message 代码", () => {
  assertEquals(errorCode(new JobError("AI_TIMEOUT")), "AI_TIMEOUT");
  assertEquals(errorCode(new SpreadsheetError("TOO_MANY_ROWS", "x")), "TOO_MANY_ROWS");
  assertEquals(errorCode(new DbError("x", "y", "XX000", 500)), "DB_ERROR");
  assertEquals(errorCode(new ConfigError("SUPABASE_ENV_MISSING")), "INTERNAL_ERROR");
  assertEquals(errorCode(new TypeError("our bug")), "INTERNAL_ERROR");
  assertEquals(errorCode(new Anthropic.RateLimitError(429, undefined, "slow down", new Headers())), "AI_BUSY");
});

// ---------------------------------------------------------------------------
// 时间预算、用量、失败时写数据库、PDF 分段、格式不对再试
// ---------------------------------------------------------------------------

/** 改 isolate.startedAt / TIMING 的任何栏位，跑完还原 */
async function withTimings(over: Partial<typeof TIMING> & { startedAt?: number }, f: () => Promise<void>) {
  const before = { ...TIMING, failRetryMs: [...TIMING.failRetryMs] };
  const startedAt = isolate.startedAt;
  const { startedAt: s, ...t } = over;
  if (s !== undefined) isolate.startedAt = s;
  Object.assign(TIMING, t);
  try {
    await f();
  } finally {
    isolate.startedAt = startedAt;
    Object.assign(TIMING, before);
  }
}

const csvOf = (n: number) =>
  new TextEncoder().encode(
    "No,Item,Unit,Price\n" + Array.from({ length: n }, (_, i) => `${i + 1},item ${i + 1},pkt,${i + 1}.00`).join("\n"),
  );

/** 请求里有几行 Excel 商品 */
const sheetLines = (c: Call) =>
  [...(c.json().messages[0].content[0].text as string).matchAll(/^(?!\[context\])(\S+!R\d+): /gm)].length;

/** 假的 Claude：读一行要 msPerLine 毫秒（时间缩小 1000 倍：1 毫秒 = 1 秒） */
function slowSheetClaude(msPerLine: number) {
  const ok = sheetClaude(100_000);
  const stats = { active: 0, maxActive: 0 };
  const route = (c: Call) => {
    stats.maxActive = Math.max(stats.maxActive, ++stats.active);
    return delayed(c, sheetLines(c) * msPerLine, () => ok(c)).finally(() => stats.active--);
  };
  return { route, stats };
}

/** 期限 = 现在 + 380 毫秒（= 付费方案的 380 秒缩小 1000 倍），其他时间也缩小 1000 倍 */
const SCALED = () => ({ startedAt: Date.now() - 380_000 + 380, reserveMs: 15, minCallMs: 20, partEstimateMs: 90 });

Deno.test("大的 Excel：Opus 读一行 1.5 秒（时间缩小 1000 倍）→ 700 样、1200 样都在预算里读完（以前：100 行一段、同时 3 段 → AI_TIMEOUT）", async () => {
  for (const n of [700, 1200]) {
    await withTimings(SCALED(), async () => {
      const slow = slowSheetClaude(1.5);
      const t = setup({ claude: slow.route });
      t.s.imp.file_path = `${W}/list.csv`;
      t.s.files = { [`${W}/list.csv`]: csvOf(n) };
      try {
        await call();
        assertEquals([t.s.imp.status, t.s.imp.error_message], ["review", null], String(n));
        assertEquals(t.s.rows.length, n);
        assertEquals(t.s.claudeCalls.length, Math.ceil(n / 50));
        assertEquals(slow.stats.maxActive, Math.min(TIMING.concurrency, Math.ceil(n / 50)));
      } finally {
        t.restore();
      }
    });
  }
  // 旧的设定（100 行一段、同时 3 段）：700 样要 3 轮 × 150 秒 > 365 秒 → 第三轮读到一半被中止
  const chunk = { ...DEFAULT_CHUNK };
  Object.assign(DEFAULT_CHUNK, { maxLines: 100, maxChars: 20_000 });
  try {
    await withTimings({ ...SCALED(), concurrency: 3 }, async () => {
      const t = setup({ claude: slowSheetClaude(1.5).route });
      t.s.imp.file_path = `${W}/list.csv`;
      t.s.files = { [`${W}/list.csv`]: csvOf(700) };
      try {
        await call();
        assertEquals([t.s.imp.status, t.s.imp.error_message], ["failed", "AI_TIMEOUT"]);
      } finally {
        t.restore();
      }
    });
  } finally {
    Object.assign(DEFAULT_CHUNK, chunk);
  }
});

Deno.test("开始之前先估计跑不跑得完：免费方案读不完 1200 样 → TOO_MANY_ROWS；worker 剩下的时间不够 → AI_TIMEOUT；都不叫 Claude", async () => {
  await withTimings({ startedAt: Date.now() }, async () => {
    const big = await expectFailure("TOO_MANY_ROWS", (t) => {
      t.s.imp.file_path = `${W}/list.csv`;
      t.s.files = { [`${W}/list.csv`]: csvOf(1200) };
    }, { PRICE_LIST_TIME_BUDGET_MS: "140000" });
    assertEquals(big.s.claudeCalls.length, 0);
    // 400 样 = 8 段 = 一轮：免费方案读得完
    const t = setup({ claude: sheetClaude(1000) }, { PRICE_LIST_TIME_BUDGET_MS: "140000" });
    t.s.imp.file_path = `${W}/list.csv`;
    t.s.files = { [`${W}/list.csv`]: csvOf(400) };
    try {
      await call();
      assertEquals(t.s.imp.status, "review");
    } finally {
      t.restore();
    }
  });
  // 付费方案，但这个 worker 已经跑了 300 秒：剩下 80 秒，一轮要 90 秒
  await withTimings({ startedAt: Date.now() - 300_000 }, async () => {
    const late = await expectFailure("AI_TIMEOUT", (t) => {
      t.s.imp.file_path = `${W}/list.csv`;
      t.s.files = { [`${W}/list.csv`]: csvOf(100) };
    });
    assertEquals(late.s.claudeCalls.length, 0);
  });
  const now = 1_000_000;
  checkPlan({ deadline: now + 380_000, budgetMs: 380_000 }, 4 * TIMING.concurrency, now); // 4 轮 × 90 秒 ≤ 365 秒
  for (
    const [job, parts, code] of [
      [{ deadline: now + 380_000, budgetMs: 380_000 }, 4 * TIMING.concurrency + 1, "TOO_MANY_ROWS"],
      [{ deadline: now + 100_000, budgetMs: 380_000 }, 1, "AI_TIMEOUT"],
    ] as const
  ) {
    let got = "";
    try {
      checkPlan(job, parts, now);
    } catch (e) {
      got = (e as JobError).code;
    }
    assertEquals(got, code);
  }
});

Deno.test("max_tokens → 两半同时读（一个接一个读的话时间不够）；半段又 max_tokens → AI_TRUNCATED", async () => {
  await withTimings(SCALED(), async () => {
    const ok = sheetClaude(1000);
    const stats = { active: 0, maxActive: 0 };
    const t = setup();
    t.s.imp.file_path = `${W}/list.csv`;
    t.s.files = { [`${W}/list.csv`]: csvOf(50) };
    // 每次 150 秒：50 行那段 max_tokens，25 行的两半读得完。一个接一个要 450 秒 > 365 秒
    t.s.claude = (c) => {
      stats.maxActive = Math.max(stats.maxActive, ++stats.active);
      const n = sheetLines(c);
      return delayed(
        c,
        150,
        () =>
          n > 30 ? claudeStream({ blocks: [{ type: "text", text: '{"rows":[' }], stopReason: "max_tokens" }) : ok(c),
      ).finally(() => stats.active--);
    };
    try {
      await call();
      assertEquals([t.s.imp.status, t.s.rows.length, t.s.claudeCalls.length], ["review", 50, 3]);
      assertEquals(stats.maxActive, 2);
    } finally {
      t.restore();
    }
  });
  const t = await expectFailure("AI_TRUNCATED", (t) => {
    t.s.imp.file_path = `${W}/list.csv`;
    t.s.files = { [`${W}/list.csv`]: csvOf(50) };
    t.s.claude = sheetClaude(10); // 25 行的半段也太长
  });
  assertEquals(
    (t.s.imp.ai_raw!.calls as Record<string, unknown>[]).map((c) => `${c.part}:${c.outcome}`).sort(),
    ["part 1/1 (half):max_tokens", "part 1/1 (half):max_tokens", "part 1/1:max_tokens"],
  );
});

Deno.test("Claude 回的不是 JSON：再试一次（照片、Excel 都是）；两次都不是 → AI_INVALID_OUTPUT", async () => {
  const garbage = () => claudeStream({ blocks: [{ type: "text", text: "Here are the rows: {" }] });
  const t = setup();
  const good = t.s.claude;
  t.s.claude = (c, n) => (n === 1 ? garbage() : good(c, n));
  try {
    await call();
    assertEquals([t.s.imp.status, t.s.rows.length, t.s.claudeCalls.length], ["review", 3, 2]);
    assertEquals(
      (t.s.imp.ai_raw!.calls as Record<string, unknown>[]).map((c) => `${c.part}:${c.outcome}`),
      ["document:invalid_output", "document-retry:ok"],
    );
  } finally {
    t.restore();
  }
  const bad = await expectFailure("AI_INVALID_OUTPUT", (t) => {
    t.s.claude = garbage;
  });
  assertEquals(bad.s.claudeCalls.length, 2);
  // Excel 的一段
  const x = setup();
  const ok = sheetClaude(1000);
  x.s.claude = (c, n) => (n === 1 ? garbage() : ok(c));
  x.s.imp.file_path = `${W}/list.csv`;
  x.s.files = { [`${W}/list.csv`]: csvOf(20) };
  try {
    await call();
    assertEquals([x.s.imp.status, x.s.rows.length], ["review", 20]);
    assertEquals(
      (x.s.imp.ai_raw!.calls as Record<string, unknown>[]).map((c) => `${c.part}:${c.outcome}`),
      ["part 1/1:invalid_output", "part 1/1 retry:ok"],
    );
  } finally {
    x.restore();
  }
  const badSheet = await expectFailure("AI_INVALID_OUTPUT", (t) => {
    t.s.claude = garbage;
    t.s.imp.file_path = `${W}/list.csv`;
    t.s.files = { [`${W}/list.csv`]: csvOf(20) };
  });
  assertEquals(badSheet.s.claudeCalls.length, 2);
});

Deno.test("数据库暂时连不上（写行失败，接着改状态也失败）→ 隔一下再试，最后还是 failed，不会一直卡在 processing", async () => {
  await withTimings({ failRetryMs: [30, 60, 120] }, async () => {
    const t = setup();
    let downUntil = 0;
    // 从写第一批行开始，PostgREST 全部 503 50 毫秒
    t.s.restDown = (c) => {
      if (!downUntil && c.url.pathname === "/rest/v1/price_list_import_rows" && c.method === "POST") {
        downUntil = Date.now() + 50;
      }
      return Date.now() < downUntil;
    };
    const rt = fakeEdgeRuntime();
    try {
      assertEquals((await call()).status, 202);
      await Promise.all(rt.pending);
      assertEquals([t.s.imp.status, t.s.imp.error_message], ["failed", "DB_ERROR"]);
      assertEquals(t.s.imp.ai_raw?.state, "failed");
      assertEquals(t.s.rows, []);
    } finally {
      rt.restore();
      t.restore();
    }
  });
});

Deno.test("用量：一直把 import 改回 processing / ai_raw = null 再叫 → 超过就 429；被挡的、409 的不算次数；还没审核的更少；停权 → 403", async () => {
  const t = setup();
  const again = () => {
    t.s.imp.status = "processing"; // 批发商自己改得到这两栏，所以次数不能看这里
    t.s.imp.ai_raw = null;
    return call();
  };
  try {
    for (let i = 0; i < QUOTA.active.burst; i++) assertEquals((await again()).status, 202);
    assertEquals(t.s.runs.size, QUOTA.active.burst);
    assert([...t.s.runs.keys()].every((k) => k.startsWith(`_runs/${W}/`)), "ledger outside the wholesaler's folder");
    const claudeBefore = t.s.claudeCalls.length;
    const res = await again();
    const body = await res.json();
    assertEquals([res.status, body.error], [429, "TOO_MANY_IMPORTS"]);
    assert(body.retry_after > 0 && body.retry_after <= 600, String(body.retry_after));
    assertEquals(res.headers.get("retry-after"), String(body.retry_after));
    assertEquals(t.s.claudeCalls.length, claudeBefore);
    assertEquals(t.s.runs.size, QUOTA.active.burst); // 被挡的那一笔删掉了
    // 10 分钟以前的不算「同时」
    const age = (
      ms: number,
    ) => (t.s.runs = new Map(
      [...t.s.runs].map(([k, v]) => [k.replace(/\/(\d{13})-/, (_, x) => `/${Number(x) - ms}-`), v]),
    ));
    age(11 * 60_000);
    assertEquals((await again()).status, 202);
    // 已经在跑 → 409，不算次数
    t.s.imp.status = "processing";
    t.s.imp.ai_raw = { state: "running", run_id: "x", claimed_at: new Date().toISOString() };
    const size = t.s.runs.size;
    assertEquals((await call()).status, 409);
    assertEquals(t.s.runs.size, size);
    // 一小时、一天的上限（10 分钟以前的）
    const seed = (n: number, minutesAgo: (i: number) => number) => (t.s.runs = new Map(
      Array.from({ length: n }, (_, i) => [`_runs/${W}/${Date.now() - minutesAgo(i) * 60_000}-r${i}.csv`, "x"]),
    ));
    for (
      const [n, ago, min] of [[QUOTA.active.hour, (i: number) => 15 + i / 2, 2000], [
        QUOTA.active.day,
        (i: number) => 120 + 30 * i,
        3600,
      ]] as const
    ) {
      seed(n, ago);
      const r = await again();
      assertEquals(r.status, 429);
      assert((await r.json()).retry_after > min);
      assertEquals(t.s.runs.size, n);
    }
    // 超过两天的记录会顺手删掉
    seed(5, (i) => 3 * 24 * 60 + i);
    assertEquals((await again()).status, 202);
    assertEquals(t.s.runs.size, 1);
  } finally {
    t.restore();
  }
  // 还没审核（pending）的批发商
  const p = setup();
  p.s.wholesalerStatus = "pending";
  try {
    for (let i = 0; i < QUOTA.pending.burst; i++) {
      p.s.imp.status = "processing";
      p.s.imp.ai_raw = null;
      assertEquals((await call()).status, 202);
    }
    p.s.imp.status = "processing";
    p.s.imp.ai_raw = null;
    assertEquals((await call()).status, 429);
  } finally {
    p.restore();
  }
  // 停权 → 403，不记次数、不叫 Claude；Storage 坏掉 → 503，不占位
  for (
    const [arrange, status, error] of [
      [(x: ReturnType<typeof setup>) => (x.s.wholesalerStatus = "suspended"), 403, "WHOLESALER_SUSPENDED"],
      [(x: ReturnType<typeof setup>) => (x.s.storageDown = true), 503, "QUOTA_UNAVAILABLE"],
    ] as const
  ) {
    const x = setup();
    arrange(x);
    try {
      const r = await call();
      assertEquals([r.status, (await r.json()).error], [status, error]);
      assertEquals([x.s.runs.size, x.s.claudeCalls.length, x.s.imp.ai_raw], [0, 0, null]);
    } finally {
      x.restore();
    }
  }
});

/** 测试用的 PDF：n 页（只有页面树，没有内容；假的 Claude 不看内容） */
function pdfWithPages(n: number): Uint8Array {
  const kids = Array.from({ length: n }, (_, i) => `${i + 3} 0 R`).join(" ");
  let s = "%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n";
  s += `2 0 obj\n<< /Type /Pages /Kids [${kids}] /Count ${n} >>\nendobj\n`;
  for (let i = 0; i < n; i++) {
    s += `${i + 3} 0 obj\n<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 99 0 R >> >> >>\nendobj\n`;
  }
  return new TextEncoder().encode(s + "trailer\n<< /Root 1 0 R >>\n%%EOF\n");
}

/** 假的 Claude（PDF）：照指示读第几页到第几页，每页回一样商品；一次超过 maxPages 页 → max_tokens */
function pdfClaude(pages: number, maxPages = Infinity) {
  return (c: Call): Response => {
    const instr = (c.json().messages[0].content[2] as { text: string }).text;
    let from = 1, to = pages;
    const m = /on pages (\d+) to (\d+)|on page (\d+)|from page (\d+) to the last page/.exec(instr);
    if (m?.[1]) [from, to] = [Number(m[1]), Number(m[2])];
    else if (m?.[3]) from = to = Number(m[3]);
    else if (m?.[4]) from = Number(m[4]);
    if (to - from + 1 > maxPages) {
      return claudeStream({ blocks: [{ type: "text", text: '{"rows":[' }], stopReason: "max_tokens" });
    }
    const rows = Array.from({ length: Math.min(to, pages) - from + 1 }, (_, i) => ({
      name: `item p${from + i}`,
      source_ref: `p${from + i} line 1`,
    }));
    return claudeStream({ blocks: [{ type: "text", text: extractionJson(rows.reverse()) }] });
  };
}

Deno.test("PDF：超过 4 页就分段读（同一个 document block + cache_control、同一个标签），第一段写好快取别段才送；照页码排", async () => {
  const pages = 10;
  const t = setup();
  t.s.imp.file_path = `${W}/list.pdf`;
  t.s.files = { [`${W}/list.pdf`]: pdfWithPages(pages) };
  const ok = pdfClaude(pages);
  const arrived: number[] = [];
  t.s.claude = (c, n) => {
    arrived.push(Date.now());
    return n === 1 ? delayed(c, 60, () => ok(c)) : ok(c);
  };
  try {
    await call();
    assertEquals(t.s.imp.status, "review");
    assertEquals(t.s.rows.map((r) => r.name), Array.from({ length: pages }, (_, i) => `item p${i + 1}`));
    assertEquals(t.s.claudeCalls.length, Math.ceil(pages / PDF_PAGES_PER_CALL));
    const contents = t.s.claudeCalls.map((c) => (c.messages as { content: Record<string, unknown>[] }[])[0].content);
    assertStringIncludes(String(contents[0][2].text), "on pages 1 to 4");
    assertStringIncludes(String(contents.at(-1)![2].text), "from page 9 to the last page");
    for (const content of contents) {
      assertEquals(content[1].cache_control, { type: "ephemeral" });
      assertEquals(content[0].text, contents[0][0].text); // 开头标签一样，快取才对得上
      assertEquals(
        (content[1].source as Record<string, unknown>).data,
        (contents[0][1].source as Record<string, unknown>).data,
      );
    }
    // 别段在第一段回应开始之后才送
    for (const at of arrived.slice(1)) assert(at - arrived[0] >= 50, `${at - arrived[0]} ms`);
    assertEquals((t.s.imp.ai_raw!.file as Record<string, unknown>).pages, pages);
  } finally {
    t.restore();
  }
});

Deno.test("PDF：max_tokens → 那几页切两半再读（以前只用 low effort 重读整份，永远读不完）", async () => {
  const t = setup();
  t.s.imp.file_path = `${W}/list.pdf`;
  t.s.files = { [`${W}/list.pdf`]: pdfWithPages(10) };
  t.s.claude = pdfClaude(10, 2);
  try {
    await call();
    assertEquals(t.s.imp.status, "review");
    assertEquals(t.s.rows.map((r) => r.name), Array.from({ length: 10 }, (_, i) => `item p${i + 1}`));
    const parts = (t.s.imp.ai_raw!.calls as Record<string, unknown>[]).map((c) => `${c.part}:${c.outcome}`).sort();
    assertEquals(parts, [
      "pages 1-2 (half):ok",
      "pages 1-4:max_tokens",
      "pages 3-4 (half):ok",
      "pages 5-6 (half):ok",
      "pages 5-8:max_tokens",
      "pages 7-8 (half):ok",
      "pages 9-end:ok",
    ]);
  } finally {
    t.restore();
  }
  // 3 页（一次读）max_tokens → 切成 1-2、3-最后
  const small = setup();
  small.s.imp.file_path = `${W}/list.pdf`;
  small.s.files = { [`${W}/list.pdf`]: pdfWithPages(3) };
  small.s.claude = pdfClaude(3, 2);
  try {
    await call();
    assertEquals(small.s.rows.map((r) => r.name), ["item p1", "item p2", "item p3"]);
    assertEquals(small.s.claudeCalls.length, 3);
  } finally {
    small.restore();
  }
  // 数不出页数（或只有一页）：low effort 再试一次 → 还是 max_tokens → AI_TRUNCATED
  const unknown = await expectFailure("AI_TRUNCATED", (t) => {
    t.s.imp.file_path = `${W}/list.pdf`;
    t.s.files = { [`${W}/list.pdf`]: new TextEncoder().encode("%PDF-1.4\n" + "x".repeat(200)) };
    t.s.claude = () => claudeStream({ blocks: [{ type: "text", text: '{"rows":[' }], stopReason: "max_tokens" });
  });
  assertEquals(unknown.s.claudeCalls.map((c) => (c.output_config as Record<string, unknown>).effort), [
    "medium",
    "low",
  ]);
});

Deno.test("PDF 页数：页面树的 /Count、压缩的物件流、linearized、数 /Type /Page；数不出来 → null", async () => {
  assertEquals(await pdfPageCount(pdfWithPages(7)), 7);
  const enc = new TextEncoder();
  const inner = enc.encode(
    `3 0 4 60 << /Type /Pages /Kids [5 0 R 6 0 R] /Count 12 >> << /Type /Catalog /Pages 3 0 R >>`,
  );
  const z = new Uint8Array(
    await new Response(new Blob([inner]).stream().pipeThrough(new CompressionStream("deflate"))).arrayBuffer(),
  );
  const head = enc.encode(
    `%PDF-1.5\n9 0 obj\n<< /Type /ObjStm /N 2 /First 10 /Filter /FlateDecode /Length ${z.length} >>\nstream\n`,
  );
  const tail = enc.encode("\nendstream\nendobj\n%%EOF\n");
  assertEquals(await pdfPageCount(new Uint8Array([...head, ...z, ...tail])), 12);
  assertEquals(
    await pdfPageCount(enc.encode("%PDF-1.7\n1 0 obj\n<< /Linearized 1 /L 9999 /N 9 /T 99 >>\nendobj\n")),
    9,
  );
  assertEquals(await pdfPageCount(enc.encode("%PDF-1.4\n<< /Type /Page >> << /Type /Page >>")), 2);
  assertEquals(await pdfPageCount(enc.encode("%PDF-1.4\n" + "x".repeat(100))), null);
  assertEquals(pageRanges(10, 4), [{ from: 1, to: 4, last: 10 }, { from: 5, to: 8, last: 10 }, {
    from: 9,
    to: null,
    last: 10,
  }]);
  assertEquals(pageRanges(4, 4), null);
  assertEquals(pageRanges(null, 4), null);
  assertEquals(splitRange({ from: 1, to: 4, last: 10 }), [{ from: 1, to: 2, last: 10 }, { from: 3, to: 4, last: 10 }]);
  assertEquals(splitRange({ from: 9, to: null, last: 10 }), [{ from: 9, to: 9, last: 10 }, {
    from: 10,
    to: null,
    last: 10,
  }]);
  assertEquals(splitRange({ from: 3, to: 3, last: 10 }), null);
  assertEquals(splitRange({ from: 10, to: null, last: 10 }), null);
});
