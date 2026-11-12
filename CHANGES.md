# CHANGES.md - fixes made to Ayodeji Shodipo's KickOff Arena CA kit (MIT 8103)

The original kit was drafted by the student's AI tool. Claude tested it in a Codespaces-like environment (Ubuntu, PostgreSQL 16, MongoDB 8, user with root-only sudo) and fixed what failed. The student runs everything in their own Codespace.

| # | File | Problem when run | Fix | Tested result |
|---|------|------------------|-----|---------------|
| 1 | setup.sh | Heavy apt installs (PostGIS, extras), python drivers never installed, `use` in a mongosh heredoc, mongod started as root, kickoff role could not log in over the socket | Lean setup: no PostGIS, `db.getSiblingDB`, mongod via `runuser`, hba line at the top for kickoff, Lagos time zone, psycopg + pymongo with a pip fallback chain and an import check | Runs; role, DB, drivers OK |
| 2 | run_p1..p5.sh | Password prompt for `psql -U kickoff` over the socket | `export PGPASSWORD` in each runner | All five run |
| 3 | P1 seed.sql | Demo booking used `now()+1 day` truncated to the hour, so it failed the opening-hours rule at night | Fixed 09:00 Lagos time tomorrow | Seed loads at any hour |
| 4 | P1 schema.sql | Opening-hours CHECK only looked at the end *hour*, so a 3-hour booking from 22:00 (ends 01:00) was accepted | Compare the real end time with 23:00 Lagos | 22:00+3h now rejected |
| 5 | P1 constraint_tests.sql | Tests depended on `now()` time of day and on seed rows deleted by the bulk load; one test passed silently (22:00 booking) and one failed on the wrong constraint (overlap, not team size) | Rewritten: each test builds its own pitch and teams, one control that must succeed (C1), 11 tests each hitting the intended constraint | C1 OK, T1-T11 show intended errors |
| 6 | P2 queries/explain files | CTE named `window` is a reserved word: syntax error, Q6 never ran | Renamed to `win` | All 6 queries run |
| 7 | P2 queries | Full-history queries make indexes pointless | Q1, Q2, Q3 made selective (one day / last 30 days); Q4, Q5 kept as full aggregates on purpose | Q1 1.9 to 1.0 ms, Q6 10.5 to 1.9 ms; Q2/Q4/Q5 stay Seq Scan (explained in README) |
| 8 | run_p2.sh | Not re-runnable fairly (indexes stayed) | Drops P2 indexes and ANALYZEs before the BEFORE run, ANALYZE after indexes | Re-runnable |
| 9 | P3 book_pitch.sql | Same opening-hours flaw; demos used random bulk rows and `now()+N days` plus hours (time-of-day dependent) | Correct check; demos use their own pitch and 6-player team and fixed Lagos times | Happy path + rollback demo work |
| 10 | P3 commit_rollback_demo.sql | `\set ON_ERROR_STOP off -- comment` is invalid psql | Comment moved to its own line | Demo runs |
| 11 | P3 two-terminal demos | Cannot be pasted by hand reliably | New `run_race_demos.py` runs all 6 parts with two real sessions and writes `race_demos_output.log` | Bug reproduced (2 rows), exclusion constraint stops it, FOR UPDATE refuses, SERIALIZABLE aborts one, deadlock detected |
| 12 | P4 all .js | `use db;` is not valid in a script file; NumberLong deprecation spam | `db.getSiblingDB(...)`, NumberLong wrapper | Scripts run |
| 13 | P4 mongo_schema.js | `additionalProperties: false` without `_id` rejected every insert | Added `_id` to properties | Inserts accepted, bad doc rejected |
| 14 | P4 seed_mongo.js | Missing assists stored as null, failed validation, seeding died | Delete undefined assists | 40,000 documents |
| 15 | P4 collscan_ixscan.js | `dropIndex` on a missing index throws, demo dies | try/catch | COLLSCAN 40,000 docs / 101 ms to IXSCAN 38 docs / 2 ms |
| 16 | P5 partitioning.sql | PG 16 rejects EXCLUDE on a partitioned table; script also dropped P1's `match_result`; only 5,000 rows, 13 partitions, no DEFAULT | Rewritten: new table `booking_partitioned`, per-partition EXCLUDE in a loop, DEFAULT partition (0 rows), all 50,003 rows, pruning vs unpartitioned timing, control test. P1 tables untouched | 28 monthly partitions, pruning 1.2 ms vs 16.1 ms |
| 17 | P5 replica | Manual multi-step guide | New `replication_demo.sh` (one script, port 5433, own conf/hba/ident, chmod 700) | Write rejected on replica, row streams across, lag shown |
| 18 | runall.sh / collect_results.sh | n/a | One file runs P1-P5 with logs, commits each, stops on failure, collects `my_results.txt` | Rehearsed from a clean repo |

## Cut or simplified (speed)
Removed PostGIS and extra apt packages; kept 50,000 bookings and 40,000 Mongo documents; replaced the hand-run two-terminal demos and the manual replica guide with scripts. Whole run takes about a minute after setup.

## Things to say at the defence
- A capacity or "check then insert" test alone does not stop a double booking under READ COMMITTED; the exclusion constraint, FOR UPDATE or SERIALIZABLE does (Part 1 vs Parts 2-4).
- Indexes help selective queries only; Q2/Q4/Q5 read most of the table, so a Seq Scan is the right plan.
