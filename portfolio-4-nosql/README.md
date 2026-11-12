# Portfolio 4 — NoSQL and Advanced Data Models

**Student:** Ayodeji Shodipo · 2026/A/MIT/0725
**Case study:** KickOff Arena — 5-a-side football pitch booking (Lagos)
**Course-note study sessions covered:**
- **Study Session 1** — *NoSQL & NewSQL types*: the document-store family
  (MongoDB) is one of the four NoSQL families introduced in SS1.
- **Study Session 5** — *Graph databases and knowledge graphs*: the
  comparison in `sql_vs_nosql.md` covers why a graph store would be a
  better fit if relationships were the dominant access pattern.
- **Study Session 3** — *Big Data*: 40k+ documents is a workload where the
  document model pays off (variable shape per match).

## What this portfolio demonstrates

1. A MongoDB collection `kickoff_mongo.match_reports` whose documents store
   the **rich, variable shape** of a 5-a-side match: final score, goal
   scorers (with minute and assist), cards (yellow / red) and free-text
   notes. Different matches have **different shapes** — some have penalty
   shootouts, some have VAR reviews, some have only the final score.
2. A `$jsonSchema` validator on the collection: every document must have a
   `match_id`, `date`, `pitch_id`, `home`/`away` team block with a `score`
   field, and (when present) scorers / cards must follow the schema.
3. A seed script that generates **40 000+ documents** with realistic
   Nigerian player names, varied scorers / cards / notes per match.
4. Aggregation pipelines:
   - **Top scorers** across all matches (`$unwind` scorers → `$group` →
     `$sort`).
   - **Team win rates** (`$group` by team, `$sum` wins, divide by matches
     played).
5. A `COLLSCAN → IXSCAN` demo: a query for "all matches in which player X
   scored" runs a collection scan before the index is created, then an index
   scan after `createIndex({ "scorers.player_id": 1 })`. The two
   `explain("executionStats")` outputs are captured side-by-side.
6. A short `sql_vs_nosql.md` comparison of the relational and document
   models for the same case study.

## Files

| File | Purpose |
|---|---|
| `mongo_schema.js` | Drops + recreates the `match_reports` collection with `$jsonSchema` validator + indexes that are *part of the design* (not the COLLSCAN-demo index — that one is added later). |
| `seed_mongo.js` | Generates and inserts 40 000+ match report documents (variable shape per match). Run with `mongosh`. |
| `aggregations.js` | Top-scorer + team win-rate pipelines. |
| `collscan_ixscan.js` | The same `find()` query run before and after `createIndex({ "scorers.player_id": 1 })`, with `explain("executionStats")` printed both times. |
| `sql_vs_nosql.md` | One-page comparison of the SQL and MongoDB models for the KickOff Arena case study. |
| `run_p4.sh` | Drives the whole portfolio in order. |
| `README.md` | This file. |

## How to run (GitHub Codespaces)

```bash
# after `bash setup.sh` has installed MongoDB 8 and started it:
cd portfolio-4-nosql
bash run_p4.sh
```

## What to screenshot

1. The validator JSON returned by `db.runCommand({ listCollections: 1,
   filter: { name: "match_reports" } })` showing the `$jsonSchema`.
2. The document-count line after `seed_mongo.js` (must be ≥ 40 000).
3. Three sample documents (`db.match_reports.findOne()` is not enough —
   paste three different shapes to show variability).
4. The top-scorer aggregation result table (top 10 scorers).
5. The team win-rate aggregation result table.
6. The `explain("executionStats")` output before the index — focus on
   `COLLSCAN`, `totalDocsExamined` and `executionTimeMillis`.
7. The `createIndex` statement succeeding.
8. The `explain("executionStats")` output after the index — focus on
   `IXSCAN`, `totalDocsExamined` and `executionTimeMillis`.

## Git commit

```bash
git add portfolio-4-nosql
git commit -m "P4: MongoDB schema validation, 40k docs, aggregations, COLLSCAN→IXSCAN, SQL vs NoSQL"
git push
```

## Plain-English explanation

The relational schema from P1 stores the *fixed, structured* part of a match
result (final score, both teams, when it was played). But the actual
on-pitch events — who scored, in which minute, who assisted, who got a card,
the captain's post-match notes, sometimes a penalty shootout — have a
*different shape per match*: a 0–0 draw has no scorers at all; a 5–4 thriller
has up to 9 scorers plus 2 keepers; a cup final has a penalty-shootout block
that a league match never has. Forcing all those shapes into one SQL table
either wastes columns (sparse table) or pushes them into JSON-in-a-column
(lost query power). MongoDB's document model is the natural fit: each match
is one document, the shape can vary, and we still get schema validation
(via `$jsonSchema`) and indexed queries on the bits that matter (e.g.
"player X scored in this match"). This is exactly the document-store family
introduced in Study Session 1, applied to a Big-Data-scale workload from
Study Session 3.
