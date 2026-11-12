-- =============================================================================
-- book_pitch.sql — book_pitch() PL/pgSQL function + happy-path + failing-path
-- Portfolio 3, MIT 8103 Advanced Database Systems.
-- Run AFTER P1's schema.sql + seed.sql (bulk_seed.py optional):
--   psql -h /var/run/postgresql -U kickoff kickoff -f book_pitch.sql
-- =============================================================================

\set ON_ERROR_STOP on
SET TIME ZONE 'Africa/Lagos';

-- =========================================================================
-- book_pitch(p_pitch_id, p_team_id, p_start_time, p_duration_hours,
--            p_method, p_amount)
--
-- Transactional:
--   1) check the slot is free (no overlapping confirmed booking),
--   2) check the team has at least 5 players,
--   3) INSERT into booking,
--   4) INSERT into payment (the deposit),
--   5) COMMIT on success / ROLLBACK on any exception.
--
-- Returns: the new booking_id, or raises an exception with a clear message.
-- =========================================================================

CREATE OR REPLACE FUNCTION book_pitch(
    p_pitch_id        BIGINT,
    p_team_id         BIGINT,
    p_start_time      TIMESTAMPTZ,
    p_duration_hours  INTEGER,
    p_method          TEXT DEFAULT 'card',
    p_amount          NUMERIC(12,2) DEFAULT NULL
) RETURNS BIGINT AS $$
DECLARE
    v_booking_id      BIGINT;
    v_player_count    INTEGER;
    v_existing        BIGINT;
    v_provisional_rng tstzrange;
    v_final_amount    NUMERIC(12,2);
    v_price_rate      NUMERIC(10,2);
    v_dow             INTEGER;
    v_peak_rows       INTEGER;
    v_offpeak_rows    INTEGER;
    v_first_peak_hr   INTEGER;
BEGIN
    IF p_duration_hours NOT BETWEEN 1 AND 3 THEN
        RAISE EXCEPTION 'Duration must be 1–3 hours (got %).', p_duration_hours
            USING ERRCODE = 'check_violation';
    END IF;
    IF EXTRACT(MINUTE FROM p_start_time) <> 0 OR EXTRACT(SECOND FROM p_start_time) <> 0 THEN
        RAISE EXCEPTION 'Booking must start on the hour (got %).', p_start_time
            USING ERRCODE = 'check_violation';
    END IF;
    IF (p_start_time AT TIME ZONE 'Africa/Lagos')::time < TIME '07:00'
       OR (p_start_time AT TIME ZONE 'Africa/Lagos') + p_duration_hours * INTERVAL '1 hour'
          > date_trunc('day', p_start_time AT TIME ZONE 'Africa/Lagos') + INTERVAL '23 hours' THEN
        RAISE EXCEPTION 'Booking must be inside opening hours 07:00-23:00 (got %..%).',
            p_start_time, p_start_time + make_interval(hours => p_duration_hours)
            USING ERRCODE = 'check_violation';
    END IF;

    -- 1) Look up the price for this pitch, weekday and time band.
    v_dow := EXTRACT(DOW FROM p_start_time AT TIME ZONE 'Africa/Lagos')::integer;
    v_first_peak_hr := CASE WHEN v_dow IN (0,6) THEN 7 ELSE 17 END;
    SELECT count(*) INTO v_peak_rows
      FROM pricing
     WHERE pitch_id = p_pitch_id
       AND day_of_week = v_dow
       AND period = 'peak'
       AND p_start_time::date BETWEEN valid_from AND valid_to;
    SELECT count(*) INTO v_offpeak_rows
      FROM pricing
     WHERE pitch_id = p_pitch_id
       AND day_of_week = v_dow
       AND period = 'off_peak'
       AND p_start_time::date BETWEEN valid_from AND valid_to;

    -- Compute the deposit as peak_rate × peak_hours + offpeak_rate × offpeak_hours.
    SELECT
        coalesce(sum(CASE
            WHEN h.hour_slot >= v_first_peak_hr THEN
                (SELECT rate FROM pricing
                  WHERE pitch_id = p_pitch_id
                    AND day_of_week = v_dow
                    AND period = 'peak'
                    AND p_start_time::date BETWEEN valid_from AND valid_to
                  LIMIT 1)
            ELSE
                (SELECT rate FROM pricing
                  WHERE pitch_id = p_pitch_id
                    AND day_of_week = v_dow
                    AND period = 'off_peak'
                    AND p_start_time::date BETWEEN valid_from AND valid_to
                  LIMIT 1)
        END), 0)
    INTO v_final_amount
    FROM generate_series(
        EXTRACT(HOUR FROM p_start_time AT TIME ZONE 'Africa/Lagos')::int,
        EXTRACT(HOUR FROM p_start_time AT TIME ZONE 'Africa/Lagos')::int + p_duration_hours - 1
    ) AS h(hour_slot);

    -- If the caller passed an explicit amount, use it; otherwise use computed rate.
    IF p_amount IS NOT NULL THEN
        v_final_amount := p_amount;
    END IF;
    IF v_final_amount <= 0 THEN
        RAISE EXCEPTION 'Cannot take a deposit of ₦0 or less (computed %).', v_final_amount
            USING ERRCODE = 'check_violation';
    END IF;

    -- 2) Check team has at least 5 players.
    SELECT count(*) INTO v_player_count FROM team_member WHERE team_id = p_team_id;
    IF v_player_count < 5 THEN
        RAISE EXCEPTION 'Team % has only % players; at least 5 required to book.',
            p_team_id, v_player_count USING ERRCODE = 'check_violation';
    END IF;

    -- 3) Check slot is free.
    v_provisional_rng := tstzrange(
        p_start_time,
        p_start_time + make_interval(hours => p_duration_hours),
        '[)');
    SELECT b.booking_id INTO v_existing
      FROM booking b
     WHERE b.pitch_id = p_pitch_id
       AND b.status = 'confirmed'
       AND b.time_range && v_provisional_rng
     LIMIT 1;
    IF v_existing IS NOT NULL THEN
        RAISE EXCEPTION
            'Slot not available on pitch % between % and % (conflicts with booking %).',
            p_pitch_id, p_start_time, p_start_time + make_interval(hours => p_duration_hours),
            v_existing
            USING ERRCODE = 'raise_exception';
    END IF;

    -- 4) INSERT booking. The trigger populates time_range; the exclusion
    --    constraint (booking_no_overlap) is what actually stops a concurrent double booking.
    INSERT INTO booking (pitch_id, team_id, start_time, duration_hours, status)
    VALUES (p_pitch_id, p_team_id, p_start_time, p_duration_hours, 'confirmed')
    RETURNING booking_id INTO v_booking_id;

    -- 5) Take the deposit. If this INSERT fails (e.g. amount = 0 or a foreign
    --    key violation), the exception propagates and the transaction rolls
    --    back, undoing the booking row inserted in step 4.
    INSERT INTO payment (booking_id, amount, currency, method, status, paid_at)
    VALUES (v_booking_id, v_final_amount, 'NGN', p_method, 'succeeded', now());

    RETURN v_booking_id;
END;
$$ LANGUAGE plpgsql;

-- =========================================================================
-- Demo 1: happy path — book a clearly free slot, see the row appear.
-- =========================================================================
-- Own demo data (so the demos never depend on random bulk rows): a pitch with
-- pricing copied from pitch 1, and a team with 6 players.
DELETE FROM team WHERE name = 'P3 Demo Team';
DELETE FROM pitch WHERE name = 'P3 Demo Pitch';
DELETE FROM player WHERE last_name = 'P3Demo';
INSERT INTO pitch (location_id, name, surface_type, capacity)
  SELECT location_id, 'P3 Demo Pitch', 'artificial_turf', 10 FROM pitch WHERE pitch_id = (SELECT min(pitch_id) FROM pitch);
INSERT INTO pricing (pitch_id, day_of_week, period, rate, valid_from, valid_to)
  SELECT (SELECT pitch_id FROM pitch WHERE name='P3 Demo Pitch'), day_of_week, period, rate, valid_from, valid_to
    FROM pricing WHERE pitch_id = (SELECT min(pitch_id) FROM pitch);
INSERT INTO team (name, captain_name) VALUES ('P3 Demo Team', 'Demo Captain');
INSERT INTO player (first_name, last_name) SELECT 'Demo'||g, 'P3Demo' FROM generate_series(1,6) g;
INSERT INTO team_member (team_id, player_id)
  SELECT (SELECT team_id FROM team WHERE name='P3 Demo Team'), player_id FROM player WHERE last_name='P3Demo';
SELECT pitch_id AS dp FROM pitch WHERE name='P3 Demo Pitch' \gset
SELECT team_id  AS dt FROM team  WHERE name='P3 Demo Team'  \gset

\echo ''
\echo '====== Demo 1: happy path (book_pitch succeeds) ======'
\echo ''
DROP TABLE IF EXISTS p3_demo_results;
CREATE TEMP TABLE p3_demo_results (step TEXT, count BIGINT);

INSERT INTO p3_demo_results VALUES ('bookings before', (SELECT count(*) FROM booking));
INSERT INTO p3_demo_results VALUES ('payments before', (SELECT count(*) FROM payment));

SELECT book_pitch(
    :dp,                                            -- pitch_id (P3 Demo Pitch)
    :dt,                                            -- team_id (P3 Demo Team, 6 players)
    ((CURRENT_DATE + 7) + TIME '09:00') AT TIME ZONE 'Africa/Lagos',
    1,                                              -- 1 hour
    'card', NULL                                    -- auto-compute the price
) AS new_booking_id \gset

INSERT INTO p3_demo_results VALUES ('bookings after happy-path', (SELECT count(*) FROM booking));
INSERT INTO p3_demo_results VALUES ('payments after happy-path',  (SELECT count(*) FROM payment));

SELECT * FROM p3_demo_results;
SELECT b.booking_id, b.pitch_id, b.team_id, b.start_time, b.duration_hours, b.status,
       p.amount, p.method, p.status AS payment_status
  FROM booking b JOIN payment p USING (booking_id)
 WHERE b.booking_id = :new_booking_id;

-- =========================================================================
-- Demo 2: failure path — call book_pitch() inside a transaction and force a
-- payment failure (amount = 0). The booking row that was inserted must be
-- rolled back — no orphaned booking.
-- =========================================================================
\echo ''
\echo '====== Demo 2: failure path (payment fails → whole transaction rolls back) ======'
\echo ''
DROP TABLE IF EXISTS p3_demo_fail;
CREATE TEMP TABLE p3_demo_fail (step TEXT, count BIGINT);
INSERT INTO p3_demo_fail VALUES ('bookings before', (SELECT count(*) FROM booking));
INSERT INTO p3_demo_fail VALUES ('payments before', (SELECT count(*) FROM payment));

-- A PL/pgSQL DO block is the right container for an EXCEPTION handler.
-- Inside the DO block:
--   1) INSERT a booking (succeeds)
--   2) INSERT a payment with amount = 0 (fails with check_violation)
-- When the EXCEPTION clause catches the error, PostgreSQL automatically
-- rolls back ALL changes made inside the DO block — including the booking
-- INSERT from step 1. So no orphaned booking row is left behind.
DO $$
DECLARE
    v_bid BIGINT;
BEGIN
    INSERT INTO booking (pitch_id, team_id, start_time, duration_hours, status)
    SELECT p.pitch_id, t.team_id,
           ((CURRENT_DATE + 8) + TIME '11:00') AT TIME ZONE 'Africa/Lagos',
           1, 'confirmed'
      FROM pitch p, team t WHERE p.name = 'P3 Demo Pitch' AND t.name = 'P3 Demo Team'
    RETURNING booking_id INTO v_bid;

    -- This next INSERT must fail because amount = 0 violates payment_amount_positive_chk.
    INSERT INTO payment (booking_id, amount, currency, method, status)
    VALUES (v_bid, 0, 'NGN', 'card', 'failed');
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'Payment failed as expected: %', SQLERRM;
    -- The subtransaction inside this DO block is rolled back automatically.
    -- Both the booking INSERT and the failed payment INSERT are undone.
END
$$;

-- Outside the DO block, the row counts show the booking was undone.
INSERT INTO p3_demo_fail VALUES ('bookings after rollback', (SELECT count(*) FROM booking));
INSERT INTO p3_demo_fail VALUES ('payments after rollback',  (SELECT count(*) FROM payment));
SELECT * FROM p3_demo_fail;

\echo ''
\echo 'If the row counts "before" and "after rollback" match, the booking was'
\echo 'rolled back atomically with the failed payment — no orphaned rows.'
