#!/usr/bin/env bash
# =============================================================================
# run_p4.sh — Portfolio 4 driver
# Steps: schema → seed → aggregations → COLLSCAN/IXSCAN.
# Run from the repo root in a Codespaces terminal:
#
#     bash portfolio-4-nosql/run_p4.sh
# =============================================================================
set -euo pipefail
export PGPASSWORD=kickoff_dev_pw

PORTFOLIO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PORTFOLIO_DIR"

MONGOSH="mongosh --quiet"

echo "============================================================"
echo "  Portfolio 4 — NoSQL and Advanced Data Models"
echo "  KickOff Arena · Ayodeji Shodipo · 2026/A/MIT/0725"
echo "============================================================"

echo "[1/4] Creating match_reports collection with \$jsonSchema validator…"
$MONGOSH kickoff_mongo mongo_schema.js 2>&1 | tee mongo_schema.out

echo ""
echo "[2/4] Seeding 40 000+ documents (variable shape per match)…"
$MONGOSH kickoff_mongo seed_mongo.js 2>&1 | tee seed_mongo.out

echo ""
echo "[3/4] Aggregations — top scorers + team win rates + cards by team…"
$MONGOSH kickoff_mongo aggregations.js 2>&1 | tee aggregations.out

echo ""
echo "[4/4] COLLSCAN → IXSCAN demo (same query, before vs after index)…"
$MONGOSH kickoff_mongo collscan_ixscan.js 2>&1 | tee collscan_ixscan.out

echo ""
echo "============================================================"
echo "  Raw output captured to:"
echo "    - mongo_schema.out       (validator + sanity insert)"
echo "    - seed_mongo.out         (40k+ insert + 3 sample docs)"
echo "    - aggregations.out       (top scorers + win rates + cards)"
echo "    - collscan_ixscan.out    (COLLSCAN → IXSCAN before/after plan)"
echo "  Screenshot checklist:"
echo "    1) The \$jsonSchema validator block from mongo_schema.out"
echo "    2) Document count >= 40 000 from seed_mongo.out"
echo "    3) Three sample documents (different shapes)"
echo "    4) Top-10 scorers table from aggregations.out"
echo "    5) Team win-rate table from aggregations.out"
echo "    6) COLLSCAN explain (totalDocsExamined, executionTimeMillis)"
echo "    7) IXSCAN explain (totalKeysExamined, executionTimeMillis)"
echo "    8) sql_vs_nosql.md filled in with real timings"
echo "============================================================"
echo "  Git commit:"
echo "    git add portfolio-4-nosql"
echo "    git commit -m \"P4: MongoDB schema validation, 40k docs, aggregations, COLLSCAN→IXSCAN, SQL vs NoSQL\""
