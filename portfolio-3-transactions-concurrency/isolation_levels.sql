-- =============================================================================
-- isolation_levels.sql — READ COMMITTED vs REPEATABLE READ vs SERIALIZABLE
-- Portfolio 3, MIT 8103 Advanced Database Systems.
--
-- Run with TWO psql sessions side-by-side; the file is annotated with which
-- terminal runs which statement. Open both terminals:
--
--   Terminal A:  sudo runuser -u postgres -- psql -d kickoff
--   Terminal B:  sudo runuser -u postgres -- psql -d kickoff
--
-- Then paste the lines marked "-- A" and "-- B" in the right terminal, in order.
-- =============================================================================

-- Setup (run once, Terminal A)
SET TIME ZONE 'Africa/Lagos';
DROP TABLE IF EXISTS p3_isolation_demo;
CREATE TABLE p3_isolation_demo (id BIGINT PRIMARY KEY, balance NUMERIC(12,2) NOT NULL);
INSERT INTO p3_isolation_demo VALUES (1, 10000);
COMMIT;

-- =========================================================================
-- Demo A: READ COMMITTED (PostgreSQL default) → NON-REPEATABLE READ
--
-- Two SELECTs in the SAME transaction return different values because another
-- transaction committed in between. READ COMMITTED allows this; REPEATABLE
-- READ does not.
-- =========================================================================

-- -- A: BEGIN at READ COMMITTED (default)
-- BEGIN ISOLATION LEVEL READ COMMITTED;
-- SELECT balance FROM p3_isolation_demo WHERE id = 1;       -- returns 10000
--
-- -- B: change the value and commit
-- BEGIN;
-- UPDATE p3_isolation_demo SET balance = 7500 WHERE id = 1;
-- COMMIT;
--
-- -- A: re-read the same row in the same transaction
-- SELECT balance FROM p3_isolation_demo WHERE id = 1;       -- returns 7500 (DIFFERENT!)
-- COMMIT;
--
-- \echo 'READ COMMITTED shows a non-repeatable read: same query, two values.'


-- =========================================================================
-- Demo B: REPEATABLE READ → snapshot is frozen at first read
-- =========================================================================

-- -- A: reset the demo
-- UPDATE p3_isolation_demo SET balance = 10000 WHERE id = 1; COMMIT;
--
-- -- A: BEGIN at REPEATABLE READ
-- BEGIN ISOLATION LEVEL REPEATABLE READ;
-- SELECT balance FROM p3_isolation_demo WHERE id = 1;       -- returns 10000
--
-- -- B: change the value and commit
-- BEGIN;
-- UPDATE p3_isolation_demo SET balance = 7500 WHERE id = 1;
-- COMMIT;
--
-- -- A: re-read the same row in the same transaction
-- SELECT balance FROM p3_isolation_demo WHERE id = 1;
-- -- returns 10000 AGAIN (snapshot was frozen at first read)
-- COMMIT;
--
-- \echo 'REPEATABLE READ freezes the snapshot: same query, same value (10000).'
-- \echo 'But once we COMMIT and re-read, we see the new value (7500):'
-- SELECT balance FROM p3_isolation_demo WHERE id = 1;       -- returns 7500


-- =========================================================================
-- Demo C: SERIALIZABLE → a write/write conflict is detected at COMMIT
-- =========================================================================

-- -- A: reset
-- UPDATE p3_isolation_demo SET balance = 10000 WHERE id = 1; COMMIT;
--
-- -- A: read balance and plan a withdrawal
-- BEGIN ISOLATION LEVEL SERIALIZABLE;
-- SELECT balance FROM p3_isolation_demo WHERE id = 1;       -- returns 10000
--
-- -- B: read the same row and plan a withdrawal of the same ₦3000
-- BEGIN ISOLATION LEVEL SERIALIZABLE;
-- SELECT balance FROM p3_isolation_demo WHERE id = 1;       -- returns 10000
--
-- -- A: deduct 3000 → balance 7000, but DO NOT commit yet
-- UPDATE p3_isolation_demo SET balance = balance - 3000 WHERE id = 1;
--
-- -- B: deduct 3000 → balance 7000 — at this point B's UPDATE blocks waiting
-- --    for A's row lock.
-- UPDATE p3_isolation_demo SET balance = balance - 3000 WHERE id = 1;
--
-- -- A: commit
-- COMMIT;
--
-- -- B: now wakes up. Under SERIALIZABLE, PostgreSQL detects that B's
-- --    read-write dependency conflicts with A's committed write, and aborts B
-- --    with:
-- -- ERROR: could not serialize access due to read/write dependencies among
-- --        transactions
-- -- ROLLBACK the failed transaction.
-- ROLLBACK;
--
-- -- Final state: only A's withdrawal landed (balance = 7000).
-- SELECT balance FROM p3_isolation_demo WHERE id = 1;

-- Cleanup
-- DROP TABLE p3_isolation_demo;
-- COMMIT;
