-- =============================================================================
-- deadlock_demo.sql — classic two-row deadlock, two psql sessions.
-- Portfolio 3, MIT 8103 Advanced Database Systems.
--
-- Run with TWO terminals side-by-side:
--
--   Terminal A:  sudo runuser -u postgres -- psql -d kickoff
--   Terminal B:  sudo runuser -u postgres -- psql -d kickoff
--
-- Paste the lines marked "-- A" into Terminal A and "-- B" into Terminal B,
-- in the order shown.
-- =============================================================================

-- Setup (Terminal A, run once)
SET TIME ZONE 'Africa/Lagos';
DROP TABLE IF EXISTS p3_deadlock_demo;
CREATE TABLE p3_deadlock_demo (id BIGINT PRIMARY KEY, label TEXT NOT NULL);
INSERT INTO p3_deadlock_demo VALUES (1, 'row-1');
INSERT INTO p3_deadlock_demo VALUES (2, 'row-2');
COMMIT;

-- The two transactions take locks in OPPOSITE order:
--
--   Terminal A:  BEGIN;  lock row 1;  try to lock row 2;  …
--   Terminal B:  BEGIN;  lock row 2;  try to lock row 1;  …
--
-- Each one is waiting for a lock the other one holds — a cycle.
-- PostgreSQL's deadlock detector kicks in after ~1 second and aborts ONE of
-- the two transactions with:
--
--   ERROR: deadlock detected
--   DETAIL:  Process … waits for ShareLock on transaction … blocked by
--            transaction … .
--            Process … waits for ShareLock on transaction … blocked by
--            transaction … .

-- -- A: lock row 1
-- BEGIN;
-- UPDATE p3_deadlock_demo SET label = label WHERE id = 1;
-- -- (don't COMMIT yet)

-- -- B: lock row 2
-- BEGIN;
-- UPDATE p3_deadlock_demo SET label = label WHERE id = 2;
-- -- (don't COMMIT yet)

-- -- A: now try to lock row 2 — blocks waiting for B
-- UPDATE p3_deadlock_demo SET label = label WHERE id = 2;

-- -- B: now try to lock row 1 — blocks waiting for A. This is the cycle.
-- --    PostgreSQL detects the deadlock within ~1 second and aborts B.
-- UPDATE p3_deadlock_demo SET label = label WHERE id = 1;
-- -- ↑ ERROR: deadlock detected
-- ROLLBACK;

-- -- A: now wakes up and succeeds.
-- COMMIT;

-- Cleanup
-- DROP TABLE p3_deadlock_demo;
-- COMMIT;
--
-- \echo 'One of the two terminals received ERROR: deadlock detected.'
-- \echo 'That is the safety net PostgreSQL provides when row locks form a cycle.'
