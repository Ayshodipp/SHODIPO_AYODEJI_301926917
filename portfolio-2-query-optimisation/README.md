# Portfolio 2 — Query Processing and Optimisation

**Student:** Ayodeji Shodipo · 2026/A/MIT/0725
**Case study:** KickOff Arena — 5-a-side football pitch booking (Lagos)
**Course-note study session covered:** Study Session 4 — *Query Optimisation
in Database* (query execution plans, cost estimation, file organisation &
indexing).

## What this portfolio demonstrates

1. Six analytics queries against the KickOff Arena schema from P1:
   - **Q1** Free slots at a location for a given date.
   - **Q2** Revenue per location per month.
   - **Q3** Peak-hour usage (peak = 17:00–23:00 weekdays + all day weekends).
   - **Q4** Top teams by number of bookings.
   - **Q5** No-show rate.
   - **Q6** Pitch utilisation %.
2. `EXPLAIN ANALYZE` for each query **before** adding indexes (mostly
   `Seq Scan` on the big `booking` table).
3. A focused set of indexes (`indexes.sql`) — chosen by inspecting the
   before-plans.
4. `EXPLAIN ANALYZE` for each query **after** the indexes (mostly `Index Scan`
   or `Bitmap Heap Scan`).
5. A before/after results template (`results_template.md`) where the student
   pastes real timings captured from the Codespace — never fabricated.

## Files

| File | Purpose |
|---|---|
| `queries.sql` | The 6 queries, runnable as-is against the seeded DB. |
| `explain_before.sql` | `EXPLAIN (ANALYZE, BUFFERS)` for each query, **no extra indexes**. |
| `indexes.sql` | The indexes added in the optimisation step. |
| `explain_after.sql` | `EXPLAIN (ANALYZE, BUFFERS)` for each query **after** `indexes.sql`. |
| `results_template.md` | Markdown table with `[paste real output here]` placeholders for the student to fill from the real run. |
| `run_p2.sh` | Runs the four steps in order and prints plans to stdout. |
| `README.md` | This file. |

## How to run (GitHub Codespaces)

```bash
# after P1 has run (so the schema + bulk seed exist):
cd portfolio-2-query-optimisation
bash run_p2.sh
```

## What to screenshot

1. The result table of each of Q1–Q6 (the actual rows).
2. The **before** `EXPLAIN ANALYZE` plan of each query (focus on
   `Seq Scan` and `actual time` lines).
3. The `CREATE INDEX` statements succeeding (`indexes.sql`).
4. The **after** `EXPLAIN ANALYZE` plan of each query (focus on
   `Index Scan`/`Bitmap Heap Scan` and the new `actual time`).
5. Fill in the `results_template.md` table with the real timings you copied
   from the terminal.

## Git commit

```bash
git add portfolio-2-query-optimisation
git commit -m "P2: 6 analytics queries + EXPLAIN ANALYZE before/after indexes"
git push
```

## Plain-English explanation

Each query is something KickOff Arena's manager would actually ask: "what's
free at Lekki tomorrow?", "how much did each location earn last month?", "which
teams book the most?", "how often do teams just not show up?". On a freshly
seeded database with 50 000+ bookings, the planner starts with sequential
scans because no useful index exists. We capture those plans, add the indexes
that match the query predicates (e.g. an index on `booking(start_time)` for
Q1 and Q3, an index on `payment(paid_at)` for Q2), and re-run the same
`EXPLAIN ANALYZE` to show the planner switching to index scans and the
execution time dropping. This is exactly the query-execution-plan +
cost-estimation workflow from Study Session 4 of the course notes.

---
## Honest note on the results (added after testing)
Run `bash run_p2.sh`: it drops the P2 indexes first, runs the BEFORE plans, creates the indexes, runs ANALYZE and the AFTER plans. Queries 1 and 6 (selective: one day / last 30 days) improve clearly. Queries 2, 4 and 5 read most of a 50,000-row table, so PostgreSQL correctly keeps a Seq Scan/Hash Join and the index brings no gain; small slower or faster timings there are run-to-run noise. Quote your own numbers from explain_before.out and explain_after.out.
