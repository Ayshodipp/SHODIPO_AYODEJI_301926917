# Race-Condition Walkthrough — Two Terminals, Same Pitch, Same Hour

**Portfolio 3 · MIT 8103 Advanced Database Systems · Ayodeji Shodipo · 2026/A/MIT/0725**

This guide shows the classic "lost update / double booking" bug and the two
standard fixes, by running **two `psql` sessions side-by-side** in two
Codespace terminals.

Open two terminals side-by-side and connect each to the database through the
Unix socket (no password — required by the Codespaces rules):

```bash
# Terminal A and Terminal B (run in each):
sudo runuser -u postgres -- psql -d kickoff
```

(Or, if you prefer your own role: `PGPASSWORD=kickoff_dev_pw psql -h /var/run/postgresql -U kickoff kickoff`.)

Pick a target slot for the demo. We use tomorrow 14:00 Lagos time on
**pitch_id = 1** (Lekki Pitch A) by **team_id = 1** (Lekki Lions FC, which
has 5 players).

> **Time-trick used below**: to make sure the slot really is empty before
> each replay, we use a date computed from `now()` so the demo never expires.

---

## Scenario 0 — Setup (run once, in Terminal A, before any sub-scenario)

```sql
-- Terminal A
SET TIME ZONE 'Africa/Lagos';
-- Pick a slot that is definitely empty: 90 days from today, 14:00, pitch 1.
-- The 90-day offset means re-running the demo any day still finds an empty slot.
SELECT count(*) FROM booking
 WHERE pitch_id = 1
   AND start_time::date = (CURRENT_DATE + 90);
-- expect 0
```

---

## Scenario 1 — THE BUG (no constraint, no locking → double booking)

### 1a) Drop the exclusion constraint and the trigger-time_range check

```sql
-- Terminal A (as superuser, since ALTER needs it)
ALTER TABLE booking DROP CONSTRAINT IF EXISTS booking_no_overlap;
-- (the trg_check_team_size and trg_sync_booking_time_range triggers stay, but
--  they don't prevent overlap; only the EXCLUDE constraint did.)
```

### 1b) Both terminals check the slot — both see it empty

```sql
-- Terminal A
BEGIN;
SELECT count(*) FROM booking
 WHERE pitch_id = 1
   AND start_time >= (CURRENT_DATE + 90)::timestamp
   AND start_time <  (CURRENT_DATE + 90)::timestamp + INTERVAL '1 hour'
   AND status = 'confirmed';
-- returns 0 → "slot is free, I'll book it"
```

```sql
-- Terminal B (run AT THE SAME TIME)
BEGIN;
SELECT count(*) FROM booking
 WHERE pitch_id = 1
   AND start_time >= (CURRENT_DATE + 90)::timestamp
   AND start_time <  (CURRENT_DATE + 90)::timestamp + INTERVAL '1 hour'
   AND status = 'confirmed';
-- returns 0 → "slot is free, I'll book it too"
```

### 1c) Both terminals INSERT — BOTH succeed → DOUBLE BOOKING

```sql
-- Terminal A
INSERT INTO booking (pitch_id, team_id, start_time, duration_hours, status)
VALUES (1, 1, (CURRENT_DATE + 90)::timestamp + INTERVAL '14 hours', 1, 'confirmed');
COMMIT;
```

```sql
-- Terminal B
INSERT INTO booking (pitch_id, team_id, start_time, duration_hours, status)
VALUES (1, 1, (CURRENT_DATE + 90)::timestamp + INTERVAL '14 hours', 1, 'confirmed');
COMMIT;
```

### 1d) Look at the table — TWO rows for the same slot

```sql
-- Terminal A or B
SELECT booking_id, pitch_id, team_id, start_time, duration_hours, status
  FROM booking
 WHERE pitch_id = 1
   AND start_time::date = CURRENT_DATE + 90
 ORDER BY booking_id;
-- TWO rows for the same hour on the same pitch → DOUBLE BOOKING. This is the bug.
```

**Screenshot to capture:** the two-row result of step 1d. This is the bug.

### 1e) Cleanup before fix 1

```sql
-- Terminal A
DELETE FROM booking
 WHERE pitch_id = 1
   AND start_time::date = CURRENT_DATE + 90;
COMMIT;
```

---

## Scenario 2 — FIX 1: restore the exclusion constraint

The whole point of P1's `btree_gist` exclusion constraint is that the
**storage layer itself** rejects overlaps, regardless of what the application
code does. Re-adding the constraint converts step 1c's silent double-booking
into a clean rejection.

### 2a) Re-add the exclusion constraint

```sql
-- Terminal A
ALTER TABLE booking
    ADD CONSTRAINT booking_no_overlap
    EXCLUDE USING gist (
        pitch_id   WITH =,
        time_range WITH &&
    )
    WHERE (status = 'confirmed');
```

### 2b) Both terminals check the slot — both see it empty (same as 1b)

```sql
-- Terminal A
BEGIN;
SELECT count(*) FROM booking
 WHERE pitch_id = 1
   AND start_time >= (CURRENT_DATE + 90)::timestamp
   AND start_time <  (CURRENT_DATE + 90)::timestamp + INTERVAL '1 hour'
   AND status = 'confirmed';
```

```sql
-- Terminal B
BEGIN;
SELECT count(*) FROM booking
 WHERE pitch_id = 1
   AND start_time >= (CURRENT_DATE + 90)::timestamp
   AND start_time <  (CURRENT_DATE + 90)::timestamp + INTERVAL '1 hour'
   AND status = 'confirmed';
```

### 2c) Terminal A INSERTs first — succeeds

```sql
-- Terminal A
INSERT INTO booking (pitch_id, team_id, start_time, duration_hours, status)
VALUES (1, 1, (CURRENT_DATE + 90)::timestamp + INTERVAL '14 hours', 1, 'confirmed');
COMMIT;
```

### 2d) Terminal B INSERTs the same slot — REJECTED

```sql
-- Terminal B
INSERT INTO booking (pitch_id, team_id, start_time, duration_hours, status)
VALUES (1, 1, (CURRENT_DATE + 90)::timestamp + INTERVAL '14 hours', 1, 'confirmed');
-- ERROR: conflicting key value violates exclusion constraint "booking_no_overlap"
-- DETAIL:  Key (pitch_id, time_range)=(1, ["2027-… 14:00:00+01","2027-… 15:00:00+01"))
--          conflicts with existing key (…).
ROLLBACK;
```

**Screenshot to capture:** the `ERROR: conflicting key value violates
exclusion constraint "booking_no_overlap"` line in Terminal B, and the
two-row check from step 1d now showing only **one** row in step 2e.

### 2e) Confirm only one booking exists

```sql
SELECT booking_id, pitch_id, team_id, start_time, status
  FROM booking
 WHERE pitch_id = 1
   AND start_time::date = CURRENT_DATE + 90;
-- exactly ONE row.
```

### 2f) Cleanup before fix 2

```sql
DELETE FROM booking
 WHERE pitch_id = 1
   AND start_time::date = CURRENT_DATE + 90;
COMMIT;

-- And DROP the constraint so fix 2 is the only thing protecting us:
ALTER TABLE booking DROP CONSTRAINT booking_no_overlap;
```

---

## Scenario 3 — FIX 2: `SELECT … FOR UPDATE` row-level locking

When a unique/exclusion constraint is not available (for example, because the
business rule is more complex than "no overlap"), the standard pattern is to
take a row lock on a parent row — here, the `pitch` row — *before* the
check-then-insert sequence. The second transaction then **blocks** on the
lock, and once it wakes up it sees the row inserted by the first transaction
and returns a clean "slot already taken" message.

### 3a) Both terminals BEGIN and lock the pitch row

```sql
-- Terminal A
BEGIN;
SELECT * FROM pitch WHERE pitch_id = 1 FOR UPDATE;
-- returns the pitch row → Terminal A now holds the lock.
```

```sql
-- Terminal B (run immediately after Terminal A's SELECT)
BEGIN;
SELECT * FROM pitch WHERE pitch_id = 1 FOR UPDATE;
-- BLOCKS here. Terminal B is waiting for Terminal A to COMMIT or ROLLBACK.
```

### 3b) Terminal A checks the slot, finds it empty, INSERTs, COMMITs

```sql
-- Terminal A
SELECT count(*) FROM booking
 WHERE pitch_id = 1
   AND start_time >= (CURRENT_DATE + 90)::timestamp
   AND start_time <  (CURRENT_DATE + 90)::timestamp + INTERVAL '1 hour'
   AND status = 'confirmed';
-- returns 0 → free

INSERT INTO booking (pitch_id, team_id, start_time, duration_hours, status)
VALUES (1, 1, (CURRENT_DATE + 90)::timestamp + INTERVAL '14 hours', 1, 'confirmed');
COMMIT;
```

### 3c) Terminal B unblocks, re-checks the slot — now NOT empty

```sql
-- Terminal B (the SELECT … FOR UPDATE has just returned)
SELECT count(*) FROM booking
 WHERE pitch_id = 1
   AND start_time >= (CURRENT_DATE + 90)::timestamp
   AND start_time <  (CURRENT_DATE + 90)::timestamp + INTERVAL '1 hour'
   AND status = 'confirmed';
-- returns 1 → "slot already taken"

-- So Terminal B raises a clean application error instead of inserting:
ROLLBACK;
\echo 'Slot already taken — please pick another hour.'
```

**Screenshot to capture:**
- Terminal B blocked (a long pause between 3a's `BEGIN; SELECT … FOR UPDATE;`
  and 3c's `SELECT count(*)`).
- The two row counts seen by Terminal B **before** and **after** Terminal A's
  COMMIT (0 → 1).

### 3d) Final cleanup

```sql
-- Terminal A or B
DELETE FROM booking
 WHERE pitch_id = 1
   AND start_time::date = CURRENT_DATE + 90;
COMMIT;

-- Restore the exclusion constraint so the schema is back to its P1 state:
ALTER TABLE booking
    ADD CONSTRAINT booking_no_overlap
    EXCLUDE USING gist (
        pitch_id   WITH =,
        time_range WITH &&
    )
    WHERE (status = 'confirmed');
```

---

## What the screenshots show, end-to-end

1. **The bug**: two `INSERT`s both succeed → two rows for the same hour on
   the same pitch.
2. **Fix 1**: the exclusion constraint rejects the second `INSERT` with a
   clean `conflicting key value violates exclusion constraint` error.
3. **Fix 2**: the second `SELECT … FOR UPDATE` blocks until the first
   transaction commits; then the re-check sees the new row and the application
   raises a clean "slot already taken" message.

These three screenshots, taken together, are the entire point of P3: the
*same* application code can be unsafe (bug), safe at storage level (fix 1)
or safe at application level (fix 2). Study Session 2 of the course notes
calls this "consistency models" — here we used the strictest (linearisability)
by relying on a unique/exclusion constraint, and the slightly weaker
serialisable-by-locking model by using `SELECT … FOR UPDATE`.
