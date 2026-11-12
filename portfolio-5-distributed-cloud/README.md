# Portfolio 5 — Distributed and Cloud Database Exercise

**Student:** Ayodeji Shodipo · 2026/A/MIT/0725
**Case study:** KickOff Arena — 5-a-side football pitch booking (Lagos)
**Course-note study sessions covered:**
- **Study Session 2** — *Distributed Database System*: DDB architecture,
  data fragmentation, replication, consistency models, CAP theorem,
  BASE vs ACID, sync vs async replication trade-offs.
- **Study Session 3** — *Cloud Database Systems*: cloud DB deployment,
  use cases, data warehousing and database security in the cloud.
- **Study Session 6** — *Data Security and Data Privacy*: NDPA 2023 and
  CBN data-localisation requirements that force KickOff Arena to keep
  customer data inside Nigeria.

## What this portfolio demonstrates

1. **Partitioning** of the `booking` table by month (range partitioning on
   `start_time`). Old months stay readable but new inserts route
   automatically to the active partition. The demo runs `EXPLAIN` on a
   date-bounded query to show **partition pruning** in action.
2. **Streaming replication**: a physical primary + a hot-standby read
   replica, set up with `pg_basebackup`. The walkthrough in
   `replication_setup.md` shows:
   - the primary accepting a write,
   - the replica rejecting a write with `cannot execute INSERT in a
     read-only transaction`,
   - the new row arriving on the replica after the standby catches up.
3. **Cloud architecture** for KickOff Arena that keeps customer data inside
   Nigeria (NDPA 2023) and complies with CBN's data-localisation guidance
   for payment data. The architecture in `cloud_architecture.md` covers
   region choice, availability zones, sync vs async replication trade-offs,
   CAP placement (CP for booking writes, AP for analytics reads), and a
   backup / disaster-recovery plan.

## Files

| File | Purpose |
|---|---|
| `partitioning.sql` | Re-creates `booking` as a partitioned table (monthly), creates a few month partitions, inserts sample rows, runs an `EXPLAIN` showing partition pruning. |
| `replication_setup.md` | Step-by-step guide to building a primary + streaming replica inside a Codespace, including the "replica rejects writes" demo and the "new row arrives via streaming" demo. |
| `cloud_architecture.md` | The KickOff Arena cloud architecture — Nigeria-resident, NDPA 2023 + CBN compliant, with CAP and sync/async trade-offs explained. |
| `run_p5.sh` | Drives the in-script parts (the replication guide is run by hand). |
| `README.md` | This file. |

## How to run (GitHub Codespaces)

```bash
# after P1 has been run at least once:
cd portfolio-5-distributed-cloud
bash run_p5.sh
# then follow replication_setup.md by hand (two PostgreSQL clusters on the
# same Codespace, listening on different ports / data directories).
```

## What to screenshot

1. The `\d+ booking` output showing `Partitioned table "public.booking"`
   with several `booking_YYYY_MM` partitions.
2. The `EXPLAIN` plan showing `Append`/`Bitmap Heap Scan` only on the
   relevant partitions (partition pruning).
3. From the replication walkthrough:
   - the primary accepting an `INSERT`,
   - the replica rejecting an `INSERT` with `cannot execute INSERT in a
     read-only transaction`,
   - the `SELECT` on the replica returning the new row after streaming
     catch-up.
4. The cloud architecture diagram (rendered Mermaid) from
   `cloud_architecture.md`.

## Git commit

```bash
git add portfolio-5-distributed-cloud
git commit -m "P5: monthly partitioning, streaming replica, Nigeria-resident cloud architecture"
git push
```

## Plain-English explanation

A 5-a-side pitch booking system that grows to several Lagos locations and
plans to expand across Nigeria generates a lot of booking rows very fast —
and the more rows accumulate, the slower every query gets if all of them
sit in one table. Partitioning by month keeps each partition small and
lets PostgreSQL prune entire partitions when a query is date-bounded. A
read replica offloads analytics reads from the OLTP primary, but it must
be read-only (otherwise two writes would diverge). The cloud deployment
must keep customer data inside Nigeria to comply with the Nigeria Data
Protection Act 2023 and the CBN's data-localisation guidance for
payment data. These three pieces — partitioning, replication and a
Nigeria-resident cloud architecture — are exactly the distributed-DB
concepts from Study Sessions 2, 3 and 6 of the course notes.

---
## Running P5 (added after testing)
`run_p5.sh` runs `partitioning.sql` (monthly partitions, DEFAULT partition = 0 rows, pruning vs unpartitioned timing, per-partition no-overlap constraint because PostgreSQL 16 rejects EXCLUDE on a partitioned parent) and then `replication_demo.sh` (primary + hot standby on port 5433, write rejected on the replica, row streamed across, lag). Outputs: `partitioning_output.log`, `replication_output.log`. The manual walkthrough in replication_setup.md is kept for reference.
