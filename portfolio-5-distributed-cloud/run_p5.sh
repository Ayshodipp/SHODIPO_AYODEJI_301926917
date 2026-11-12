#!/usr/bin/env bash
# =============================================================================
# run_p5.sh — Portfolio 5 driver (the in-script parts; the streaming-replica
# walkthrough in replication_setup.md is run by hand).
# Run from the repo root in a Codespaces terminal:
#
#     bash portfolio-5-distributed-cloud/run_p5.sh
# =============================================================================
set -euo pipefail
export PGPASSWORD=kickoff_dev_pw

PORTFOLIO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PORTFOLIO_DIR"

PSQL="psql -v ON_ERROR_STOP=1 -h /var/run/postgresql -U kickoff kickoff"
PSQL_AS_PG="sudo runuser -u postgres -- psql -d kickoff -v ON_ERROR_STOP=1"

echo "============================================================"
echo "  Portfolio 5 — Distributed and Cloud Database Exercise"
echo "  KickOff Arena · Ayodeji Shodipo · 2026/A/MIT/0725"
echo "============================================================"

echo "[1/2] Partitioning: booking copy by month, pruning, per-partition no-overlap rule..."
$PSQL_AS_PG -f partitioning.sql 2>&1 | tee partitioning_output.log

echo ""
echo "[2/2] Streaming replica (primary + hot standby), one script..."
bash replication_demo.sh 2>&1 | tee replication_output.log

echo ""
echo "============================================================"
echo "  Git commit:"
echo "    git add portfolio-5-distributed-cloud"
echo "    git commit -m \"P5: monthly partitioning, streaming replica, Nigeria-resident cloud architecture\""
