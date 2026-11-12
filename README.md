# Advanced Database Systems Portfolio — KickOff Arena

**Student:** Ayodeji Shodipo
**Matric number:** 2026/A/MIT/0725
**Programme:** Master of Information Technology, Miva Open University
**Course:** MIT 8103 — Advanced Database Systems (2026/2027, First Semester CA)
**GitHub link:** `[GitHub link]`  ← paste the real URL of your private repo here before submission.

---

## 1. Selected case study

**Organisation:** KickOff Arena (simulated company).
**Business:** Operates 5-a-side football pitches across several Lagos locations —
Lekki, Yaba, Ikeja and Surulere. Teams book pitches by the hour, pay online,
and record match results.

**Users of the database:**
- Operations staff (manage locations, pitches, pricing)
- Team captains (book pitches, register players, view invoices)
- Players (view fixtures, match results, top-scorer leaderboards)
- Finance (revenue, refunds, no-show reconciliation)
- Analytics (pitch utilisation, peak-hour demand)

**Major data stored:**
- Master data: locations, pitches, teams, players, team membership, pricing
  (peak vs off-peak)
- Transactional data: hourly bookings, payments, match results
- Reporting data: revenue per location per month, utilisation %, top teams,
  no-show rate, top scorers (MongoDB aggregation)

**Key operations the database supports:**
- Book a pitch for 1–3 hours starting on the hour, between 07:00 and 23:00
- Take a deposit when the booking is created; refund / cancel on payment failure
- Prevent two teams from booking the same pitch for overlapping hours
- Enforce that a team must have at least 5 registered players before booking
- Record match results (final score, scorers, cards, notes) with a flexible
  shape per match (MongoDB)
- Run analytics on revenue, utilisation, peak demand and player performance
- Replicate to a read-only streaming replica and partition bookings by month

## 2. Repository layout

```
advanced-database-portfolio/
├── README.md                              ← this file
├── setup.sh                               ← installs + starts PostgreSQL 16 and MongoDB 8
├── portfolio-1-database-design/
├── portfolio-2-query-optimisation/
├── portfolio-3-transactions-concurrency/
├── portfolio-4-nosql/
└── portfolio-5-distributed-cloud/
```

Each portfolio folder contains its own `README.md` describing what it
demonstrates and which course-note study session it covers, plus a `run_pN.sh`
helper script.

## 3. Bootstrap the environment (Codespaces)

In a GitHub Codespace terminal, from the repo root:

```bash
bash setup.sh
```

This installs PostgreSQL 16 + MongoDB 8, creates the `kickoff` PostgreSQL
database (with the `btree_gist` and `pgcrypto` extensions) and the
`kickoff_mongo` MongoDB database.

Codespaces-specific notes (all enforced inside `setup.sh` and the per-portfolio
run scripts):

| Concern | Rule used |
|---|---|
| Acting as the `postgres` OS user | `sudo runuser -u postgres -- …`, never `sudo -u postgres …` |
| PostgreSQL config path | `/etc/postgresql/16/main/` (start via `pg_ctlcluster 16 main start`) |
| `pg_ctl` binary | `/usr/lib/postgresql/16/bin/pg_ctl` |
| TCP logins need a password | All `psql` calls connect through the Unix socket: `-h /var/run/postgresql` |
| Foreign data wrappers | `postgres_fdw` is **not** used anywhere |
| Broken apt source | `/etc/apt/sources.list.d/yarn.list` is removed before `apt-get update` |
| Dates | All seed data is generated **relative to today**, never fixed dates that expire |

## 4. Per-portfolio run + commit workflow

| Portfolio | Run | Screenshot to capture | Commit |
|---|---|---|---|
| 1 — Database design | `bash portfolio-1-database-design/run_p1.sh` | ER diagram render, schema applied, bulk-seed row counts, each failing constraint test | `git add portfolio-1-database-design && git commit -m "P1: schema, 3NF, bulk seed, constraint tests"` |
| 2 — Query optimisation | `bash portfolio-2-query-optimisation/run_p2.sh` | Each query result + its `EXPLAIN ANALYZE` before and after the index | `git add portfolio-2-query-optimisation && git commit -m "P2: queries + EXPLAIN ANALYZE before/after indexes"` |
| 3 — Transactions & concurrency | `bash portfolio-3-transactions-concurrency/run_p3.sh` (then the two-terminal guide) | `COMMIT`/`ROLLBACK` output, race-condition double-booking, exclusion rejection, `FOR UPDATE` blocking, deadlock abort | `git add portfolio-3-transactions-concurrency && git commit -m "P3: book_pitch() transaction, race-condition fixes, isolation levels, deadlock"` |
| 4 — NoSQL | `bash portfolio-4-nosql/run_p4.sh` | Collection validator, 40k+ insert count, top-scorer aggregation result, COLLSCAN → IXSCAN explain output | `git add portfolio-4-nosql && git commit -m "P4: MongoDB schema validation, 40k docs, aggregations, COLLSCAN→IXSCAN, SQL vs NoSQL"` |
| 5 — Distributed & cloud | `bash portfolio-5-distributed-cloud/run_p5.sh` (then the replication guide) | Partition pruning plan, replica rejecting a write, replica reading a fresh row, cloud architecture diagram | `git add portfolio-5-distributed-cloud && git commit -m "P5: monthly partitioning, streaming replica, Nigeria-resident cloud architecture"` |

## 5. Honesty about AI assistance

AI tools (a coding assistant) were used to:
1. Draft the SQL schema, the bulk-data generator, the MongoDB seed script and
   the run-shell scripts.
2. Draft the ER diagram (Mermaid) and the markdown explanations.

Every script was reviewed, corrected where needed, and **must be re-run by the
student** in a Codespace to capture the real outputs. Where a result depends on
real execution, the file uses the placeholder `[paste real output here]` —
never a fabricated value. The final 2–3 page documentation PDF will only be
produced after the student has run everything and pasted the real outputs.

AI-use declaration (to be expanded in the final documentation):

> *AI tool used:* a coding assistant.
> *Used for:* drafting SQL/JS/shell scripts, ER diagrams and explanations.
> *How reviewed:* the student read every script, ran it in a Codespace, fixed
> errors, and pasted real execution output into the result placeholders. The
> student understands and can explain every line during viva.

## 6. Final documentation (later step)

After all five portfolios have been run and the real outputs captured, a
2–3 page PDF will be produced:

```
Shodipo_Ayodeji_2026-A-MIT-0725_Documentation.pdf
```

It will use only the student's real results, include the GitHub link, contain
a short individual technical reflection, and an honest AI-use declaration.

## 7. Mapping of portfolios to course-note study sessions

| Portfolio | Course-note study session(s) covered |
|---|---|
| P1 — Database design & modelling | Study Session 1 (Review of Traditional Relational Databases & Advanced Concepts): ER modelling, normalisation, keys, constraints, integrity. |
| P2 — Query processing & optimisation | Study Session 4 (Query Optimisation in Database): query execution plans, cost estimation, file organisation & indexing. |
| P3 — Transactions & concurrency | Study Session 2 (Distributed Database System): ACID, BASE, consistency models; Study Session 1 conclusion: "concurrency control issues" of traditional DBMS. |
| P4 — NoSQL & advanced data models | Study Session 1 (NoSQL & NewSQL types); Study Session 5 (graph databases & knowledge graphs); Study Session 3 (Big Data). |
| P5 — Distributed & cloud database | Study Session 2 (DDB architecture, replication, fragmentation, CAP, sync vs async); Study Session 3 (Cloud DB systems & use cases); Study Session 6 (Data Privacy — NDPA 2023, CBN data-localisation). |
