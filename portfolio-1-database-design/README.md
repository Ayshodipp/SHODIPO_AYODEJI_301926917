# Portfolio 1 — Database Design and Modelling

**Student:** Ayodeji Shodipo · 2026/A/MIT/0725
**Case study:** KickOff Arena — 5-a-side football pitch booking (Lagos)
**Course-note study session covered:** Study Session 1 — *Review of Traditional
Relational Databases and Advanced Concepts* (ER modelling, normalisation,
keys, constraints, integrity).

## What this portfolio demonstrates

1. A realistic ER model for KickOff Arena, drawn as a Mermaid `erDiagram`.
2. The relational schema in 3NF for 9 tables: `location`, `pitch`, `team`,
   `player`, `team_member`, `booking`, `payment`, `match_result`, `pricing`.
3. The five required constraints implemented in PostgreSQL 16:
   - No two bookings on the same pitch overlap → **exclusion constraint** on
     a `tstzrange` column using the `btree_gist` extension.
   - Bookings start on the hour and last 1–3 hours → `CHECK`.
   - Bookings only inside opening hours (07:00–23:00) → `CHECK`.
   - Payment amount > 0 → `CHECK`.
   - A team needs at least 5 players to book → **trigger** + function.
4. Small seed data + a Python bulk generator that produces 50 000+ bookings
   spread across 2 years, with no overlaps and realistic Lagos names and peak /
   off-peak prices.
5. A constraint-test script whose every statement **must fail** (used as
   evidence the constraints actually fire).

## Files

| File | Purpose |
|---|---|
| `er_diagram.md` | Mermaid ER diagram for the 9 tables. |
| `normalisation_notes.md` | 3NF walkthrough for each table. |
| `schema.sql` | DDL: extensions, tables, constraints, indexes, trigger. |
| `seed.sql` | Small hand-written seed (4 locations, pitches, 2 teams, etc.). |
| `bulk_seed.py` | Generates 50k+ bookings over 2 years, no overlaps. |
| `constraint_tests.sql` | Statements that must fail with the right SQLSTATE. |
| `run_p1.sh` | Runs schema → seed → bulk seed → constraint tests in order. |
| `README.md` | This file. |

## How to run (GitHub Codespaces)

```bash
# from the repo root, after `bash setup.sh` has succeeded:
cd portfolio-1-database-design
bash run_p1.sh
```

`run_p1.sh` connects to PostgreSQL through the Unix socket
(`-h /var/run/postgresql`) as required by the Codespaces rules — no TCP, no
password prompt.

## What to screenshot (for the LMS submission)

1. The rendered Mermaid ER diagram (use the GitHub web view of
   `er_diagram.md` — GitHub renders Mermaid natively).
2. The `\dt` output of `psql -d kickoff -c "\dt"` after `schema.sql` runs,
   showing all 9 tables.
3. The `\d booking` output showing the exclusion constraint and CHECKs.
4. The row counts after `bulk_seed.py` finishes (`SELECT count(*) FROM
   booking;` should be ≥ 50 000).
5. Each `psql:constraint_tests.sql:LINE: ERROR …` line produced by
   `constraint_tests.sql` (one screenshot per failing test is ideal).

## Git commit

```bash
git add portfolio-1-database-design
git commit -m "P1: ER diagram, 3NF schema, bulk seed (50k+), constraint tests"
git push
```

## Plain-English explanation

The schema models the day-to-day operations of a 5-a-side pitch operator:
locations host pitches, teams of players book pitches by the hour and pay
online, and the result of each booked match is recorded. The five constraints
map directly to the operator's real business rules — no pitch can be sold
twice for the same hour, you cannot book for 90 minutes or at 2 a.m., a payment
of ₦0 makes no sense, and a team that has not yet recruited a full 5-a-side
line-up is not allowed to lock up a pitch. This is the relational design half
of Study Session 1 of the course notes.
