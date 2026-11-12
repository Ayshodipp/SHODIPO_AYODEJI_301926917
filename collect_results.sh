#!/usr/bin/env bash
# collect_results.sh - gathers REAL output from the five portfolio logs into my_results.txt
cd "$(dirname "$(readlink -f "$0")")"
OUT=my_results.txt
sec() { echo; echo "################ $1 ################"; }
show() { if [ -f "$1" ]; then cat "$1"; else echo "(no $1 - this portfolio did not run)"; fi; }
{
echo "MY RESULTS - KickOff Arena - Ayodeji Shodipo - generated $(date)"
sec "P1 row counts + constraint tests"
if [ -f portfolio-1-database-design/p1_output.log ]; then
  grep -E "^ (locations|pitches|teams|players|team_members|pricing_rows|bookings|payments|match_results) " portfolio-1-database-design/p1_output.log | tail -9
  grep -E "====== (C1|T[0-9]+)|ERROR:|INSERT 0 1" portfolio-1-database-design/p1_output.log | sed -n '/C1/,$p'
else echo "(no p1_output.log)"; fi
sec "P2 EXPLAIN ANALYZE before vs after indexes (execution times)"
for f in explain_before.out explain_after.out; do
  echo "--- $f"; grep -E "====== Q|Execution Time" portfolio-2-query-optimisation/$f 2>/dev/null || echo "(no $f)"
done
sec "P3 transactions + concurrency demos"
show portfolio-3-transactions-concurrency/race_demos_output.log
sec "P4 MongoDB (documents, COLLSCAN to IXSCAN)"
if [ -f portfolio-4-nosql/p4_output.log ]; then
  grep -E "Done. match_reports.countDocuments|Target player_id|Count of matches" portfolio-4-nosql/p4_output.log
  sed -n '/BEFORE vs AFTER summary/,/^====/p' portfolio-4-nosql/p4_output.log
else echo "(no p4_output.log)"; fi
sec "P5 partitioning + replica"
if [ -f portfolio-5-distributed-cloud/partitioning_output.log ]; then
  sed -n '/Partitions and rows/,$p' portfolio-5-distributed-cloud/partitioning_output.log | grep -v "^$" | head -70
else echo "(no partitioning_output.log)"; fi
show portfolio-5-distributed-cloud/replication_output.log
} > $OUT 2>&1
echo "Wrote $(pwd)/$OUT  ($(wc -l < $OUT) lines)"
