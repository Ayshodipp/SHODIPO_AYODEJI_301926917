#!/usr/bin/env bash
# =============================================================================
# run_p1.sh — Portfolio 1 driver
# Steps: schema → seed → bulk_seed → constraint tests → verify counts.
# Run from the repo root in a Codespaces terminal:
#
#     bash portfolio-1-database-design/run_p1.sh
# =============================================================================
set -euo pipefail
export PGPASSWORD=kickoff_dev_pw

PORTFOLIO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PORTFOLIO_DIR"

PSQL="psql -v ON_ERROR_STOP=1 -h /var/run/postgresql -U kickoff kickoff"
PSQL_AS_PG="sudo runuser -u postgres -- psql -d kickoff -v ON_ERROR_STOP=1"
PY="python3"

echo "============================================================"
echo "  Portfolio 1 — Database Design and Modelling"
echo "  KickOff Arena · Ayodeji Shodipo · 2026/A/MIT/0725"
echo "============================================================"

echo "[1/6] Applying schema.sql (DDL + constraints + triggers)…"
$PSQL_AS_PG -f schema.sql

echo "[2/6] Applying seed.sql (4 locations, 12 pitches, 2 teams, 9 players, 1 booking)…"
$PSQL_AS_PG -f seed.sql

echo "[3/6] Generating 50 000+ bookings via bulk_seed.py (this takes ~1–3 min)…"
$PY bulk_seed.py

echo "[4/6] Listing tables and key constraints…"
$PSQL -c "\dt"
$PSQL -c "\d booking"
$PSQL -c "\d payment"

echo "[5/6] Row counts after bulk seed…"
$PSQL -c "
SELECT 'locations'    AS t, count(*) FROM location
UNION ALL SELECT 'pitches',       count(*) FROM pitch
UNION ALL SELECT 'teams',        count(*) FROM team
UNION ALL SELECT 'players',      count(*) FROM player
UNION ALL SELECT 'team_members', count(*) FROM team_member
UNION ALL SELECT 'pricing_rows', count(*) FROM pricing
UNION ALL SELECT 'bookings',     count(*) FROM booking
UNION ALL SELECT 'payments',     count(*) FROM payment
UNION ALL SELECT 'match_results',count(*) FROM match_result
ORDER BY t;"

echo "[6/6] Running constraint_tests.sql — every test must FAIL with an ERROR…"
$PSQL -f constraint_tests.sql

echo "============================================================"
echo "  Portfolio 1 done. Capture screenshots of:"
echo "    1) the rendered ER diagram (er_diagram.md on GitHub)"
echo "    2) \\dt + \\d booking output"
echo "    3) the row counts above (bookings >= 50 000)"
echo "    4) each ERROR line produced by constraint_tests.sql"
echo "============================================================"
echo "  Git commit:"
echo "    git add portfolio-1-database-design"
echo "    git commit -m \"P1: ER diagram, 3NF schema, bulk seed (50k+), constraint tests\""
