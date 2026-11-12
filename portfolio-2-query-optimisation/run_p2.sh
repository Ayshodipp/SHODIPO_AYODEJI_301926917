#!/usr/bin/env bash
# =============================================================================
# run_p2.sh — Portfolio 2 driver
# Steps: queries → explain_before → indexes → explain_after → results table.
# Run from the repo root in a Codespaces terminal:
#
#     bash portfolio-2-query-optimisation/run_p2.sh
# =============================================================================
set -euo pipefail
export PGPASSWORD=kickoff_dev_pw

PORTFOLIO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PORTFOLIO_DIR"

PSQL="psql -v ON_ERROR_STOP=1 -h /var/run/postgresql -U kickoff kickoff"
PSQL_AS_PG="sudo runuser -u postgres -- psql -d kickoff -v ON_ERROR_STOP=1"

echo "============================================================"
echo "  Portfolio 2 — Query Processing and Optimisation"
echo "  KickOff Arena · Ayodeji Shodipo · 2026/A/MIT/0725"
echo "============================================================"

# Fair, re-runnable BEFORE: drop the P2 indexes, refresh statistics.
$PSQL -q -c "DROP INDEX IF EXISTS idx_booking_status_start, idx_payment_paid_at_succeeded, idx_payment_booking_id, idx_team_id_booking, idx_match_result_booking_id, idx_booking_time_range_gist; ANALYZE;"

echo "[1/5] Running the 6 analytics queries (results visible) …"
$PSQL -f queries.sql > queries_output.txt 2>&1; tail -5 queries_output.txt

echo ""
echo "[2/5] EXPLAIN ANALYZE BEFORE indexes (capture Seq Scan + Execution Time) …"
$PSQL -f explain_before.sql 2>&1 | tee explain_before.out

echo ""
echo "[3/5] Creating optimisation indexes (indexes.sql) …"
$PSQL -f indexes.sql; $PSQL -q -c "ANALYZE;"

echo ""
echo "[4/5] EXPLAIN ANALYZE AFTER indexes (capture Index Scan + Execution Time) …"
$PSQL -f explain_after.sql 2>&1 | tee explain_after.out

echo ""
echo "[5/5] Reminder: paste real plans and timings into results_template.md"
echo "      Files saved for your convenience:"
echo "        - explain_before.out   (raw EXPLAIN ANALYZE plans BEFORE)"
echo "        - explain_after.out     (raw EXPLAIN ANALYZE plans AFTER)"
echo "        - results_template.md   (paste the timings into the placeholders)"

echo ""
echo "============================================================"
echo "  Screenshot checklist:"
echo "    1) Each query's result table from queries.sql"
echo "    2) The BEFORE plan of each query (note Seq Scan + Execution Time)"
echo "    3) The CREATE INDEX output from indexes.sql"
echo "    4) The AFTER plan of each query (note Index Scan + Execution Time)"
echo "    5) The filled-in results_template.md table"
echo "============================================================"
echo "  Git commit:"
echo "    git add portfolio-2-query-optimisation"
echo "    git commit -m \"P2: 6 analytics queries + EXPLAIN ANALYZE before/after indexes\""
