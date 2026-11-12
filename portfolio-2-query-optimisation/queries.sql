-- =============================================================================
-- queries.sql — 6 analytics queries for KickOff Arena
-- Portfolio 2, MIT 8103 Advanced Database Systems.
-- Run AFTER schema.sql + seed.sql + bulk_seed.py from P1.
--
--   psql -h /var/run/postgresql -U kickoff kickoff -f queries.sql
--
-- The :target_date psql variable defaults to tomorrow; override with -v.
--   psql ... -v target_date="'2026-12-01'" -f queries.sql
-- =============================================================================

\set ON_ERROR_STOP on
SET TIME ZONE 'Africa/Lagos';

-- Default target date = tomorrow, so free-slots has something to show.
\if :{?target_date}
\else
  \set target_date '(CURRENT_DATE + 1)::date'
\endif

\echo ''
\echo '====== Q1: Free slots at a location for a given date ======'
\echo '      (location = Lekki, date = tomorrow by default)'
\echo ''
-- Free slots = every hour 07:00–23:00 for every pitch at the location
-- MINUS the hours covered by confirmed/completed bookings.
WITH location_pitches AS (
    SELECT p.pitch_id, p.name AS pitch_name
      FROM pitch p JOIN location l USING (location_id)
     WHERE l.area = 'Lekki'
),
all_hours AS (
    SELECT pitch_id, pitch_name,
           generate_series(7, 22) AS start_hour   -- 07..22 → 1h slot starts at hour 22 ends 23:00
      FROM location_pitches
),
booked_hours AS (
    SELECT b.pitch_id, h.hour_slot
      FROM booking b
      JOIN LATERAL generate_series(
            EXTRACT(HOUR FROM b.start_time AT TIME ZONE 'Africa/Lagos')::int,
            EXTRACT(HOUR FROM b.start_time AT TIME ZONE 'Africa/Lagos')::int + b.duration_hours - 1
          ) AS h(hour_slot)
        ON b.start_time::date = :target_date
     WHERE b.status IN ('confirmed','completed')
)
SELECT a.pitch_name,
       lpad(a.start_hour::text, 2, '0') || ':00' AS free_slot
  FROM all_hours a
  LEFT JOIN booked_hours bh ON bh.pitch_id = a.pitch_id AND bh.hour_slot = a.start_hour
 WHERE bh.hour_slot IS NULL
 ORDER BY a.pitch_name, a.start_hour;

\echo ''
\echo '====== Q2: Revenue per location per month (last 12 months) ======'
\echo ''
SELECT l.area AS location,
       to_char(date_trunc('month', p.paid_at), 'YYYY-MM') AS month,
       sum(p.amount) AS revenue_ngn,
       count(*)     AS payment_count
  FROM payment p
  JOIN booking b  ON b.booking_id = p.booking_id
  JOIN pitch  pi  ON pi.pitch_id  = b.pitch_id
  JOIN location l ON l.location_id = pi.location_id
 WHERE p.status = 'succeeded'
   AND p.paid_at >= now() - INTERVAL '30 days'
 GROUP BY l.area, date_trunc('month', p.paid_at)
 ORDER BY l.area, month;

\echo ''
\echo '====== Q3: Peak-hour usage (peak = 17:00–23:00 weekdays OR all day weekends) ======'
\echo ''
-- Count bookings that touch at least one peak hour, per location.
SELECT l.area AS location,
       count(*) AS peak_bookings,
       sum(b.duration_hours) AS peak_hours_booked
  FROM booking b
  JOIN pitch  pi  ON pi.pitch_id  = b.pitch_id
  JOIN location l  ON l.location_id = pi.location_id
 WHERE b.status IN ('confirmed','completed')
   AND b.start_time >= now() - INTERVAL '30 days' AND b.start_time < now()
   AND (
     EXTRACT(DOW FROM b.start_time AT TIME ZONE 'Africa/Lagos') IN (0, 6)
     OR
     EXISTS (
       SELECT 1 FROM generate_series(
         EXTRACT(HOUR FROM b.start_time AT TIME ZONE 'Africa/Lagos')::int,
         EXTRACT(HOUR FROM b.start_time AT TIME ZONE 'Africa/Lagos')::int + b.duration_hours - 1
       ) AS h(hour_slot)
       WHERE h.hour_slot >= 17
     )
   )
 GROUP BY l.area
 ORDER BY peak_hours_booked DESC NULLS LAST;

\echo ''
\echo '====== Q4: Top 10 teams by number of bookings ======'
\echo ''
SELECT t.team_id, t.name AS team_name,
       count(b.booking_id) AS bookings,
       sum(b.duration_hours) AS hours_booked
  FROM team t
  LEFT JOIN booking b ON b.team_id = t.team_id
 GROUP BY t.team_id, t.name
 ORDER BY bookings DESC NULLS LAST, hours_booked DESC NULLS LAST
 LIMIT 10;

\echo ''
\echo '====== Q5: No-show rate (bookings whose start is in the past ======'
\echo '           and have no match_result, divided by total past bookings)'
\echo ''
WITH past AS (
    SELECT b.booking_id, b.status
      FROM booking b
     WHERE b.start_time < now()
),
flagged AS (
    SELECT p.*,
           CASE WHEN p.status = 'no_show' THEN 1 ELSE 0 END AS is_no_show,
           CASE WHEN p.status = 'no_show'
                  OR (p.status = 'confirmed'
                      AND NOT EXISTS (SELECT 1 FROM match_result m WHERE m.booking_id = p.booking_id)
                     )
                THEN 1 ELSE 0 END AS considered_no_show
      FROM past p
)
SELECT count(*)                                                 AS past_bookings,
       sum(is_no_show)                                          AS marked_no_show,
       round(100.0 * sum(is_no_show) / nullif(count(*), 0), 2)  AS no_show_rate_pct
  FROM flagged;

\echo ''
\echo '====== Q6: Pitch utilisation % (booked hours / available hours) ======'
\echo '           over the last 30 days, per pitch'
\echo ''
WITH win AS (
    SELECT now() - INTERVAL '30 days' AS from_ts,
           now()                       AS to_ts
),
available AS (
    SELECT pi.pitch_id, pi.name AS pitch_name,
           extract(epoch FROM (w.to_ts - w.from_ts))/3600.0 AS available_hours
      FROM pitch pi CROSS JOIN win w
     WHERE pi.active
),
booked AS (
    SELECT b.pitch_id,
           sum(b.duration_hours) AS booked_hours
      FROM booking b CROSS JOIN win w
     WHERE b.start_time >= w.from_ts
       AND b.start_time <  w.to_ts
       AND b.status IN ('confirmed','completed')
 GROUP BY b.pitch_id
)
SELECT a.pitch_name,
       a.available_hours,
       COALESCE(b.booked_hours, 0) AS booked_hours,
       round(100.0 * COALESCE(b.booked_hours, 0) / a.available_hours, 2) AS utilisation_pct
  FROM available a
  LEFT JOIN booked b USING (pitch_id)
 ORDER BY utilisation_pct DESC;
