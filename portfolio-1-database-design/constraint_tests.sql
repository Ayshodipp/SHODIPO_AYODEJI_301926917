-- =============================================================================
-- constraint_tests.sql — Portfolio 1 constraint tests (KickOff Arena).
-- Each test builds its own situation inside one transaction, tries the bad
-- action, and must show the INTENDED error. Test C1 is a control that must
-- SUCCEED. Everything is rolled back at the end.
-- =============================================================================
\set ON_ERROR_STOP off
SET TIME ZONE 'Africa/Lagos';
BEGIN;

-- Own test data: a brand-new pitch (no bookings), a 5-player team and a 4-player team.
INSERT INTO pitch (location_id, name, surface_type, capacity)
  SELECT location_id, 'TEST Pitch', 'grass', 10 FROM location LIMIT 1;
INSERT INTO team (name, captain_name) VALUES ('TEST Full Team','A'), ('TEST Small Team','B');
INSERT INTO player (first_name, last_name) SELECT 'T'||g, 'Tester' FROM generate_series(1,9) g;
INSERT INTO team_member (team_id, player_id)
  SELECT (SELECT team_id FROM team WHERE name='TEST Full Team'),  player_id FROM player WHERE last_name='Tester' ORDER BY player_id LIMIT 5;
INSERT INTO team_member (team_id, player_id)
  SELECT (SELECT team_id FROM team WHERE name='TEST Small Team'), player_id FROM player WHERE last_name='Tester' ORDER BY player_id DESC LIMIT 4;
SELECT pitch_id AS tp FROM pitch WHERE name='TEST Pitch' \gset
SELECT team_id AS full_t  FROM team WHERE name='TEST Full Team'  \gset
SELECT team_id AS small_t FROM team WHERE name='TEST Small Team' \gset
-- Day 20 days ahead, Lagos time
SELECT ((CURRENT_DATE + 20)::timestamp) AT TIME ZONE 'Africa/Lagos' AS d0 \gset

\echo '====== C1 (control): valid booking 10:00, 1 hour - must SUCCEED ======'
INSERT INTO booking (pitch_id, team_id, start_time, duration_hours)
VALUES (:tp, :full_t, :'d0'::timestamptz + INTERVAL '10 hours', 1);

\echo '====== T1: overlapping booking, same pitch 10:00 (EXCLUDE booking_no_overlap) ======'
SAVEPOINT s; INSERT INTO booking (pitch_id, team_id, start_time, duration_hours)
VALUES (:tp, :full_t, :'d0'::timestamptz + INTERVAL '10 hours', 1);
ROLLBACK TO s;

\echo '====== T2: booking not on the hour, 10:30 (CHECK booking_hourly_start_chk) ======'
SAVEPOINT s; INSERT INTO booking (pitch_id, team_id, start_time, duration_hours)
VALUES (:tp, :full_t, :'d0'::timestamptz + INTERVAL '14 hours 30 minutes', 1);
ROLLBACK TO s;

\echo '====== T3: duration 4 hours (CHECK booking_hourly_start_chk) ======'
SAVEPOINT s; INSERT INTO booking (pitch_id, team_id, start_time, duration_hours)
VALUES (:tp, :full_t, :'d0'::timestamptz + INTERVAL '12 hours', 4);
ROLLBACK TO s;

\echo '====== T4: start 02:00, closed hours (CHECK booking_opening_hours_chk) ======'
SAVEPOINT s; INSERT INTO booking (pitch_id, team_id, start_time, duration_hours)
VALUES (:tp, :full_t, :'d0'::timestamptz + INTERVAL '2 hours', 1);
ROLLBACK TO s;

\echo '====== T5: 3-hour booking from 22:00 ends at 01:00 (CHECK booking_opening_hours_chk) ======'
SAVEPOINT s; INSERT INTO booking (pitch_id, team_id, start_time, duration_hours)
VALUES (:tp, :full_t, :'d0'::timestamptz + INTERVAL '22 hours', 3);
ROLLBACK TO s;

\echo '====== T6: team with only 4 players books (TRIGGER trg_check_team_size) ======'
SAVEPOINT s; INSERT INTO booking (pitch_id, team_id, start_time, duration_hours)
VALUES (:tp, :small_t, :'d0'::timestamptz + INTERVAL '16 hours', 1);
ROLLBACK TO s;

\echo '====== T7: payment amount = 0 (CHECK payment_amount_positive_chk) ======'
SAVEPOINT s; INSERT INTO payment (booking_id, amount, method, status)
SELECT booking_id, 0, 'card', 'succeeded' FROM booking WHERE pitch_id = :tp;
ROLLBACK TO s;

\echo '====== T8: negative payment amount (CHECK payment_amount_positive_chk) ======'
SAVEPOINT s; INSERT INTO payment (booking_id, amount, method, status)
SELECT booking_id, -5000, 'card', 'refunded' FROM booking WHERE pitch_id = :tp;
ROLLBACK TO s;

\echo '====== T9: match_result with home team = away team (CHECK match_result_teams_differ_chk) ======'
SAVEPOINT s; INSERT INTO match_result (booking_id, home_team_id, away_team_id, home_score, away_score, played_at)
SELECT booking_id, :full_t, :full_t, 2, 2, now() FROM booking WHERE pitch_id = :tp;
ROLLBACK TO s;

\echo '====== T10: pricing rate <= 0 (CHECK pricing_rate_check) ======'
SAVEPOINT s; INSERT INTO pricing (pitch_id, day_of_week, period, rate, valid_from, valid_to)
VALUES (:tp, 3, 'peak', 0, CURRENT_DATE, CURRENT_DATE + 365);
ROLLBACK TO s;

\echo '====== T11: invalid surface_type (CHECK pitch_surface_chk) ======'
SAVEPOINT s; INSERT INTO pitch (location_id, name, surface_type, capacity)
SELECT location_id, 'Bad', 'sand', 10 FROM location LIMIT 1;
ROLLBACK TO s;

\echo '====== Done: C1 succeeded; T1-T11 must each show their intended ERROR above. ======'
ROLLBACK;
