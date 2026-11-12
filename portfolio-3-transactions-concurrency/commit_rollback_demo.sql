-- =============================================================================
-- commit_rollback_demo.sql — explicit COMMIT / ROLLBACK + SAVEPOINT examples.
-- Portfolio 3, MIT 8103 Advanced Database Systems.
-- =============================================================================

-- ON_ERROR_STOP is off so we can see the ERROR, then continue
\set ON_ERROR_STOP off
SET TIME ZONE 'Africa/Lagos';

\echo ''
\echo '====== COMMIT demo: changes are visible after COMMIT ======'
\echo ''
DROP TABLE IF EXISTS p3_commit_demo;
CREATE TABLE p3_commit_demo (id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                             note TEXT NOT NULL,
                             created_at TIMESTAMPTZ DEFAULT now());

BEGIN;
INSERT INTO p3_commit_demo (note) VALUES ('committed row 1');
INSERT INTO p3_commit_demo (note) VALUES ('committed row 2');
COMMIT;
\echo 'After COMMIT, rows visible to all sessions:'
SELECT * FROM p3_commit_demo ORDER BY id;


\echo ''
\echo '====== ROLLBACK demo: changes discarded after ROLLBACK ======'
\echo ''
BEGIN;
INSERT INTO p3_commit_demo (note) VALUES ('this row will be rolled back');
INSERT INTO p3_commit_demo (note) VALUES ('this row will also be rolled back');
\echo 'Inside the transaction, we can see them:'
SELECT count(*) AS rows_inside_txn FROM p3_commit_demo;
ROLLBACK;
\echo 'After ROLLBACK, the inserted rows are gone:'
SELECT count(*) AS rows_after_rollback FROM p3_commit_demo;


\echo ''
\echo '====== SAVEPOINT demo: partial rollback inside a transaction ======'
\echo ''
BEGIN;
INSERT INTO p3_commit_demo (note) VALUES ('will survive');
SAVEPOINT sp1;
INSERT INTO p3_commit_demo (note) VALUES ('will be rolled back to sp1');
ROLLBACK TO SAVEPOINT sp1;
INSERT INTO p3_commit_demo (note) VALUES ('also survives');
COMMIT;
\echo 'After COMMIT, only the two non-rolled-back rows are visible:'
SELECT * FROM p3_commit_demo ORDER BY id;


\echo ''
\echo '====== TRIGGER-driven rollback: a payment insert that violates a CHECK ====='
\echo '       is automatically rolled back when the outer block fails.'
\echo ''
DROP TABLE IF EXISTS p3_payment_demo;
CREATE TABLE p3_payment_demo (
    payment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    amount     NUMERIC(12,2) NOT NULL,
    CONSTRAINT p3_amount_positive_chk CHECK (amount > 0)
);
BEGIN;
INSERT INTO p3_payment_demo (amount) VALUES (5000);           -- OK
INSERT INTO p3_payment_demo (amount) VALUES (0);               -- FAILS (CHECK)
-- Because ON_ERROR_STOP=off for this file, psql continues; but the transaction
-- is now aborted. We ROLLBACK explicitly to leave the table empty.
ROLLBACK;
\echo 'After ROLLBACK, the demo table is empty (the 5000 row was undone together with the 0 row):'
SELECT count(*) AS rows_in_p3_payment_demo FROM p3_payment_demo;

-- cleanup
DROP TABLE IF EXISTS p3_commit_demo;
DROP TABLE IF EXISTS p3_payment_demo;
