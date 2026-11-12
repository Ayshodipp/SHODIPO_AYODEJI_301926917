# Portfolio 3 — Transactions and Concurrency

**Student:** Ayodeji Shodipo · 2026/A/MIT/0725
**Case study:** KickOff Arena — 5-a-side football pitch booking (Lagos)
**Course-note study sessions covered:**
- **Study Session 2** — *Distributed Database System*: ACID vs BASE,
  consistency models.
- **Study Session 1** — *Limitations of traditional DBMS*: the conclusion
  explicitly calls out "concurrency control issues" of centralised DBMS —
  this portfolio is the practical answer to that problem.

## What this portfolio demonstrates

1. A `book_pitch()` PL/pgSQL function that runs as a single transaction:
   - check the slot is free,
   - insert the booking (time_range trigger populates `time_range`),
   - insert a payment row (the deposit),
   - `COMMIT` on success, `ROLLBACK` on any exception (e.g. failed payment).
2. A demo that a failed payment rolls back the booking insert too — no
   orphaned booking row.
3. A two-terminal, same-pitch, same-hour race condition, written as a
   step-by-step guide for two interactive `psql` sessions:
   - **The bug**: with the exclusion constraint dropped and no locking, two
     terminals each pass the "is the slot free?" check and both insert —
     **a double booking**.
   - **Fix 1**: restore the exclusion constraint; the second insert is
     rejected by PostgreSQL with a clean `conflicting key value violates
     exclusion constraint "booking_no_overlap"` error.
   - **Fix 2**: keep the constraint dropped, but `SELECT ... FOR UPDATE` on
     the `pitch` row inside the transaction. The second transaction now
     *blocks* until the first one commits, then sees the new booking and
     returns a clean "slot already taken" message.
4. Isolation levels (`READ COMMITTED`, `REPEATABLE READ`, `SERIALIZABLE`)
   illustrated with a non-repeatable-read scenario.
5. A classic two-row deadlock demo (T1 locks A then waits for B; T2 locks B
   then waits for A; PostgreSQL detects the cycle and aborts one of them).

## Files

| File | Purpose |
|---|---|
| `book_pitch.sql` | `book_pitch()` PL/pgSQL function + a happy-path call + a failing-path call (deposit payment fails → rollback). |
| `commit_rollback_demo.sql` | Demonstrates `COMMIT` keeping changes and `ROLLBACK` discarding them, using `SAVEPOINT` to model a partial rollback. |
| `race_condition_guide.md` | The two-terminal step-by-step walkthrough: the bug, fix 1 (exclusion constraint), fix 2 (`SELECT … FOR UPDATE`). |
| `isolation_levels.sql` | Side-by-side `READ COMMITTED` vs `REPEATABLE READ` vs `SERIALIZABLE` on the same scenario. |
| `deadlock_demo.sql` | Two sessions each grab two locks in opposite order — one detects the deadlock. |
| `run_p3.sh` | Runs the in-script parts of P3 (the two-terminal parts are run by hand). |
| `README.md` | This file. |

## How to run (GitHub Codespaces)

```bash
# after P1 has run:
cd portfolio-3-transactions-concurrency
bash run_p3.sh
# then open the race_condition_guide.md and follow the two-terminal steps
# in two SEPARATE Codespace terminals.
```

## What to screenshot

1. The two `SELECT * FROM booking …` rows after `book_pitch()` succeeds.
2. The `book_pitch()` failure case showing that **no** orphaned booking row
   is left behind (run `SELECT count(*) FROM booking WHERE team_id = …`
   before and after).
3. The race-condition walkthrough — **three** sub-screenshots:
   - the bug (double booking),
   - fix 1 (exclusion constraint error message),
   - fix 2 (the second `psql` blocks, then returns "slot already taken").
4. The isolation-level demo — the non-repeatable read in `READ COMMITTED`
   vs the `could not serialize access` error in `SERIALIZABLE`.
5. The deadlock — the `ERROR: deadlock detected` line in one of the two
   terminals.

## Git commit

```bash
git add portfolio-3-transactions-concurrency
git commit -m "P3: book_pitch() transaction, race-condition fixes, isolation levels, deadlock"
git push
```

## Plain-English explanation

Booking a pitch is the textbook atomic operation: you cannot let a customer
pay for a slot that another customer has just taken, and you cannot keep the
booking row if the payment fails. PostgreSQL gives us three complementary
tools for this: (i) `BEGIN/COMMIT/ROLLBACK` keeps the insert+payment
atomic; (ii) the `btree_gist` exclusion constraint from P1 makes
overlapping inserts impossible at the storage level; (iii) row-level locks
(`SELECT … FOR UPDATE`) let us serialise the check-then-insert sequence
when a constraint is not available. We then show how different isolation
levels change what each transaction "sees", and finally reproduce a
deliberate deadlock to prove PostgreSQL's cycle-detector works.

---
## Running the concurrency demos (added after testing)
`run_p3.sh` now runs `run_race_demos.py` automatically: two real PostgreSQL sessions race each other and print labelled output to `race_demos_output.log` (race bug, exclusion constraint on the real booking table, SELECT FOR UPDATE, SERIALIZABLE, READ COMMITTED vs REPEATABLE READ, deadlock). No two terminals needed. Note: a check-then-insert (or a capacity trigger) alone does NOT stop the race under READ COMMITTED; the exclusion constraint, a row lock or SERIALIZABLE does.
