-- =============================================================================
-- partitioning.sql - booking copy partitioned by month (RANGE on start_time).
-- Portfolio 5, MIT 8103. Run AFTER P1 (needs the 50,000 booking rows).
-- Leaves P1's original tables untouched: creates booking_partitioned only.
-- PostgreSQL 16 does NOT allow an EXCLUDE constraint on the partitioned parent,
-- so the no-overlap rule is added to EACH partition in the loop below.
-- =============================================================================
\set ON_ERROR_STOP on
SET TIME ZONE 'Africa/Lagos';
\pset pager off

DROP TABLE IF EXISTS booking_partitioned CASCADE;

CREATE TABLE booking_partitioned (
    booking_id     BIGINT      NOT NULL,
    pitch_id       BIGINT      NOT NULL REFERENCES pitch(pitch_id),
    team_id        BIGINT      NOT NULL REFERENCES team(team_id),
    start_time     TIMESTAMPTZ NOT NULL,
    duration_hours INTEGER     NOT NULL,
    time_range     tstzrange,
    status         TEXT        NOT NULL DEFAULT 'confirmed'
                     CHECK (status IN ('confirmed','cancelled','completed','no_show')),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- PK must contain the partition key
    CONSTRAINT booking_part_pk PRIMARY KEY (booking_id, start_time),
    CONSTRAINT booking_part_hourly_start_chk CHECK (
        EXTRACT(MINUTE FROM start_time) = 0 AND EXTRACT(SECOND FROM start_time) = 0
        AND duration_hours BETWEEN 1 AND 3),
    CONSTRAINT booking_part_opening_hours_chk CHECK (
        (start_time AT TIME ZONE 'Africa/Lagos')::time >= TIME '07:00'
        AND (start_time AT TIME ZONE 'Africa/Lagos') + duration_hours * INTERVAL '1 hour'
            <= date_trunc('day', start_time AT TIME ZONE 'Africa/Lagos') + INTERVAL '23 hours')
) PARTITION BY RANGE (start_time);

-- Keep time_range in sync (row trigger on the parent applies to every partition)
CREATE OR REPLACE FUNCTION sync_booking_time_range_p() RETURNS trigger AS $$
BEGIN
    NEW.time_range := tstzrange(NEW.start_time, NEW.start_time + make_interval(hours => NEW.duration_hours), '[)');
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_sync_booking_time_range_p
BEFORE INSERT OR UPDATE OF start_time, duration_hours ON booking_partitioned
FOR EACH ROW EXECUTE FUNCTION sync_booking_time_range_p();

-- Monthly partitions: 14 months back to 14 months ahead (covers all the P1 data),
-- each with its own no-overlap EXCLUDE constraint, plus a DEFAULT safety partition.
DO $$
DECLARE
    m date := date_trunc('month', CURRENT_DATE - INTERVAL '14 months')::date;
    stop date := date_trunc('month', CURRENT_DATE + INTERVAL '14 months')::date;
    pname text;
BEGIN
    WHILE m < stop LOOP
        pname := 'booking_' || to_char(m, 'YYYY_MM');
        EXECUTE format('CREATE TABLE %I PARTITION OF booking_partitioned FOR VALUES FROM (%L) TO (%L)',
                       pname, m, (m + INTERVAL '1 month')::date);
        EXECUTE format('ALTER TABLE %I ADD CONSTRAINT %I EXCLUDE USING gist (pitch_id WITH =, time_range WITH &&) WHERE (status = ''confirmed'')',
                       pname, pname || '_no_overlap');
        m := (m + INTERVAL '1 month')::date;
    END LOOP;
END $$;
CREATE TABLE booking_default PARTITION OF booking_partitioned DEFAULT;

-- Copy ALL P1 bookings (same ids)
INSERT INTO booking_partitioned (booking_id, pitch_id, team_id, start_time, duration_hours, status, created_at)
SELECT booking_id, pitch_id, team_id, start_time, duration_hours, status, created_at FROM booking;
ANALYZE booking_partitioned;

\echo ''
\echo '====== Partitions and rows per partition (DEFAULT partition must be 0) ======'
SELECT count(*) AS partitions FROM pg_inherits WHERE inhparent = 'booking_partitioned'::regclass;
SELECT tableoid::regclass AS partition, count(*) AS rows FROM booking_partitioned GROUP BY 1 ORDER BY 1;
SELECT 'booking_default rows' AS check, count(*) FROM booking_default;
SELECT 'total rows (must equal booking)' AS check, (SELECT count(*) FROM booking_partitioned) AS partitioned, (SELECT count(*) FROM booking) AS original;

\echo ''
\echo '====== Partition pruning: one month on the PARTITIONED table (touches 1 partition) ======'
EXPLAIN (ANALYZE, COSTS OFF, TIMING ON)
SELECT count(*), sum(duration_hours) FROM booking_partitioned
 WHERE start_time >= date_trunc('month', CURRENT_DATE)::timestamptz
   AND start_time <  (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamptz;

\echo ''
\echo '====== Same query on the UNPARTITIONED booking table (for comparison) ======'
EXPLAIN (ANALYZE, COSTS OFF, TIMING ON)
SELECT count(*), sum(duration_hours) FROM booking
 WHERE start_time >= date_trunc('month', CURRENT_DATE)::timestamptz
   AND start_time <  (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamptz;

\echo ''
\set ON_ERROR_STOP off
\echo '====== Control: the per-partition EXCLUDE constraint still blocks a double booking ======'
BEGIN;
INSERT INTO booking_partitioned (booking_id, pitch_id, team_id, start_time, duration_hours)
  VALUES (900000001, 1, 1, ((CURRENT_DATE + 3) + TIME '12:00') AT TIME ZONE 'Africa/Lagos', 1);
SAVEPOINT s;
INSERT INTO booking_partitioned (booking_id, pitch_id, team_id, start_time, duration_hours)
  VALUES (900000002, 1, 1, ((CURRENT_DATE + 3) + TIME '12:00') AT TIME ZONE 'Africa/Lagos', 1);
ROLLBACK TO s;
ROLLBACK;
