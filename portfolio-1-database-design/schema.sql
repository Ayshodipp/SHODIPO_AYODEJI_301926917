-- =============================================================================
-- schema.sql — KickOff Arena relational schema (3NF) for PostgreSQL 16
-- Portfolio 1, MIT 8103 Advanced Database Systems
-- Student: Ayodeji Shodipo · 2026/A/MIT/0725
-- Case study: KickOff Arena — 5-a-side pitch booking (Lagos)
-- Study session covered: SS1 (ER modelling, normalisation, constraints).
--
-- Connect (Codespaces, Unix socket — no password):
--   sudo runuser -u postgres -- psql -d kickoff -f schema.sql
-- or, as the kickoff role:
--   PGPASSWORD=kickoff_dev_pw psql -h /var/run/postgresql -U kickoff kickoff -f schema.sql
-- =============================================================================

\set ON_ERROR_STOP on
SET TIME ZONE 'Africa/Lagos';

BEGIN;

-- ---------- extensions -----------------------------------------------------
CREATE EXTENSION IF NOT EXISTS btree_gist;   -- tstzrange exclusion constraint
CREATE EXTENSION IF NOT EXISTS pgcrypto;     -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pg_trgm;      -- used by P2 trigram index

-- ---------- drop existing objects (idempotent re-runs) ---------------------
DROP TABLE IF EXISTS match_result   CASCADE;
DROP TABLE IF EXISTS payment        CASCADE;
DROP TABLE IF EXISTS booking        CASCADE;
DROP TABLE IF EXISTS team_member    CASCADE;
DROP TABLE IF EXISTS pricing        CASCADE;
DROP TABLE IF EXISTS player         CASCADE;
DROP TABLE IF EXISTS team           CASCADE;
DROP TABLE IF EXISTS pitch          CASCADE;
DROP TABLE IF EXISTS location       CASCADE;
DROP FUNCTION IF EXISTS check_team_size() CASCADE;
DROP FUNCTION IF EXISTS sync_booking_time_range() CASCADE;

-- =========================================================================
-- 1. location  — 4 Lagos areas where KickOff Arena operates pitches
-- =========================================================================
CREATE TABLE location (
    location_id  BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name         TEXT         NOT NULL,
    area         TEXT         NOT NULL,
    address      TEXT         NOT NULL,
    opens_at     TIME         NOT NULL,         -- daily opening time
    closes_at    TIME         NOT NULL,         -- daily closing time
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT location_open_before_close CHECK (opens_at < closes_at),
    CONSTRAINT location_area_chk CHECK (
        area IN ('Lekki','Yaba','Ikeja','Surulere')
    )
);

-- =========================================================================
-- 2. pitch  — a single 5-a-side pitch at a location
-- =========================================================================
CREATE TABLE pitch (
    pitch_id     BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    location_id  BIGINT       NOT NULL REFERENCES location(location_id) ON DELETE RESTRICT,
    name         TEXT         NOT NULL,
    surface_type TEXT         NOT NULL,
    capacity     INTEGER      NOT NULL CHECK (capacity BETWEEN 5 AND 12),
    active       BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT pitch_surface_chk CHECK (
        surface_type IN ('artificial_turf','grass','indoor','concrete')
    )
);
CREATE INDEX pitch_location_idx ON pitch(location_id);

-- =========================================================================
-- 3. team  — a group of players that books pitches
-- =========================================================================
CREATE TABLE team (
    team_id      BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name         TEXT         NOT NULL UNIQUE,
    captain_name TEXT         NOT NULL,
    phone        TEXT,
    email        TEXT,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- =========================================================================
-- 4. player  — an individual football player
-- =========================================================================
CREATE TABLE player (
    player_id    BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name   TEXT         NOT NULL,
    last_name    TEXT         NOT NULL,
    phone        TEXT,
    email        TEXT,
    dob          DATE,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX player_name_trgm ON player USING gin (first_name gin_trgm_ops);

-- =========================================================================
-- 5. team_member  — many-to-many between team and player
-- =========================================================================
CREATE TABLE team_member (
    team_id      BIGINT       NOT NULL REFERENCES team(team_id)    ON DELETE CASCADE,
    player_id    BIGINT       NOT NULL REFERENCES player(player_id) ON DELETE CASCADE,
    role         TEXT         NOT NULL DEFAULT 'player'
                  CHECK (role IN ('captain','vice_captain','player')),
    joined_at    DATE         NOT NULL DEFAULT CURRENT_DATE,
    PRIMARY KEY (team_id, player_id)
);
CREATE INDEX team_member_player_idx ON team_member(player_id);

-- =========================================================================
-- 6. pricing  — peak and off-peak hourly rates per pitch, per weekday
--    day_of_week: 0=Sunday … 6=Saturday (matches PostgreSQL EXTRACT(DOW FROM …))
-- =========================================================================
CREATE TABLE pricing (
    pricing_id    BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pitch_id      BIGINT      NOT NULL REFERENCES pitch(pitch_id) ON DELETE CASCADE,
    day_of_week   INTEGER     NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    period        TEXT         NOT NULL CHECK (period IN ('peak','off_peak')),
    rate          NUMERIC(10,2) NOT NULL CHECK (rate > 0),
    valid_from    DATE         NOT NULL,
    valid_to      DATE         NOT NULL,
    CONSTRAINT pricing_window_chk CHECK (valid_from <= valid_to)
);
CREATE UNIQUE INDEX pricing_pitch_dow_period_window_uidx
    ON pricing (pitch_id, day_of_week, period, valid_from);
CREATE INDEX pricing_pitch_idx ON pricing(pitch_id);

-- =========================================================================
-- 7. booking  — hourly pitch booking by a team
--    The tstzrange column carries (start_time, start_time + duration_hours).
--    It is populated by a BEFORE INSERT/UPDATE trigger so it is always in
--    sync; the EXCLUDE constraint uses it to reject overlapping bookings.
-- =========================================================================
CREATE TABLE booking (
    booking_id     BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pitch_id       BIGINT      NOT NULL REFERENCES pitch(pitch_id)    ON DELETE RESTRICT,
    team_id        BIGINT      NOT NULL REFERENCES team(team_id)      ON DELETE RESTRICT,
    start_time     TIMESTAMPTZ NOT NULL,
    duration_hours INTEGER      NOT NULL,
    time_range     tstzrange,                       -- populated by trigger
    status         TEXT         NOT NULL DEFAULT 'confirmed'
                     CHECK (status IN ('confirmed','cancelled','completed','no_show')),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- (a) start on the hour and last 1–3 hours
    CONSTRAINT booking_hourly_start_chk CHECK (
        EXTRACT(MINUTE FROM start_time) = 0
        AND EXTRACT(SECOND FROM start_time) = 0
        AND duration_hours BETWEEN 1 AND 3
    ),
    -- (b) only inside opening hours 07:00–23:00 in the session time zone
    CONSTRAINT booking_opening_hours_chk CHECK (
        (start_time AT TIME ZONE 'Africa/Lagos')::time >= TIME '07:00'
        AND (start_time AT TIME ZONE 'Africa/Lagos') + duration_hours * INTERVAL '1 hour'
            <= date_trunc('day', start_time AT TIME ZONE 'Africa/Lagos') + INTERVAL '23 hours'
    ),
    -- (c) status transitions
    CONSTRAINT booking_status_chk CHECK (
        status <> 'cancelled' OR true   -- placeholder; real transitions enforced in P3
    )
);

-- (d) NO OVERLAPPING BOOKINGS on the same pitch — exclusion constraint
--     using btree_gist so we can mix a scalar (=) with a range (&&).
CREATE EXTENSION IF NOT EXISTS btree_gist;
ALTER TABLE booking
    ADD CONSTRAINT booking_no_overlap
    EXCLUDE USING gist (
        pitch_id   WITH =,
        time_range WITH &&
    )
    WHERE (status = 'confirmed');   -- only confirmed bookings block each other

CREATE INDEX booking_pitch_start_idx ON booking(pitch_id, start_time);
CREATE INDEX booking_team_idx       ON booking(team_id);
CREATE INDEX booking_status_idx     ON booking(status);

-- Trigger: keep time_range in sync with start_time + duration_hours.
CREATE OR REPLACE FUNCTION sync_booking_time_range()
RETURNS trigger AS $$
BEGIN
    NEW.time_range := tstzrange(
        NEW.start_time,
        NEW.start_time + make_interval(hours => NEW.duration_hours),
        '[)'
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_booking_time_range
BEFORE INSERT OR UPDATE OF start_time, duration_hours ON booking
FOR EACH ROW EXECUTE FUNCTION sync_booking_time_range();

-- (e) A team needs at least 5 players to book.
CREATE OR REPLACE FUNCTION check_team_size()
RETURNS trigger AS $$
DECLARE
    player_count INTEGER;
BEGIN
    SELECT count(*) INTO player_count
      FROM team_member
     WHERE team_id = NEW.team_id;
    IF player_count < 5 THEN
        RAISE EXCEPTION
            'Team % has only % registered players; at least 5 required to book a pitch.',
            NEW.team_id, player_count
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_team_size
BEFORE INSERT OR UPDATE OF team_id ON booking
FOR EACH ROW EXECUTE FUNCTION check_team_size();

-- =========================================================================
-- 8. payment  — settlement for a booking (deposit at booking time)
-- =========================================================================
CREATE TABLE payment (
    payment_id  BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    booking_id  BIGINT        NOT NULL REFERENCES booking(booking_id) ON DELETE CASCADE,
    amount      NUMERIC(12,2) NOT NULL,
    currency    TEXT          NOT NULL DEFAULT 'NGN',
    method      TEXT          NOT NULL CHECK (method IN ('card','transfer','wallet','cash')),
    status      TEXT          NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','succeeded','failed','refunded')),
    paid_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    -- amount > 0 — required constraint
    CONSTRAINT payment_amount_positive_chk CHECK (amount > 0),
    CONSTRAINT payment_amount_max_chk       CHECK (amount <= 1000000)
);
CREATE INDEX payment_booking_idx ON payment(booking_id);
CREATE INDEX payment_status_idx  ON payment(status);
CREATE INDEX payment_paid_at_idx ON payment(paid_at);

-- =========================================================================
-- 9. match_result  — structured summary of a played match
--    (rich scorer / card / notes data lives in MongoDB in Portfolio 4)
-- =========================================================================
CREATE TABLE match_result (
    match_id       BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    booking_id     BIGINT       NOT NULL REFERENCES booking(booking_id) ON DELETE CASCADE,
    home_team_id   BIGINT       NOT NULL REFERENCES team(team_id),
    away_team_id   BIGINT       NOT NULL REFERENCES team(team_id),
    home_score     INTEGER      NOT NULL CHECK (home_score >= 0),
    away_score     INTEGER      NOT NULL CHECK (away_score >= 0),
    played_at      TIMESTAMPTZ  NOT NULL,
    CONSTRAINT match_result_teams_differ_chk CHECK (home_team_id <> away_team_id)
);
CREATE INDEX match_result_booking_idx ON match_result(booking_id);
CREATE INDEX match_result_home_idx    ON match_result(home_team_id);
CREATE INDEX match_result_away_idx    ON match_result(away_team_id);

COMMIT;

-- =============================================================================
-- Verification queries (run after schema.sql + seed.sql + bulk_seed.py).
-- =============================================================================
-- \dt
-- \d+ booking
-- \d+ payment
-- SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
--   WHERE conrelid = 'booking'::regclass ORDER BY conname;
