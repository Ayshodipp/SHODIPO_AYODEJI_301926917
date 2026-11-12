-- =============================================================================
-- indexes.sql — the indexes added after the "before" plans.
-- Portfolio 2, MIT 8103 Advanced Database Systems.
--
-- Run BEFORE explain_after.sql:
--   psql -h /var/run/postgresql -U kickoff kickoff -f indexes.sql
--
-- Index choices are justified inline by which query they help:
--
--   idx_booking_start_time           — Q1 (filter on start_time::date) + Q3
--                                       (filter on EXTRACT(HOUR/DOW from start_time))
--                                       + Q6 (range on start_time)
--   idx_booking_status_start         — Q3 + Q6 + Q5 filter on status='confirmed'
--   idx_payment_paid_at_succeeded     — Q2 filter on paid_at + status='succeeded'
--   idx_payment_booking_id           — Q2 join payment → booking
--   idx_team_id_booking              — Q4 group by team
--   idx_match_result_booking_id       — Q5 NOT EXISTS subquery
--
-- idx_booking_status_start is a partial index that holds only the rows the
-- analytics queries actually care about (status IN ('confirmed','completed',
-- 'no_show')); it is dramatically smaller than a full index on booking and
-- therefore cheaper to scan.
-- =============================================================================

\set ON_ERROR_STOP on
SET TIME ZONE 'Africa/Lagos';

\echo '====== Creating optimisation indexes ======'

-- Q1, Q3, Q6: range scan on start_time and predicate on status.
CREATE INDEX IF NOT EXISTS idx_booking_status_start
    ON booking (start_time)
    WHERE status IN ('confirmed','completed','no_show');

-- Q2: filter on payment.paid_at + status='succeeded'.
CREATE INDEX IF NOT EXISTS idx_payment_paid_at_succeeded
    ON payment (paid_at)
    WHERE status = 'succeeded';

-- Q2 join: payment → booking.
CREATE INDEX IF NOT EXISTS idx_payment_booking_id
    ON payment (booking_id);

-- Q4 group by team.
CREATE INDEX IF NOT EXISTS idx_team_id_booking
    ON booking (team_id);

-- Q5 NOT EXISTS subquery.
CREATE INDEX IF NOT EXISTS idx_match_result_booking_id
    ON match_result (booking_id);

-- Q3: help DOW / hour filters (covering index already does most of the work,
-- but adding a GIST on time_range helps the rare "find overlapping peak" form).
CREATE INDEX IF NOT EXISTS idx_booking_time_range_gist
    ON booking USING gist (time_range);

-- ANALYZE so the planner picks up the new statistics.
ANALYZE booking;
ANALYZE payment;
ANALYZE match_result;
ANALYZE team;
ANALYZE pitch;
ANALYZE location;

\echo '====== Indexes created. Re-running EXPLAIN ANALYZE now. ======'
\dt+
\di
