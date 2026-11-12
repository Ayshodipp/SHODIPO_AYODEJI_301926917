-- =============================================================================
-- seed.sql — small hand-written seed for KickOff Arena
-- Portfolio 1, MIT 8103
-- Run AFTER schema.sql:
--   psql -h /var/run/postgresql -U kickoff kickoff -f seed.sql
--
-- This file is intentionally small: it gives a few known rows for the
-- constraint tests in constraint_tests.sql and for sanity checks. The 50 000+
-- booking workload comes from bulk_seed.py.
-- =============================================================================

\set ON_ERROR_STOP on
SET TIME ZONE 'Africa/Lagos';

BEGIN;

-- 4 Lagos locations (opens 07:00, closes 23:00)
INSERT INTO location (name, area, address, opens_at, closes_at) VALUES
  ('KickOff Lekki',     'Lekki',     '12 Admiralty Way, Lekki Phase 1',     '07:00', '23:00'),
  ('KickOff Yaba',      'Yaba',      '5 Tejuosho Road, Yaba',                '07:00', '23:00'),
  ('KickOff Ikeja',     'Ikeja',     '78 Allen Avenue, Ikeja',               '07:00', '23:00'),
  ('KickOff Surulere',  'Surulere',  '21 Adeniran Ogunsanya St, Surulere',   '07:00', '23:00');

-- 8 pitches (2 per location)
INSERT INTO pitch (location_id, name, surface_type, capacity) VALUES
  (1, 'Lekki Pitch A', 'artificial_turf', 10),
  (1, 'Lekki Pitch B', 'grass',           10),
  (2, 'Yaba Pitch A',  'artificial_turf', 10),
  (2, 'Yaba Pitch B',  'indoor',          10),
  (3, 'Ikeja Pitch A', 'artificial_turf', 12),
  (3, 'Ikeja Pitch B', 'concrete',        10),
  (4, 'Surulere Pitch A','artificial_turf',10),
  (4, 'Surulere Pitch B','grass',          8);

-- Pricing for every pitch × every weekday × peak/off_peak.
-- Peak = 17:00–23:00 weekdays and all day weekends.
-- Off-peak = 07:00–17:00 weekdays.
INSERT INTO pricing (pitch_id, day_of_week, period, rate, valid_from, valid_to)
SELECT p.pitch_id,
       d.dow,
       CASE WHEN d.period = 'peak' THEN 'peak' ELSE 'off_peak' END,
       CASE
         WHEN d.period = 'peak' AND d.dow IN (0,6) THEN 25000  -- weekend peak ₦25,000
         WHEN d.period = 'peak'                   THEN 18000  -- weekday peak ₦18,000
         ELSE 9000                                            -- off-peak ₦9,000
       END,
       CURRENT_DATE,
       CURRENT_DATE + INTERVAL '2 years'
  FROM pitch p
  CROSS JOIN (
    VALUES (0,'peak'),(0,'off_peak'),
           (1,'peak'),(1,'off_peak'),
           (2,'peak'),(2,'off_peak'),
           (3,'peak'),(3,'off_peak'),
           (4,'peak'),(4,'off_peak'),
           (5,'peak'),(5,'off_peak'),
           (6,'peak'),(6,'off_peak')
  ) AS d(dow, period);

-- Two teams — only one has the minimum 5 players required to book.
INSERT INTO team (name, captain_name, phone, email) VALUES
  ('Lekki Lions FC',   'Tunde Bello',  '0801 111 0001', 'captain@lekkilions.ng'),
  ('Surulere Strikers','Chidi Okafor',  '0801 111 0002', 'captain@surulerestrikers.ng');

-- 10 players — 5 attached to Lekki Lions FC, 4 to Surulere Strikers (deliberate: 4 < 5).
INSERT INTO player (first_name, last_name, phone, email, dob) VALUES
  ('Tunde',  'Bello',     '0802 000 0001','tunde.bello@example.com',    '1996-03-12'),
  ('Ade',    'Olawale',   '0802 000 0002','ade.olawale@example.com',    '1998-07-04'),
  ('Kunle',  'Adeyemi',   '0802 000 0003','kunle.adeyemi@example.com',  '1995-11-22'),
  ('Bola',   'Oyeleye',   '0802 000 0004','bola.oyeleye@example.com',   '1999-01-30'),
  ('Danjuma','Ibrahim',   '0802 000 0005','danjuma.ibrahim@example.com','2000-09-15'),
  ('Chidi',  'Okafor',    '0802 000 0006','chidi.okafor@example.com',   '1997-05-19'),
  ('Emeka',  'Nwosu',     '0802 000 0007','emeka.nwosu@example.com',    '1996-08-08'),
  ('Femi',   'Adesanya',  '0802 000 0008','femi.adesanya@example.com',  '2001-02-25'),
  ('Tobi',   'Akinwale',  '0802 000 0009','tobi.akinwale@example.com',  '1994-12-09');

INSERT INTO team_member (team_id, player_id, role, joined_at) VALUES
  (1, 1, 'captain',      CURRENT_DATE - INTERVAL '180 days'),
  (1, 2, 'player',       CURRENT_DATE - INTERVAL '180 days'),
  (1, 3, 'player',       CURRENT_DATE - INTERVAL '160 days'),
  (1, 4, 'player',       CURRENT_DATE - INTERVAL '160 days'),
  (1, 5, 'vice_captain', CURRENT_DATE - INTERVAL '120 days'),
  (2, 6, 'captain',      CURRENT_DATE - INTERVAL '90 days'),
  (2, 7, 'player',       CURRENT_DATE - INTERVAL '90 days'),
  (2, 8, 'player',       CURRENT_DATE - INTERVAL '80 days'),
  (2, 9, 'player',       CURRENT_DATE - INTERVAL '70 days');

-- One booking that satisfies every constraint (Lekki Lions FC at Lekki Pitch A,
-- tomorrow 09:00 for 1 hour). The trigger computes time_range; payment_amount
-- > 0; team has 5 players; pitch open 07:00–23:00.
INSERT INTO booking (pitch_id, team_id, start_time, duration_hours, status)
VALUES (1, 1, ((CURRENT_DATE + 1) + TIME '09:00') AT TIME ZONE 'Africa/Lagos', 1, 'confirmed');

INSERT INTO payment (booking_id, amount, currency, method, status)
SELECT booking_id, 9000, 'NGN', 'card', 'succeeded'
  FROM booking ORDER BY booking_id DESC LIMIT 1;

COMMIT;

-- ============================================================================
-- Sanity check: prints counts. Expected after seed.sql only (before bulk_seed):
--   locations=4  pitches=8  teams=2  players=9  team_members=9  bookings=1
--                payments=1
-- ============================================================================
SELECT 'locations'   AS t, count(*) FROM location
UNION ALL SELECT 'pitches',      count(*) FROM pitch
UNION ALL SELECT 'teams',        count(*) FROM team
UNION ALL SELECT 'players',      count(*) FROM player
UNION ALL SELECT 'team_members', count(*) FROM team_member
UNION ALL SELECT 'pricing_rows', count(*) FROM pricing
UNION ALL SELECT 'bookings',     count(*) FROM booking
UNION ALL SELECT 'payments',     count(*) FROM payment;
