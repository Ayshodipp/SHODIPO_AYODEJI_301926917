#!/usr/bin/env bash
# =============================================================================
# run_p3.sh — Portfolio 3 driver (the in-script parts; the two-terminal parts
# are run by hand following race_condition_guide.md, isolation_levels.sql and
# deadlock_demo.sql).
# Run from the repo root in a Codespaces terminal:
#
#     bash portfolio-3-transactions-concurrency/run_p3.sh
# =============================================================================
set -euo pipefail
export PGPASSWORD=kickoff_dev_pw

PORTFOLIO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PORTFOLIO_DIR"

PSQL="psql -h /var/run/postgresql -U kickoff kickoff"
PSQL_AS_PG="sudo runuser -u postgres -- psql -d kickoff"

echo "============================================================"
echo "  Portfolio 3 — Transactions and Concurrency"
echo "  KickOff Arena · Ayodeji Shodipo · 2026/A/MIT/0725"
echo "============================================================"

echo "[1/3] Installing book_pitch() function + happy-path + failing-path demo…"
$PSQL -v ON_ERROR_STOP=1 -f book_pitch.sql | tee book_pitch_output.log

echo ""
echo "[2/3] COMMIT / ROLLBACK / SAVEPOINT demo…"
$PSQL -v ON_ERROR_STOP=0 -f commit_rollback_demo.sql | tee commit_rollback_output.log

echo ""
echo "[3/3] Concurrency demos (race bug, exclusion fix, FOR UPDATE, SERIALIZABLE, isolation, deadlock) - two real sessions..."
python3 run_race_demos.py 2>&1 | tee race_demos_output.log

echo ""
echo "============================================================"
echo "  Evidence saved: book_pitch_output.log, commit_rollback_output.log, race_demos_output.log"
echo "  Screenshot: happy-path booking, rollback counts, each of the 6 race-demo parts."
echo "============================================================"
echo "  Git commit:"
echo "    git add portfolio-3-transactions-concurrency"
echo "    git commit -m \"P3: book_pitch() transaction, race-condition fixes, isolation levels, deadlock\""
