import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import Anthropic from "@anthropic-ai/sdk";
import fn, {
  checkPlan,
  errorCode,
  handleShutdown,
  isolate,
  jobDeadline,
  JobError,
  MAX_BUDGET_MS,
  PDF_PAGES_PER_CALL,
  refusalResponse,
  shutdownCode,
  storagePath,
  timeBudgetMs,
  TIMING,
} from "../parse-price-list/index.ts";
import { UUID_RE } from "../_shared/http.ts";
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
  pgError,
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
/** 登录的人（auth.getUser 回的 id） */
const USER_ID = "dddddddd-0000-4000-8000-000000000004";
const MIN = 60_000;
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

/** price_list_runs 的一行（只有 reserve_price_list_run 写） */
interface Run {
  wholesaler_id: string;
  import_id: string | null;
  run_id: string;
  user_id: string;
  /** epoch 毫秒 */
  created_at: number;
}

interface State {
  imp: ImportRow;
  /** RLS：用户身份读得到这份导入 */
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
  /** wholesalers.status（reserve_price_list_run 看） */
  wholesalerStatus: string;
  /** wholesaler_members（W 的 owner / staff 的 user_id） */
  members: string[];
  /** profiles.role = admin 的 user_id */
  admins: string[];
  /** price_list_runs */
  runs: Run[];
  /** reserve_price_list_run 收到的参数 */
  reserveCalls: Record<string, unknown>[];
  /** reserve_price_list_run 叫不到：500、断线、函数还没建（PostgREST 404） */
  reserveDown?: "http" | "network" | "missing";
  /** reserve_price_list_run 回这个（迁移跟代码对不上） */
  reserveResult?: unknown;
  /** RLS 读到之后、reserve 之前被删掉了 */
  importGone?: boolean;
  /** price_list_imports 的 PATCH（服务器身份）的条件 */
  patches: URLSearchParams[];
  /** 这时候 PostgREST 全部回 503（数据库暂时连不上） */
  restDown?: (c: Call) => boolean;
  /** Auth 的 /user 换成这个回应（Auth 服务出问题）；丢错 = 断线 */
  authResponse?: () => Response;
}

/** 照 _price_list_run_limits（20261127000200_seller_hardening.sql）：[段, 长度, active 上限, pending 上限] */
const LIMITS = [["burst", 10 * MIN, 3, 2], ["hour", 60 * MIN, 10, 4], ["day", 24 * 60 * MIN, 30, 8]] as const;

/** jsonb 里的 timestamptz 长这样：2026-11-25T21:06:06.326696+00:00 */
const pgTime = (ms: number) => new Date(ms).toISOString().replace(/\.(\d{3})Z$/, ".$1000+00:00");

/**
 * 假的 reserve_price_list_run：检查的顺序、回传的样子都照 SQL（20261127000200_seller_hardening.sql；
 * 顺序和进位 07_seller_hardening.test.sql 有测）。只有一家批发商（W）、一份导入（s.imp）。不跑的结果什么都不改。
 * 用量算两份：这家批发商、叫的人（在每一家跑的都算，客服不算）。SQL 还会把「建这家批发商的人」建的每一家
 * 加起来算、停权的老板也挡，这里只有一家批发商，不用。
 */
function reserve(s: State, p: Record<string, unknown>): Response {
  const uuidOrNull = (v: unknown) => v == null || (typeof v === "string" && UUID_RE.test(v));
  if (![p.p_import_id, p.p_user_id, p.p_run_id].every(uuidOrNull)) {
    return pgError("invalid input syntax for type uuid", "22P02");
  }
  if (p.p_run_id == null) return pgError("INVALID_RUN_ID");
  if (s.runs.some((r) => r.run_id === p.p_run_id)) return pgError("RUN_ID_USED");
  const now = Date.now();
  const imp = !s.importGone && p.p_import_id === s.imp.id && s.imp.wholesaler_id === W ? s.imp : null;
  if (!imp) return Response.json({ result: "not_found" });
  const user = p.p_user_id as string | null;
  if (!user || !(s.members.includes(user) || s.admins.includes(user))) return Response.json({ result: "not_member" });
  if (s.wholesalerStatus !== "active" && s.wholesalerStatus !== "pending") {
    return Response.json({ result: "suspended" });
  }
  if (imp.status !== "processing") return Response.json({ result: "not_processing", status: imp.status });
  // 在跑而且 claimed_at 10 分钟内；读不懂的时间（NaN）当成死掉了
  if (imp.ai_raw?.state === "running" && Date.parse(String(imp.ai_raw.claimed_at)) > now - 10 * MIN) {
    return Response.json({ result: "already_running" });
  }
  let window: string | null = null;
  let retry = 0;
  const scopes: ((r: Run) => boolean)[] = [(r) => r.wholesaler_id === W];
  if (!s.admins.includes(user)) scopes.push((r) => r.user_id === user);
  for (const [name, len, active, pending] of LIMITS) {
    const max = s.wholesalerStatus === "active" ? active : pending;
    for (const inScope of scopes) {
      const times = s.runs.filter((r) => inScope(r) && r.created_at > now - len).map((r) => r.created_at)
        .sort((a, b) => a - b);
      if (times.length >= max) {
        // 第 (已跑 - 上限 + 1) 旧的那一次离开这段时间就有位置；几份、几段都满 → 要等最久的
        const wait = Math.max(1, Math.ceil((times[times.length - max] + len - now) / 1000));
        if (window === null || wait > retry) [window, retry] = [name, wait];
      }
    }
  }
  if (window) return Response.json({ result: "quota", window, retry_after_sec: retry });
  const claimedAt = pgTime(now);
  imp.ai_raw = { version: 1, state: "running", run_id: p.p_run_id, claimed_at: claimedAt, claimed_by: user };
  imp.error_message = null;
  s.runs.push({ wholesaler_id: W, import_id: imp.id, run_id: p.p_run_id as string, user_id: user, created_at: now });
  return Response.json({
    result: "ok",
    run_id: p.p_run_id,
    claimed_at: claimedAt,
    wholesaler_id: W,
    wholesaler_status: s.wholesalerStatus,
    import_id: imp.id,
    file_path: imp.file_path,
    file_type: imp.file_type,
  });
}

/** 假的 Supabase（Auth、PostgREST、Storage 的价目表档案）+ Anthropic。没对到的请求（例如以前 Storage 的用量记录）都算 unexpected */
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
    if (rpcName(c) === "reserve_price_list_run") {
      // 只给服务器（revoke 了 authenticated）
      if (!isService(c)) return pgError("permission denied for function reserve_price_list_run", "42501", 401);
      const params = c.json();
      s.reserveCalls.push(params);
      assertEquals(Object.keys(params).sort(), ["p_import_id", "p_run_id", "p_user_id"]);
      if (s.reserveDown === "network") return Promise.reject(new TypeError("connection reset"));
      if (s.reserveDown === "http") return pgError("canceling statement due to statement timeout", "57014", 500);
      if (s.reserveDown === "missing") {
        return Response.json({ code: "PGRST202", message: "Could not find the function", details: null, hint: null }, {
          status: 404,
        });
      }
      if ("reserveResult" in s) return Response.json(s.reserveResult ?? null);
      return reserve(s, params);
    }
    if (p === "/auth/v1/user") {
      if (s.authResponse) return s.authResponse();
      if (c.headers.get("authorization") !== `Bearer ${USER_JWT}`) {
        return Response.json({ code: 401, error_code: "bad_jwt", msg: "invalid JWT" }, { status: 401 });
      }
      return Response.json({ id: USER_ID, aud: "authenticated", role: "authenticated", email: "w@x.my" });
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
      s.patches.push(q);
      // 占位只在 reserve_price_list_run 里；之后的写回都要还是 processing、而且是这一次的 run_id
      assert(!q.has("or"), "claim PATCH");
      assertEquals(q.get("status"), "eq.processing");
      assert(q.has("ai_raw->>run_id"), "write without run_id");
      if (q.get("id") !== `eq.${s.imp.id}`) return Response.json([]);
      if (s.imp.status !== "processing") return Response.json([]);
      if (q.get("ai_raw->>run_id") !== `eq.${s.imp.ai_raw?.run_id}`) return Response.json([]);
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
    members: [USER_ID],
    admins: [],
    runs: [],
    reserveCalls: [],
    patches: [],
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

/** price_list_runs 的一笔：minutesAgo 分钟前跑的 */
const pastRun = (minutesAgo: number): Run => ({
  wholesaler_id: W,
  import_id: null,
  run_id: crypto.randomUUID(),
  user_id: USER_ID,
  created_at: Date.now() - minutesAgo * MIN,
});

Deno.test("parse-price-list：身份、参数、设定不全、RLS 读不到 → 404（都不叫 reserve_price_list_run）", async () => {
  const t = setup();
  try {
    const opt = await fn.fetch(new Request(URL_, { method: "OPTIONS" }));
    assertEquals(opt.status, 204);
    assertEquals(opt.headers.get("access-control-allow-origin"), "*");
    assertEquals((await fn.fetch(new Request(URL_))).status, 405);
    assertEquals((await call(undefined, null)).status, 401);
    assertEquals((await call(undefined, "Bearer someone.else")).status, 401);
    const bad = await call({ import_id: "../../etc" });
    assertEquals([bad.status, (await bad.json()).error], [400, "INVALID_IMPORT_ID"]);
    t.s.visible = false; // RLS：别家的 import 看不到
    const nf = await call();
    assertEquals([nf.status, (await nf.json()).error], [404, "IMPORT_NOT_FOUND"]);
    assertEquals([t.s.reserveCalls.length, t.s.runs.length, t.s.claudeCalls.length], [0, 0, 0]);
  } finally {
    t.restore();
  }
  // 设定不全：什么都还没碰就回 500（不会占了位才发现）
  const c = setup({}, { SUPABASE_PUBLISHABLE_KEYS: undefined });
  try {
    const res = await call();
    assertEquals([res.status, (await res.json()).error], [500, "CONFIG_MISSING"]);
    assertEquals(c.net.calls.length, 0);
  } finally {
    c.restore();
  }
});

Deno.test("Auth 服务出问题（断线、5xx、429、回的不是 JSON）→ 503 AUTH_UNAVAILABLE（不是 401：JWT 可能是好的）；JWT 真的不对才 401", async () => {
  const cases: [string, () => Response, number, string][] = [
    ["503", () => Response.json({ code: 503, msg: "unavailable" }, { status: 503 }), 503, "AUTH_UNAVAILABLE"],
    ["500", () => Response.json({ code: 500, msg: "boom" }, { status: 500 }), 503, "AUTH_UNAVAILABLE"],
    ["502 HTML（gateway）", () => new Response("<html>Bad Gateway</html>", { status: 502 }), 503, "AUTH_UNAVAILABLE"],
    ["504 逾时", () => new Response("upstream timeout", { status: 504 }), 503, "AUTH_UNAVAILABLE"],
    [
      "429 太忙",
      () => Response.json({ code: 429, error_code: "over_request_rate_limit", msg: "slow down" }, { status: 429 }),
      503,
      "AUTH_UNAVAILABLE",
    ],
    ["回的不是 JSON（4xx）", () => new Response("<html>Forbidden</html>", { status: 403 }), 503, "AUTH_UNAVAILABLE"],
    [
      "断线",
      () => {
        throw new TypeError("connection refused");
      },
      503,
      "AUTH_UNAVAILABLE",
    ],
    [
      "JWT 不对（401）",
      () => Response.json({ code: 401, error_code: "bad_jwt", msg: "invalid JWT" }, { status: 401 }),
      401,
      "UNAUTHORIZED",
    ],
    [
      "用户删掉了（403 user_not_found）",
      () =>
        Response.json({ code: 403, error_code: "user_not_found", msg: "User from sub claim in JWT does not exist" }, {
          status: 403,
        }),
      401,
      "UNAUTHORIZED",
    ],
    [
      "session 不在了（登出）",
      () =>
        Response.json({ code: 403, error_code: "session_not_found", msg: "Session does not exist" }, { status: 403 }),
      401,
      "UNAUTHORIZED",
    ],
  ];
  for (const [name, response, status, error] of cases) {
    const t = setup({ authResponse: response });
    try {
      const res = await call();
      assertEquals([res.status, await res.json()], [status, { error }], name);
      assertEquals(res.headers.get("access-control-allow-origin"), "*", name);
      // 都还没碰导入：没读、没叫 reserve、没占位
      assertEquals(
        [t.s.reserveCalls.length, t.s.runs.length, t.s.imp.ai_raw, t.s.claudeCalls.length],
        [0, 0, null, 0],
        name,
      );
    } finally {
      t.restore();
    }
  }
});

Deno.test("reserve_price_list_run 的每一种「不跑」→ HTTP；顺序照 SQL；都没占位、没算次数、不叫 Claude", async () => {
  const running = () => ({ version: 1, state: "running", run_id: crypto.randomUUID(), claimed_at: pgTime(Date.now()) });
  const cases: [string, (s: State) => void, number, Record<string, unknown>][] = [
    ["RLS 读到之后被删掉了", (s) => (s.importGone = true), 404, { error: "IMPORT_NOT_FOUND" }],
    ["不是这家的成员（也不是客服）", (s) => (s.members = []), 404, { error: "IMPORT_NOT_FOUND" }],
    ["停权", (s) => (s.wholesalerStatus = "suspended"), 403, { error: "WHOLESALER_SUSPENDED" }],
    ["不是 processing", (s) => (s.imp.status = "review"), 409, { error: "IMPORT_NOT_PROCESSING", status: "review" }],
    ["有人在跑（10 分钟内）", (s) => (s.imp.ai_raw = running()), 409, { error: "IMPORT_ALREADY_RUNNING" }],
    // 几样都不对：回第一个（成员 → 停权 → 状态 → 在跑 → 用量）
    [
      "不是成员 + 停权",
      (s) => {
        s.members = [];
        s.wholesalerStatus = "suspended";
      },
      404,
      { error: "IMPORT_NOT_FOUND" },
    ],
    [
      "停权 + 已经上架",
      (s) => {
        s.wholesalerStatus = "suspended";
        s.imp.status = "applied";
      },
      403,
      { error: "WHOLESALER_SUSPENDED" },
    ],
    [
      "failed + 还写着在跑",
      (s) => {
        s.imp.status = "failed";
        s.imp.ai_raw = running();
      },
      409,
      { error: "IMPORT_NOT_PROCESSING", status: "failed" },
    ],
    [
      "在跑 + 用量满了（不算次数）",
      (s) => {
        s.imp.ai_raw = running();
        s.runs = [1, 2, 3].map(pastRun);
      },
      409,
      { error: "IMPORT_ALREADY_RUNNING" },
    ],
  ];
  for (const [name, arrange, status, body] of cases) {
    const t = setup();
    arrange(t.s);
    const before = structuredClone({ imp: t.s.imp, runs: t.s.runs });
    try {
      const res = await call();
      assertEquals([res.status, await res.json()], [status, body], name);
      assertEquals(res.headers.get("access-control-allow-origin"), "*", name);
      assertEquals(t.s.reserveCalls.length, 1, name);
      assertEquals({ imp: t.s.imp, runs: t.s.runs }, before, name); // 什么都没改
      assertEquals([t.s.claudeCalls.length, t.s.patches.length], [0, 0], name);
      assertEquals(t.net.unexpected, [], name);
    } finally {
      t.restore();
    }
  }
  // 客服（不是成员）可以代操作：一样算这家批发商的次数
  const a = setup({ members: [], admins: [USER_ID] });
  try {
    assertEquals((await call()).status, 202);
    assertEquals([a.s.imp.status, a.s.runs.length, a.s.runs[0].wholesaler_id], ["review", 1, W]);
  } finally {
    a.restore();
  }
});

Deno.test("叫不到 reserve_price_list_run（数据库出错、断线、函数还没建、回传认不得）→ 503 QUOTA_UNAVAILABLE，不跑", async () => {
  const cases: [string, (s: State) => void][] = [
    ["500", (s) => (s.reserveDown = "http")],
    ["断线", (s) => (s.reserveDown = "network")],
    ["迁移还没跑", (s) => (s.reserveDown = "missing")],
    ["认不得的结果", (s) => (s.reserveResult = { result: "maybe" })],
    ["null", (s) => (s.reserveResult = null)],
  ];
  for (const [name, arrange] of cases) {
    const t = setup();
    arrange(t.s);
    try {
      const res = await call();
      assertEquals([res.status, await res.json()], [503, { error: "QUOTA_UNAVAILABLE" }], name);
      assertEquals(res.headers.get("retry-after"), null, name);
      assertEquals(
        [t.s.imp.ai_raw, t.s.runs.length, t.s.claudeCalls.length, t.s.patches.length],
        [null, 0, 0, 0],
        name,
      );
      assertEquals(t.net.unexpected, [], name);
    } finally {
      t.restore();
    }
  }
  // 回应的样子
  const q = refusalResponse({ result: "quota", window: "day", retry_after_sec: 12.2 });
  assertEquals([q.status, q.headers.get("retry-after"), await q.json()], [429, "13", {
    error: "TOO_MANY_IMPORTS",
    retry_after: 13,
    window: "day",
  }]);
  const odd = refusalResponse({ result: "quota", retry_after_sec: "soon" });
  assertEquals([odd.headers.get("retry-after"), (await odd.json()).retry_after], ["60", 60]);
  assertEquals(refusalResponse({}).status, 503);
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
    // 先占位才回 202：只用 reserve_price_list_run（服务器身份），这次新的 run_id、验过的用户
    assertEquals(t.s.reserveCalls.length, 1);
    const rc = t.s.reserveCalls[0] as Record<string, string>;
    assertEquals([rc.p_import_id, rc.p_user_id], [IMP, USER_ID]);
    assert(UUID_RE.test(rc.p_run_id), rc.p_run_id);
    assertEquals(t.s.runs.map((r) => [r.run_id, r.import_id, r.user_id]), [[rc.p_run_id, IMP, USER_ID]]);
    const claim = { ...t.s.imp.ai_raw };
    assertEquals([claim.state, claim.run_id, claim.claimed_by], ["running", rc.p_run_id, USER_ID]);
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
    // run_id、claimed_at 照数据库占位时写的（claimed_at 是 Postgres 的格式，不是这里的时间）
    assertEquals([ai.run_id, ai.claimed_at], [claim.run_id, claim.claimed_at]);
    assertStringIncludes(String(ai.claimed_at), "+00:00");
    // 写回：还是 processing、同一个 run_id
    assertEquals(t.s.patches.map((q) => q.get("ai_raw->>run_id")), [`eq.${rc.p_run_id}`]);
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

Deno.test("parse-price-list：之前跑到一半死掉（占位超过 10 分钟、claimed_at 读不懂）→ 可以重跑", async () => {
  for (const claimed_at of [new Date(Date.now() - 11 * MIN).toISOString(), "not a time"]) {
    const t = setup();
    t.s.imp.ai_raw = { state: "running", run_id: "dead-run", claimed_at };
    try {
      assertEquals((await call()).status, 202, claimed_at);
      assertEquals(t.s.imp.status, "review");
      assertEquals(t.s.imp.ai_raw?.run_id, t.s.runs[0].run_id);
      assertEquals(t.s.rows.length, 3);
    } finally {
      t.restore();
    }
  }
});

Deno.test("定时任务已经把卡住的标成 AI_TIMEOUT：很晚才失败的 worker 不会盖掉（写回都要 processing + 同一个 run_id）", async () => {
  const t = setup();
  let answer: (r: Response) => void = () => {};
  t.s.claude = () => new Promise<Response>((r) => (answer = r));
  const rt = fakeEdgeRuntime();
  try {
    assertEquals((await call()).status, 202);
    await waitFor(() => t.s.claudeCalls.length === 1);
    // fail_stuck_price_list_imports：failed + AI_TIMEOUT，ai_raw 留着 run_id、claimed_at
    const runId = t.s.imp.ai_raw!.run_id;
    Object.assign(t.s.imp, {
      status: "failed",
      error_message: "AI_TIMEOUT",
      ai_raw: { ...t.s.imp.ai_raw, state: "failed", error: "AI_TIMEOUT", interrupted: "sweep" },
    });
    answer(claudeStream({ blocks: [], stopReason: "refusal", stopDetails: { type: "refusal", category: "cyber" } }));
    await Promise.all(rt.pending);
    assertEquals([t.s.imp.status, t.s.imp.error_message, t.s.imp.ai_raw?.interrupted], [
      "failed",
      "AI_TIMEOUT",
      "sweep",
    ]);
    assertEquals(t.s.patches.length, 1); // worker 想标 AI_REFUSED，但条件对不上
    assertEquals(t.s.patches[0].get("ai_raw->>run_id"), `eq.${runId}`);
  } finally {
    rt.restore();
    t.restore();
  }
});

Deno.test("PRICE_LIST_TIME_BUDGET_MS 最多 9 分钟（比「在跑超过 10 分钟可以重新占位」短）：超过就用默认的 380 秒", () => {
  assert(MAX_BUDGET_MS < 10 * MIN);
  for (
    const [v, want] of [
      [undefined, 380_000],
      ["140000", 140_000],
      ["540000", 540_000],
      ["600000", 380_000],
      ["900000", 380_000],
      ["abc", 380_000],
    ] as const
  ) {
    const restore = setEnv({ PRICE_LIST_TIME_BUDGET_MS: v });
    try {
      assertEquals(timeBudgetMs(), want, String(v));
    } finally {
      restore();
    }
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

Deno.test("用量：批发商一直新建导入再叫 → 第 4 次 429（Retry-After）；挡下来的不算次数；10 分钟后又可以；一小时 / 一天；几段都满回要等最久的", async () => {
  const t = setup();
  let n = 0;
  // 批发商自己做得到的：上传、新建一份 processing 的导入（保护 trigger 只让它这样建，旧的改不回 processing），再叫
  const again = () => {
    const id = `cccccccc-0000-4000-8000-${String(++n).padStart(12, "0")}`;
    t.s.imp = { ...t.s.imp, id, status: "processing", error_message: null, ai_raw: null };
    return call({ import_id: id });
  };
  const blocked = async (window: string, min: number, max: number) => {
    const runs = t.s.runs.length;
    const claude = t.s.claudeCalls.length;
    const res = await again();
    const body = await res.json();
    assertEquals([res.status, body.error, body.window], [429, "TOO_MANY_IMPORTS", window]);
    assert(body.retry_after >= min && body.retry_after <= max, `${window}: ${body.retry_after}`);
    assertEquals(res.headers.get("retry-after"), String(body.retry_after));
    // 被挡的：不占位、不算次数、不叫 Claude
    assertEquals([t.s.imp.ai_raw, t.s.runs.length, t.s.claudeCalls.length], [null, runs, claude]);
  };
  try {
    for (let i = 0; i < 3; i++) assertEquals((await again()).status, 202);
    assertEquals(t.s.runs.length, 3);
    assertEquals(new Set(t.s.runs.map((r) => r.run_id)).size, 3); // 每次新的 run_id
    await blocked("burst", 590, 600); // 刚跑的那一次 10 分钟后离开
    // 10 分钟以前的不算「同时」
    for (const r of t.s.runs) r.created_at -= 11 * MIN;
    assertEquals((await again()).status, 202);
    // 已经在跑 → 409，不算次数
    t.s.imp.status = "processing";
    t.s.imp.ai_raw = { state: "running", run_id: "x", claimed_at: new Date().toISOString() };
    const size = t.s.runs.length;
    assertEquals((await call({ import_id: t.s.imp.id })).status, 409);
    assertEquals(t.s.runs.length, size);
    // 一小时 10 次：最旧的 19.5 分钟前 → 40.5 分钟后
    t.s.runs = Array.from({ length: 10 }, (_, i) => pastRun(15 + i / 2));
    await blocked("hour", 2429, 2430);
    // 一天 30 次：最旧的 16.5 小时前 → 7.5 小时后
    t.s.runs = Array.from({ length: 30 }, (_, i) => pastRun(120 + 30 * i));
    await blocked("day", 26_999, 27_000);
    // 10 分钟、一小时都满：回要等最久的那段（7 分钟后 burst 有位置，但一小时的要 39 分钟）
    t.s.runs = [1, 2, 3, ...Array.from({ length: 7 }, (_, i) => 15 + i)].map(pastRun);
    await blocked("hour", 2339, 2340);
    // 超过一天的不算
    t.s.runs = Array.from({ length: 30 }, (_, i) => pastRun(24 * 60 + 1 + i));
    assertEquals((await again()).status, 202);
    // 同一个人在别家批发商跑的也算（一直注册新的批发商不会多出用量）
    t.s.runs = [1, 2, 3].map((m) => ({ ...pastRun(m), wholesaler_id: OTHER_W }));
    await blocked("burst", 1, 600);
  } finally {
    t.restore();
  }
  // 还没审核（pending）的批发商：10 分钟 2 次、一小时 4 次
  const p = setup({ wholesalerStatus: "pending" });
  try {
    for (let i = 0; i < 2; i++) {
      p.s.imp = { ...p.s.imp, status: "processing", ai_raw: null };
      assertEquals((await call()).status, 202);
    }
    p.s.imp = { ...p.s.imp, status: "processing", ai_raw: null };
    const r = await call();
    assertEquals([r.status, (await r.json()).window], [429, "burst"]);
    p.s.runs = [15, 20, 25, 30].map(pastRun);
    const h = await call();
    assertEquals([h.status, (await h.json()).window], [429, "hour"]);
  } finally {
    p.restore();
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
