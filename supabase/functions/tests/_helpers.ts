// 测试共用：假的 fetch（PostgREST、Storage、Auth、FCM、Google OAuth、Graph API、Anthropic 都在这里模拟）和环境变量。

export const SB_URL = "http://sb.test";
export const SECRET = "sb_secret_test_0123456789";
export const PUBLISHABLE = "sb_publishable_test_abcdef";
/** 旧项目的 service_role key（JWT） */
export const LEGACY_SERVICE_KEY = "legacy-service-role-jwt";

export interface Call {
  method: string;
  url: URL;
  headers: Headers;
  text: string;
  // deno-lint-ignore no-explicit-any
  json: () => any;
}

export type Route = (c: Call) => Response | Promise<Response | undefined | null> | undefined | null;

/** 换掉 globalThis.fetch。没有对到的请求丢错（不会真的连网），也记在 unexpected。 */
export function fakeFetch(route: Route): { calls: Call[]; unexpected: string[]; restore: () => void } {
  const original = globalThis.fetch;
  const calls: Call[] = [];
  const unexpected: string[] = [];
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const req = new Request(input, init);
    const text = req.body ? await req.text() : "";
    const c: Call = {
      method: req.method,
      url: new URL(req.url),
      headers: req.headers,
      text,
      json: () => JSON.parse(text),
    };
    calls.push(c);
    const res = await route(c);
    if (!res) {
      unexpected.push(`${c.method} ${c.url}`);
      throw new TypeError(`unexpected fetch ${c.method} ${c.url}`);
    }
    return res;
  }) as typeof fetch;
  return { calls, unexpected, restore: () => (globalThis.fetch = original) };
}

/** 设环境变量；回传还原的函数。undefined = 删掉 */
export function setEnv(vars: Record<string, string | undefined>): () => void {
  const before: Record<string, string | undefined> = {};
  for (const [k, v] of Object.entries(vars)) {
    before[k] = Deno.env.get(k);
    if (v === undefined) Deno.env.delete(k);
    else Deno.env.set(k, v);
  }
  return () => {
    for (const [k, v] of Object.entries(before)) {
      if (v === undefined) Deno.env.delete(k);
      else Deno.env.set(k, v);
    }
  };
}

export const SUPABASE_ENV = {
  SUPABASE_URL: SB_URL,
  SUPABASE_SECRET_KEYS: JSON.stringify({ default: SECRET }),
  SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({ default: PUBLISHABLE }),
  SUPABASE_SERVICE_ROLE_KEY: undefined,
  SUPABASE_ANON_KEY: undefined,
};

/** PostgREST 的错误回应（数据库 raise exception 的样子） */
export function pgError(message: string, code = "P0001", status = 400): Response {
  return Response.json({ message, code, details: null, hint: null }, { status });
}

/** 是不是用 secret key 叫的 PostgREST / Storage */
export function isService(c: Call): boolean {
  const key = c.headers.get("apikey");
  return c.url.origin === SB_URL && (key === SECRET || key === LEGACY_SERVICE_KEY);
}

export function rpcName(c: Call): string | null {
  const m = /^\/rest\/v1\/rpc\/([a-z_]+)$/.exec(c.url.pathname);
  return c.url.origin === SB_URL && c.method === "POST" && m ? m[1] : null;
}

// ---------------------------------------------------------------------------
// Anthropic 的 SSE（streaming）回应
// ---------------------------------------------------------------------------

export interface FakeClaudeOptions {
  /** text block 的内容（可以几段，中间插 fallback block） */
  blocks: ({ type: "text"; text: string } | { type: "fallback"; from: string; to: string } | { type: "thinking" })[];
  stopReason?: string;
  stopDetails?: Record<string, unknown> | null;
  model?: string;
}

function sse(event: string, data: unknown): string {
  return `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
}

export function claudeStream(o: FakeClaudeOptions): Response {
  const model = o.model ?? "claude-opus-5-5";
  let body = sse("message_start", {
    type: "message_start",
    message: {
      id: "msg_test",
      type: "message",
      role: "assistant",
      model,
      content: [],
      stop_reason: null,
      stop_sequence: null,
      stop_details: null,
      usage: { input_tokens: 1200, output_tokens: 1, cache_read_input_tokens: 0, cache_creation_input_tokens: 1100 },
    },
  });
  o.blocks.forEach((b, index) => {
    if (b.type === "thinking") {
      body += sse("content_block_start", {
        type: "content_block_start",
        index,
        content_block: { type: "thinking", thinking: "", signature: "" },
      });
      body += sse("content_block_delta", {
        type: "content_block_delta",
        index,
        delta: { type: "signature_delta", signature: "sig" },
      });
    } else if (b.type === "fallback") {
      body += sse("content_block_start", {
        type: "content_block_start",
        index,
        content_block: {
          type: "fallback",
          from: { model: b.from },
          to: { model: b.to },
          trigger: { type: "refusal", category: "cyber" },
        },
      });
    } else {
      body += sse("content_block_start", {
        type: "content_block_start",
        index,
        content_block: { type: "text", text: "" },
      });
      // 分两段送，测试 delta 会接起来
      const half = Math.floor(b.text.length / 2);
      for (const part of [b.text.slice(0, half), b.text.slice(half)]) {
        if (part) {
          body += sse("content_block_delta", {
            type: "content_block_delta",
            index,
            delta: { type: "text_delta", text: part },
          });
        }
      }
    }
    body += sse("content_block_stop", { type: "content_block_stop", index });
  });
  body += sse("message_delta", {
    type: "message_delta",
    delta: { stop_reason: o.stopReason ?? "end_turn", stop_sequence: null, stop_details: o.stopDetails ?? null },
    usage: { output_tokens: 321 },
  });
  body += sse("message_stop", { type: "message_stop" });
  return new Response(body, {
    status: 200,
    headers: { "content-type": "text/event-stream", "request-id": "req_test" },
  });
}

export function isAnthropic(c: Call): boolean {
  return c.url.host === "api.anthropic.com" && c.url.pathname === "/v1/messages";
}

/** 一份正常的价目表结果 */
export function extractionJson(rows: Record<string, unknown>[], unreadable: Record<string, unknown>[] = []): string {
  return JSON.stringify({
    supplier_name: "JB Packaging Supply",
    order_min_sen: 30000,
    document_notes: null,
    rows: rows.map((r) => ({
      name: "16oz PP cup",
      unit: "carton",
      unit_raw: "ctn",
      pack_qty: 1000,
      price_sen: 8500,
      min_order_qty: null,
      confidence: 0.95,
      raw_text: "16oz PP cup 1000pcs/ctn RM85.00",
      source_ref: "p1 line 3",
      notes: null,
      ...r,
    })),
    unreadable,
  });
}

/** 让 EdgeRuntime.waitUntil 存在（收集背景工作，测试再 await） */
export function fakeEdgeRuntime(): { pending: Promise<unknown>[]; restore: () => void } {
  const g = globalThis as { EdgeRuntime?: unknown };
  const before = g.EdgeRuntime;
  const pending: Promise<unknown>[] = [];
  g.EdgeRuntime = { waitUntil: (p: Promise<unknown>) => pending.push(p) };
  return {
    pending,
    restore: () => {
      if (before === undefined) delete g.EdgeRuntime;
      else g.EdgeRuntime = before;
    },
  };
}
