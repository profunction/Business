#!/usr/bin/env bash
# 重新导出第七步（收费）的示范数据：临时起一个 Postgres（跟 scripts/test-db.sh 一样），跑全部迁移和 seed.sql，
# 再跑 tool/billing_fixtures.sql，结果写进 packages/core/test/fixtures/{buyer_billing*,seller_billing,commission_invoice,payment_paid,admin_payments}.json，
# 最后更新客服后台和手机 App 的 lib/demo/demo_data.dart。
#   ./tool/export_billing_fixtures.sh    （在 apps/admin_web 里跑；端口用 EXPORT_DB_PORT，默认 54345）
set -euo pipefail
APP="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$APP/../.." && pwd)"
PG_BIN="${PG_BIN:-$(pg_config --bindir 2>/dev/null || echo /usr/lib/postgresql/16/bin)}"
PORT="${EXPORT_DB_PORT:-54345}"
WORK="$(mktemp -d)"
OUT="$WORK/out"
mkdir -p "$OUT"
RUN=()
if [ "$(id -u)" = "0" ]; then chown -R postgres "$WORK"; RUN=(runuser -u postgres --); fi
cleanup() { "${RUN[@]}" "$PG_BIN/pg_ctl" -D "$WORK/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT

"${RUN[@]}" "$PG_BIN/initdb" -D "$WORK/data" -U postgres --auth=trust >/dev/null
"${RUN[@]}" "$PG_BIN/pg_ctl" -D "$WORK/data" -l "$WORK/postgres.log" -w \
  -o "-p $PORT -k $WORK -c listen_addresses='' -c timezone=UTC" start >/dev/null
export PGHOST="$WORK" PGPORT="$PORT" PGUSER=postgres PGDATABASE=postgres PGOPTIONS='-c client_min_messages=warning'
PSQL=(psql -X -q -v ON_ERROR_STOP=1)
"${PSQL[@]}" -f "$ROOT/scripts/local-db/supabase_stub.sql"
for f in "$ROOT"/supabase/migrations/*.sql; do "${PSQL[@]}" -f "$f"; done
"${PSQL[@]}" -f "$ROOT/supabase/seed.sql" >/dev/null
"${RUN[@]}" "${PSQL[@]}" -v outdir="$OUT" -f "$APP/tool/billing_fixtures.sql" >/dev/null
cp "$OUT"/*.json "$ROOT/packages/core/test/fixtures/"
echo "导出 $(ls "$OUT" | wc -l) 个 → packages/core/test/fixtures/{buyer_billing*,seller_billing,commission_invoice,payment_paid,admin_payments}.json"
python3 "$APP/tool/gen_demo_data.py"
python3 "$ROOT/apps/mobile/tool/gen_demo_data.py"
