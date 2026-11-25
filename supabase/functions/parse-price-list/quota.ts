// parse-price-list 的用量限制：每家批发商一段时间内最多跑几次（每次可能叫十几次 Opus）。
//
// 记录放在 price-lists bucket 的 _runs/<wholesaler_id>/ 下面，一次一个小档（服务器身份写）：
// Storage 的规则只让批发商碰「第一层是自己 id」的资料夹，所以批发商删不掉、也改不了这些记录。
// （price_list_imports 的 status / ai_raw 批发商自己可以改，不能拿来算次数。）
// 先写自己这一笔、再数：同时进来的请求最多多挡，不会多放。被挡下来的那一笔会删掉（不算次数）。

import type { SupabaseClient } from "@supabase/supabase-js";
import { DbError } from "../_shared/supabase.ts";

export const RUNS_PREFIX = "_runs";

export interface QuotaLimits {
  /** 10 分钟内（一次最多跑 400 秒，这个数字差不多就是同时在跑的上限） */
  burst: number;
  hour: number;
  day: number;
}

/** 还没审核通过（pending）的批发商限制比较紧；停权（suspended）的不能跑 */
export const QUOTA: { active: QuotaLimits; pending: QuotaLimits } = {
  active: { burst: 3, hour: 10, day: 30 },
  pending: { burst: 2, hour: 4, day: 8 },
};

const WINDOWS = [
  ["burst", 10 * 60_000],
  ["hour", 60 * 60_000],
  ["day", 24 * 60 * 60_000],
] as const;

/** 超过两天的记录顺手删掉 */
const KEEP_MS = 2 * 24 * 60 * 60_000;

export type QuotaResult =
  | { ok: true; path: string }
  | { ok: false; window: "burst" | "hour" | "day"; retryAfterSec: number };

/** 档名：<毫秒时间>-<run_id>.csv（bucket 只收那几种 MIME，text/csv 是其中一种） */
function markerTime(name: string): number | null {
  const m = /^(\d{13})-/.exec(name);
  return m ? Number(m[1]) : null;
}

function storageError(op: string, e: unknown): DbError {
  const x = (e ?? {}) as Record<string, unknown>;
  const status = Number(x.statusCode ?? x.status ?? 0) || 0;
  return new DbError(op, String(x.message ?? e), "", status);
}

/**
 * 记一笔、再数这家批发商最近跑了几次；超过 → 删掉这一笔，回传 ok:false。
 * Storage 出错 → 丢 DbError（不知道用了多少就不跑）。
 */
export async function reserveRun(
  admin: SupabaseClient,
  bucket: string,
  wholesalerId: string,
  limits: QuotaLimits,
  run: { runId: string; userId: string; importId: string },
  now = Date.now(),
): Promise<QuotaResult> {
  const folder = `${RUNS_PREFIX}/${wholesalerId}`;
  const path = `${folder}/${now}-${run.runId}.csv`;
  const store = admin.storage.from(bucket);
  const up = await store.upload(path, `run_id,user_id,import_id\n${run.runId},${run.userId},${run.importId}\n`, {
    contentType: "text/csv",
    upsert: false,
  });
  if (up.error) throw storageError("reserve run", up.error);

  const list = await store.list(folder, { limit: 100, sortBy: { column: "name", order: "desc" } });
  if (list.error) {
    await store.remove([path]).catch(() => undefined);
    throw storageError("count runs", list.error);
  }
  const times = (list.data ?? []).flatMap((o) => {
    const t = markerTime(o.name);
    return t == null ? [] : [t];
  });
  if (!times.includes(now)) times.push(now); // 列表还没看到自己这笔也算进去
  for (const [window, ms] of WINDOWS) {
    const inWindow = times.filter((t) => t > now - ms).sort((a, b) => a - b);
    if (inWindow.length > limits[window]) {
      await store.remove([path]).catch(() => undefined);
      // 最旧的那一笔过期之后就有位置
      const oldest = inWindow[inWindow.length - limits[window] - 1] ?? now;
      return { ok: false, window, retryAfterSec: Math.max(1, Math.ceil((oldest + ms - now) / 1000)) };
    }
  }
  const stale = (list.data ?? []).filter((o) => (markerTime(o.name) ?? now) < now - KEEP_MS).map((o) =>
    `${folder}/${o.name}`
  );
  if (stale.length > 0) await store.remove(stale).catch(() => undefined);
  return { ok: true, path };
}

/** 没有真的开始跑（例如已经在跑 → 409）：把记录删掉，不算次数 */
export async function releaseRun(admin: SupabaseClient, bucket: string, path: string): Promise<void> {
  await admin.storage.from(bucket).remove([path]).catch(() => undefined);
}
