-- =============================================================================
-- explain_after.sql — EXPLAIN ANALYZE for the 6 queries AFTER adding indexes.
-- Portfolio 2, MIT 8103 Advanced Database Systems.
--
-- Run AFTER indexes.sql:
--   psql -h /var/run/postgresql -U kickoff kickoff -f explain_after.sql
--
-- Paste each plan's Seq-Scan-vs-Index-Scan node and "Execution Time" line
-- into results_template.md.
-- =============================================================================

\set ON_ERROR_STOP on
SET TIME ZONE 'Africa/Lagos';
\pset pager off

\echo '====== Q1 EXPLAIN (after) — free slots at Lekki for tomorrow ======'
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
WITH location_pitches AS (
    SELECT p.pitch_id, p.name AS pitch_name
      FROM pitch p JOIN location l USING (location_id)
     WHERE l.area = 'Lekki'
),
all_hours AS (
    SELECT pitch_id, pitch_name, generate_series(7, 22) AS start_hour
      FROM location_pitches
),
booked_hours AS (
    SELECT b.pitch_id, h.hour_slot
      FROM booking b
      JOIN LATERAL generate_series(
            EXTRACT(HOUR FROM b.start_time AT TIME ZONE 'Africa/Lagos')::int,
            EXTRACT(HOUR FROM b.start_time AT TIME ZONE 'Africa/Lagos')::int + b.duration_hours - 1
          ) AS h(hour_slot)
        ON true
     WHERE b.status IN ('confirmed','completed')
       AND b.start_time >= (CURRENT_DATE + 1)::timestamptz AND b.start_time < (CURRENT_DATE + 2)::timestamptz
)
SELECT a.pitch_name, lpad(a.start_hour::text, 2, '0') || ':00' AS free_slot
  FROM all_hours a
  LEFT JOIN booked_hours bh ON bh.pitch_id = a.pitch_id AND bh.hour_slot = a.start_hour
 WHERE bh.hour_slot IS NULL
 ORDER BY a.pitch_name, a.start_hour;

\echo ''
\echo '====== Q2 EXPLAIN (after) — revenue per location per month ======'
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT l.area,
       to_char(date_trunc('month', p.paid_at), 'YYYY-MM') AS month,
       sum(p.amount), count(*)
  FROM payment p
  JOIN booking b  ON b.booking_id = p.booking_id
  JOIN pitch  pi  ON pi.pitch_id  = b.pitch_id
  JOIN location l ON l.location_id = pi.location_id
 WHERE p.status = 'succeeded'
   AND p.paid_at >= now() - INTERVAL '30 days'
 GROUP BY l.area, date_trunc('month', p.paid_at)
 ORDER BY l.area, month;

\echo ''
\echo '====== Q3 EXPLAIN (after) — peak-hour usage ======'
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT l.area, count(*), sum(b.duration_hours)
  FROM booking b
  JOIN pitch  pi  ON pi.pitch_id  = b.pitch_id
  JOIN location l  ON l.location_id = pi.location_id
 WHERE b.status IN ('confirmed','completed')
   AND b.start_time >= now() - INTERVAL '30 days' AND b.start_time < now()
   AND (
     EXTRACT(DOW FROM b.start_time AT TIME ZONE 'Africa/Lagos') IN (0, 6)
     OR EXISTS (
       SELECT 1 FROM generate_series(
         EXTRACT(HOUR FROM b.start_time AT TIME ZONE 'Africa/Lagos')::int,
         EXTRACT(HOUR FROM b.start_time AT TIME ZONE 'Africa/Lagos')::int + b.duration_hours - 1
       ) AS h(hour_slot)
       WHERE h.hour_slot >= 17
     )
   )
 GROUP BY l.area
 ORDER BY 3 DESC;

\echo ''
\echo '====== Q4 EXPLAIN (after) — top teams by bookings ======'
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT t.team_id, t.name, count(b.booking_id), sum(b.duration_hours)
  FROM team t
  LEFT JOIN booking b ON b.team_id = t.team_id
 GROUP BY t.team_id, t.name
 ORDER BY count(b.booking_id) DESC NULLS LAST, sum(b.duration_hours) DESC NULLS LAST
 LIMIT 10;

\echo ''
\echo '====== Q5 EXPLAIN (after) — no-show rate ======'
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
WITH past AS (
    SELECT b.booking_id, b.status
      FROM booking b
     WHERE b.start_time < now()
)
SELECT count(*),
       sum(CASE WHEN p.status = 'no_show' THEN 1 ELSE 0 END),
       round(100.0 * sum(CASE WHEN p.status = 'no_show' THEN 1 ELSE 0 END) / nullif(count(*), 0), 2)
  FROM past p;

\echo ''
\echo '====== Q6 EXPLAIN (after) — pitch utilisation % ======'
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
WITH win AS (
    SELECT now() - INTERVAL '30 days' AS from_ts, now() AS to_ts
),
available AS (
    SELECT pi.pitch_id, pi.name,
           extract(epoch FROM (w.to_ts - w.from_ts))/3600.0 AS available_hours
      FROM pitch pi CROSS JOIN win w
     WHERE pi.active
),
booked AS (
    SELECT b.pitch_id, sum(b.duration_hours) AS booked_hours
      FROM booking b CROSS JOIN win w
     WHERE b.start_time >= w.from_ts AND b.start_time < w.to_ts
       AND b.status IN ('confirmed','completed')
 GROUP BY b.pitch_id
)
SELECT a.name, a.available_hours, COALESCE(b.booked_hours, 0),
       round(100.0 * COALESCE(b.booked_hours, 0) / a.available_hours, 2)
  FROM available a LEFT JOIN booked b USING (pitch_id)
 ORDER BY 4 DESC;
