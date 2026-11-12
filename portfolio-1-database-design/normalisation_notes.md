# Normalisation Notes (3NF) — KickOff Arena

Each table below is shown first as it would look as a "flat" spreadsheet (1NF)
or with partial / transitive dependencies (2NF→3NF problems), and then in its
final 3NF form. The 3NF column matches `schema.sql` exactly.

The case study stores the following kinds of facts: locations, pitches, teams,
players, team membership, hourly bookings, payments, match results and peak /
off-peak pricing. The normalisation walk-through below shows why the obvious
"one big bookings spreadsheet" is not 3NF and how it is decomposed.

---

## 1NF — first normal form

A relation is in 1NF when every attribute holds atomic values and there are no
repeating groups. The KickOff Arena booking register reaches 1NF as soon as we
stop storing, e.g. `players` as a comma-separated list inside the booking row
and instead split players into their own `PLAYER` rows, with a `TEAM_MEMBER`
link table capturing team membership.

## 2NF — second normal form

A relation is in 2NF when every non-key attribute depends on the **whole**
primary key. The `TEAM_MEMBER` link table has a composite key
`(team_id, player_id)`. The only attribute that depends on both keys is
`joined_at` and `role`, so this is already 2NF. By contrast, putting
`captain_name` (depends only on `team_id`) into `TEAM_MEMBER` would be a 2NF
violation, so `captain_name` stays in `TEAM`.

## 3NF — third normal form

A relation is in 3NF when no non-key attribute transitively depends on the
primary key. The trickiest case is `BOOKING`: storing the pitch's
`location_id` directly on `BOOKING` (alongside `pitch_id`) would be a 3NF
violation because `location_id` transitively depends on `booking_id` via
`pitch_id`. The 3NF design therefore keeps `location_id` only on `PITCH` and
joins through it when needed.

---

## Table-by-table 3NF justification

### location
- **PK:** `location_id`
- **Attributes:** `name, area, address, opens_at, closes_at, created_at`
- **3NF check:** every attribute depends only on `location_id`. No partial or
  transitive dependencies. `opens_at` / `closes_at` belong to the location
  (a location can choose to open at 07:00 and close at 23:00), not to a pitch,
  so they live here.

### pitch
- **PK:** `pitch_id`
- **FK:** `location_id → location`
- **Attributes:** `name, surface_type, capacity, active`
- **3NF check:** `surface_type`, `capacity` and `active` depend only on the
  pitch, not on the location or on any booking. `location_id` is a foreign key
  (a relationship, not a transitive dependency).

### team
- **PK:** `team_id`
- **Attributes:** `name, captain_name, phone, email, created_at`
- **3NF check:** `captain_name`, `phone`, `email` describe the team itself. We
  do **not** embed "captain's home address" here (it would depend on the
  captain, not the team — i.e. transitive on `captain_name`).

### player
- **PK:** `player_id`
- **Attributes:** `first_name, last_name, phone, email, dob`
- **3NF check:** all attributes depend only on the player. `dob` is atomic,
  `phone` and `email` are scalar.

### team_member
- **PK:** `(team_id, player_id)` — composite
- **FK:** `team_id → team`, `player_id → player`
- **Attributes:** `role, joined_at`
- **3NF check:** `role` and `joined_at` depend on the *membership* — i.e. on
  the *pair* `(team_id, player_id)` — and not on team or player alone. This
  is the canonical 2NF/3NF pattern for an associative entity.

### pricing
- **PK:** `pricing_id`
- **FK:** `pitch_id → pitch`
- **Attributes:** `day_of_week, period, peak_rate, off_peak_rate, valid_from, valid_to`
- **3NF check:** rates depend on `(pitch_id, day_of_week, period,
  valid_from)`, all of which are attributes of the same row. We do **not**
  put `peak_rate` on `BOOKING` (transitive on `pitch_id`); instead the rate
  is looked up at booking time and copied onto `PAYMENT.amount`.

### booking
- **PK:** `booking_id`
- **FK:** `pitch_id → pitch`, `team_id → team`
- **Attributes:** `start_time, duration_hours, time_range, status, created_at`
- **3NF check:** the only attributes carried are the ones that describe the
  booking itself. We deliberately avoid carrying `pitch_name`, `team_name`,
  `peak_rate`, `captain_phone` etc. here — those are looked up by join. The
  derived column `time_range tstzrange` is a *functional dependency* of
  `(start_time, duration_hours)` used purely to host the exclusion
  constraint; it is kept in sync by a trigger so it is not a 3NF violation
  (it is a stored generated value, not a transitive fact).

### payment
- **PK:** `payment_id`
- **FK:** `booking_id → booking`
- **Attributes:** `amount, currency, method, status, paid_at`
- **3NF check:** `amount`, `method`, `status` and `paid_at` depend only on the
  payment, not on the booking or the team. The `amount > 0` rule is enforced
  by `CHECK`.

### match_result
- **PK:** `match_id`
- **FK:** `booking_id → booking`, `home_team_id → team`, `away_team_id → team`
- **Attributes:** `home_score, away_score, played_at`
- **3NF check:** scores and timestamp depend only on the match. We do **not**
  embed the scorer list here — the rich, variable-shape scorer / card / notes
  data is the natural home of a document store, and is therefore moved to
  MongoDB in Portfolio 4. The SQL `match_result` table holds only the
  structured, fixed-shape summary needed for relational integrity.

---

## Summary

| Table | PK | Notable 3NF decision |
|---|---|---|
| location | `location_id` | opening hours live here, not on pitch |
| pitch | `pitch_id` | only pitch-level attributes; `location_id` is a FK |
| team | `team_id` | captain details stay here; not duplicated on booking |
| player | `player_id` | scalar contact fields, atomic `dob` |
| team_member | `(team_id, player_id)` | composite key — pure associative entity |
| pricing | `pricing_id` | rates depend on `(pitch, day_of_week, period, validity)` |
| booking | `booking_id` | no transitive copies of pitch/team facts; `time_range` is derived for the exclusion constraint |
| payment | `payment_id` | amount/method/status only; `amount > 0` enforced by CHECK |
| match_result | `match_id` | only the structured summary; rich scorer data → MongoDB |

All nine tables are in **third normal form (3NF)**. The schema also satisfies
**BCNF** for every non-trivial functional dependency, because every
determinant is a candidate key.
