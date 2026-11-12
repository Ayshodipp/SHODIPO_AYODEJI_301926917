# ER Diagram — KickOff Arena (5-a-side pitch booking)

Mermaid renders this diagram natively on GitHub. Open this file on the GitHub
web UI to see it.

```mermaid
erDiagram
    LOCATION ||--o{ PITCH : "hosts"
    PITCH ||--o{ PRICING : "priced by"
    PITCH ||--o{ BOOKING : "is booked in"
    TEAM ||--o{ TEAM_MEMBER : "has"
    PLAYER ||--o{ TEAM_MEMBER : "belongs to"
    TEAM ||--o{ BOOKING : "makes"
    BOOKING ||--|| PAYMENT : "settled by"
    BOOKING ||--o| MATCH_RESULT : "produces"

    LOCATION {
        bigint   location_id PK
        text     name
        text     area
        text     address
        time     opens_at
        time     closes_at
        timestamptz created_at
    }

    PITCH {
        bigint   pitch_id PK
        bigint   location_id FK
        text     name
        text     surface_type
        int      capacity
        boolean  active
    }

    PRICING {
        bigint   pricing_id PK
        bigint   pitch_id FK
        int      day_of_week
        text     period
        numeric  peak_rate
        numeric  off_peak_rate
        date     valid_from
        date     valid_to
    }

    TEAM {
        bigint   team_id PK
        text     name
        text     captain_name
        text     phone
        text     email
        timestamptz created_at
    }

    PLAYER {
        bigint   player_id PK
        text     first_name
        text     last_name
        text     phone
        text     email
        date     dob
    }

    TEAM_MEMBER {
        bigint   team_id PK,FK
        bigint   player_id PK,FK
        text     role
        date     joined_at
    }

    BOOKING {
        bigint      booking_id PK
        bigint      pitch_id FK
        bigint      team_id FK
        timestamptz start_time
        int         duration_hours
        tstzrange   time_range
        text        status
        timestamptz created_at
    }

    PAYMENT {
        bigint      payment_id PK
        bigint      booking_id FK
        numeric     amount
        text        currency
        text        method
        text        status
        timestamptz paid_at
    }

    MATCH_RESULT {
        bigint      match_id PK
        bigint      booking_id FK
        bigint      home_team_id FK
        bigint      away_team_id FK
        int         home_score
        int         away_score
        timestamptz played_at
    }
```

## Cardinality notes

- A `LOCATION` has many `PITCH`es; a `PITCH` belongs to exactly one location.
- A `PITCH` has many `PRICING` rows (one per day-of-week × period).
- A `TEAM` ↔ `PLAYER` is many-to-many through `TEAM_MEMBER`.
- A `BOOKING` is for exactly one `PITCH` made by exactly one `TEAM`.
- A `BOOKING` has exactly one `PAYMENT` (a deposit at booking time; refunds
  update the same row).
- A `BOOKING` may produce at most one `MATCH_RESULT` (the match is played after
  the booking; some bookings end in a no-show, in which case there is no row).

## How the exclusion constraint fits

The `BOOKING` table stores both `start_time` and a derived `time_range
tstzrange`. The exclusion constraint `EXCLUDE USING gist (pitch_id WITH =,
time_range WITH &&)` is what actually enforces "no overlapping bookings on the
same pitch". The `start_time`, `duration_hours` columns are kept for
readability and for the CHECK constraints.
