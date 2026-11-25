import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import fn, { storagePath } from "../parse-price-list/index.ts";
import {
  type Call,
  claudeStream,
  extractionJson,
  fakeEdgeRuntime,
  fakeFetch,
  isAnthropic,
  isService,
  PUBLISHABLE,
  rpcName,
  SB_URL,
  setEnv,
  SUPABASE_ENV,
} from "./_helpers.ts";
import { makeWorkbook } from "./_sheets.ts";

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
  claude: (c: Call, n: number) => Response;
  claudeCalls: Record<string, unknown>[];
  deletes: number;
}

/** 假的 Supabase（Auth、PostgREST、Storage）+ Anthropic */
function backend(s: State) {
  return (c: Call): Response | undefined => {
    const p = c.url.pathname;
    if (isAnthropic(c)) {
      s.claudeCalls.push(c.json());
      return s.claude(c, s.claudeCalls.length);
    }
    if (c.url.origin !== SB_URL) return undefined;
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
      return new Response(null, { status: 201 });
    }
    if (rpcName(c) === "suggest_import_matches") {
      assert(isService(c));
      s.suggestCalls.push(c.json());
      return Response.json({ rows: s.rows.length, matched: 1, suggested: 2 });
    }
    if (p.startsWith("/storage/v1/object/price-lists/")) {
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
  const t = setup({ claude: sheetClaude(60) });
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
    // 150 行 → 2 段（100 + 50）；100 行那段 max_tokens → 切成 50 + 50
    const parts = (t.s.imp.ai_raw!.calls as Record<string, unknown>[]).map((c) => `${c.part}:${c.outcome}`).sort();
    assertEquals(parts, ["part 1/2 (half):ok", "part 1/2 (half):ok", "part 1/2:max_tokens", "part 2/2:ok"]);
    // 每段都有表头
    for (const call of t.s.claudeCalls) {
      const text = (call.messages as { content: { text: string }[] }[])[0].content[0].text;
      assertStringIncludes(text, "[context] Sheet1!R1: No | Item | Unit | Price");
    }
    assertEquals(t.s.imp.ai_raw!.file, { kind: "csv", bytes: csv.length, lines: 151, chunks: 2 });
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
