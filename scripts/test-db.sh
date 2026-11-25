#!/usr/bin/env bash
# 不用 Docker 的数据库测试：在本机临时起一个 Postgres，跑全部迁移、种子数据和 pgTAP 测试，
# 跑完自动删掉。需要：Postgres（15 以上）、pgTAP、pg_prove。
#
#   ./scripts/test-db.sh
#
# 有 Docker 的话，也可以用 Supabase 官方做法：
#   npx supabase start && npx supabase db reset && npx supabase test db
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PG_BIN="${PG_BIN:-$(pg_config --bindir 2>/dev/null || echo /usr/lib/postgresql/16/bin)}"
PORT="${TEST_DB_PORT:-54329}"
WORK="$(mktemp -d)"

RUN=()
if [ "$(id -u)" = "0" ]; then
  # Postgres 不肯用 root 跑
  chown postgres "$WORK"
  RUN=(runuser -u postgres --)
fi

cleanup() {
  "${RUN[@]}" "$PG_BIN/pg_ctl" -D "$WORK/data" -m immediate stop >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

"${RUN[@]}" "$PG_BIN/initdb" -D "$WORK/data" -U postgres --auth=trust >/dev/null
"${RUN[@]}" "$PG_BIN/pg_ctl" -D "$WORK/data" -l "$WORK/postgres.log" -w \
  -o "-p $PORT -k $WORK -c listen_addresses='' -c timezone=UTC" start >/dev/null

export PGHOST="$WORK" PGPORT="$PORT" PGUSER=postgres PGDATABASE=postgres
PSQL=(psql -X -q -v ON_ERROR_STOP=1 --set=client_min_messages=warning)

echo "== 模拟 Supabase 平台"
"${PSQL[@]}" -f "$ROOT/scripts/local-db/supabase_stub.sql"

echo "== 迁移"
for f in "$ROOT"/supabase/migrations/*.sql; do
  echo "   $(basename "$f")"
  PGOPTIONS='-c client_min_messages=warning' "${PSQL[@]}" -f "$f"
done

echo "== 种子数据"
PGOPTIONS='-c client_min_messages=warning' "${PSQL[@]}" -f "$ROOT/supabase/seed.sql" >/dev/null

echo "== 测试"
pg_prove --ext .sql -r "$ROOT/supabase/tests/database"
