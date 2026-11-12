#!/usr/bin/env python3
"""
bulk_seed.py — generate 50 000+ bookings over 2 years for KickOff Arena.
Portfolio 1, MIT 8103 Advanced Database Systems.

Design goals
------------
* Generate **at least 50 000** booking rows spread over a rolling 2-year
  window (1 year in the past, 1 year in the future) anchored on **today**,
  so the data never "expires" relative to the run date.
* **No two bookings on the same pitch overlap** — enforced locally by
  tracking, per pitch, the set of (date, hour) slots already used.
* Bookings start on the hour (minute=0, second=0) and last 1–3 hours.
* Bookings stay inside opening hours 07:00–23:00 Africa/Lagos time.
* Realistic Lagos team names, Nigerian player names, peak / off-peak prices.
* Each booking is paired with one payment row (amount > 0).
* Each booking may (probabilistically) also produce a match_result row.

Run:
    python3 portfolio-1-database-design/bulk_seed.py

Connects through the Unix socket (no password) as the `kickoff` role.
"""

from __future__ import annotations
import os
import random
import sys
from datetime import date, datetime, timedelta, time, timezone
import psycopg

# ---------- configuration ---------------------------------------------------
DB_NAME = os.environ.get("KICKOFF_DB", "kickoff")
DB_USER = os.environ.get("KICKOFF_USER", "kickoff")
DB_HOST = os.environ.get("KICKOFF_HOST", "/var/run/postgresql")  # Unix socket
DB_PW   = os.environ.get("KICKOFF_PW", "kickoff_dev_pw")

TARGET_BOOKINGS = 50_000            # well above the 50k minimum
LOCATIONS       = [
    ("KickOff Lekki",    "Lekki",    "12 Admiralty Way, Lekki Phase 1"),
    ("KickOff Yaba",     "Yaba",     "5 Tejuosho Road, Yaba"),
    ("KickOff Ikeja",    "Ikeja",    "78 Allen Avenue, Ikeja"),
    ("KickOff Surulere", "Surulere", "21 Adeniran Ogunsanya St, Surulere"),
]
PITCHES_PER_LOCATION = 3   # 4 × 3 = 12 pitches
TEAMS_TARGET         = 600
PLAYERS_TARGET       = 4_000
OPEN_HOUR, CLOSE_HOUR = 7, 23      # 07:00–23:00
DAYS_WINDOW          = 365 * 2      # 2-year window: 1 year back, 1 year forward

NG_FIRST = ["Tunde","Ade","Kunle","Bola","Danjuma","Chidi","Emeka","Femi",
            "Tobi","Seyi","Bayo","Tope","Yemi","Gbenga","Nnamdi","Uche",
            "Yakubu","Ifeanyi","Saheed","Kemi","Nike","Folake","Adaeze",
            "Chioma","Zainab","Aisha","Fatima","Joy","Grace","Maryam"]
NG_LAST  = ["Bello","Olawale","Adeyemi","Oyeleye","Ibrahim","Okafor","Nwosu",
            "Adesanya","Akinwale","Olawepo","Adebayo","Ojo","Oyetola","Sanusi",
            "Bashir","Okoro","Eze","Mohammed","Olawale","Idris","Okafor",
            "Ezekwesili","Abubakar","Okonkwo","Ogunleye","Adewale","Ehigiator"]

TEAM_PREFIXES = ["Lekki","Yaba","Ikeja","Surulere","Mainland","Island",
                 "Victoria","Festac","Apapa","Agege"]
TEAM_SUFFIXES = ["Lions FC","Strikers","United","Rovers","Athletic","FC",
                 "City","Warriors","Eagles","Galaxy"]

random.seed(20261107)  # deterministic: same data on every run

# ---------- connection ------------------------------------------------------
DSN = f"dbname='{DB_NAME}' user='{DB_USER}' host='{DB_HOST}' password='{DB_PW}'"

# ---------- helpers ---------------------------------------------------------
def daterange(start: date, end: date):
    d = start
    while d <= end:
        yield d
        d += timedelta(days=1)

def peak_period(dow: int, hour: int) -> str:
    """Match the rule in seed.sql: peak = 17:00–23:00 weekdays OR all day weekends."""
    if dow in (0, 6):
        return "peak"
    return "peak" if hour >= 17 else "off_peak"

def lagos_now() -> datetime:
    """Africa/Lagos is UTC+1, no DST."""
    return datetime.now(timezone.utc) + timedelta(hours=1)

# ---------- main ------------------------------------------------------------
def main() -> int:
    today = lagos_now().date()
    window_start = today - timedelta(days=DAYS_WINDOW // 2)
    window_end   = today + timedelta(days=DAYS_WINDOW // 2)

    conn = psycopg.connect(DSN)
    conn.autocommit = False
    cur = conn.cursor()

    # 0) wipe transactional data (locations, pitches, pricing, teams, players
    #    from seed.sql are kept; this script only regenerates bookings etc.).
    print("[0] Cleaning transactional data …")
    cur.execute("TRUNCATE match_result, payment, booking RESTART IDENTITY CASCADE;")
    # also wipe the seed team/player rows so we can re-insert a larger, realistic set
    cur.execute("TRUNCATE team_member, player, team, pitch, pricing, location RESTART IDENTITY CASCADE;")
    conn.commit()

    # 1) locations + pitches + pricing
    print("[1] Inserting 4 locations, 12 pitches, pricing grid …")
    pitch_ids: list[int] = []
    for (lname, area, addr) in LOCATIONS:
        cur.execute(
            "INSERT INTO location (name, area, address, opens_at, closes_at) "
            "VALUES (%s,%s,%s,'07:00','23:00') RETURNING location_id",
            (lname, area, addr))
        loc_id = cur.fetchone()[0]
        for k in range(PITCHES_PER_LOCATION):
            surfaces = ["artificial_turf","grass","indoor","concrete"]
            cur.execute(
                "INSERT INTO pitch (location_id, name, surface_type, capacity) "
                "VALUES (%s,%s,%s,10) RETURNING pitch_id",
                (loc_id, f"{area} Pitch {chr(ord('A')+k)}",
                 surfaces[k % len(surfaces)]))
            pitch_ids.append(cur.fetchone()[0])

    # pricing: 7 weekdays × 2 periods × 12 pitches = 168 rows
    pricing_rows = []
    for pid in pitch_ids:
        for dow in range(7):
            for period in ("peak","off_peak"):
                if period == "peak":
                    rate = 25000 if dow in (0,6) else 18000
                else:
                    rate = 9000
                pricing_rows.append((pid, dow, period, rate,
                                     window_start, window_end))
    cur.executemany(
        "INSERT INTO pricing (pitch_id, day_of_week, period, rate, valid_from, valid_to) "
        "VALUES (%s,%s,%s,%s,%s,%s)", pricing_rows)
    conn.commit()
    print(f"    pitches={len(pitch_ids)}  pricing_rows={len(pricing_rows)}")

    # 2) players + teams + team_members
    print(f"[2] Inserting {PLAYERS_TARGET} players, {TEAMS_TARGET} teams …")
    players: list[int] = []
    for i in range(PLAYERS_TARGET):
        cur.execute(
            "INSERT INTO player (first_name, last_name, phone, email, dob) "
            "VALUES (%s,%s,%s,%s,%s) RETURNING player_id",
            (random.choice(NG_FIRST), random.choice(NG_LAST),
             f"0802 {1000+i:07d}", f"player{i}@kickoff.ng",
             date(1990,1,1) + timedelta(days=random.randint(0, 12_000))))
        players.append(cur.fetchone()[0])

    teams: list[int] = []
    used_team_names = set()
    for i in range(TEAMS_TARGET):
        while True:
            nm = f"{random.choice(TEAM_PREFIXES)} {random.choice(TEAM_SUFFIXES)} {i+1}"
            if nm not in used_team_names:
                used_team_names.add(nm); break
        cur.execute(
            "INSERT INTO team (name, captain_name, phone, email, created_at) "
            "VALUES (%s,%s,%s,%s,%s) RETURNING team_id",
            (nm, random.choice(NG_FIRST)+" "+random.choice(NG_LAST),
             f"0803 {2000+i:07d}", f"captain{i}@kickoff.ng",
             datetime.utcnow() - timedelta(days=random.randint(30, 700))))
        teams.append(cur.fetchone()[0])
    conn.commit()

    # team members: every team gets 5–10 players, so it can book.
    print("[2b] Linking 5–10 players to each team …")
    member_rows = []
    for tid in teams:
        n = random.randint(5, 10)
        members = random.sample(players, n)
        for j, pid in enumerate(members):
            role = "captain" if j == 0 else ("vice_captain" if j == 1 else "player")
            member_rows.append((tid, pid, role,
                                date.today() - timedelta(days=random.randint(30, 700))))
    cur.executemany(
        "INSERT INTO team_member (team_id, player_id, role, joined_at) "
        "VALUES (%s,%s,%s,%s)", member_rows)
    conn.commit()
    print(f"    team_members={len(member_rows)}")

    # 3) Build a per-pitch slot occupancy set so we never produce overlaps.
    # Each occupied slot is (pitch_id, yyyy-mm-dd, start_hour). A 2-hour booking
    # starting at 09:00 occupies (9,10); a 3-hour booking starting at 21:00
    # occupies (21,22,23) and ends at 23:00 — within opening hours.
    print("[3] Generating bookings (target >= 50 000) …")
    occupied: dict[int, set[tuple[date, int]]] = {pid: set() for pid in pitch_ids}

    bookings_done = 0
    payment_rows: list[tuple] = []
    match_rows:   list[tuple] = []
    iterations    = 0
    MAX_ITER      = TARGET_BOOKINGS * 30

    while bookings_done < TARGET_BOOKINGS and iterations < MAX_ITER:
        iterations += 1
        pid  = random.choice(pitch_ids)
        d    = window_start + timedelta(days=random.randint(0, DAYS_WINDOW))
        sh   = random.randint(OPEN_HOUR, CLOSE_HOUR - 1)   # start hour
        dur  = random.randint(1, 3)
        # ensure booking ends at or before 23:00
        if sh + dur > CLOSE_HOUR:
            continue
        # build the set of hours this booking would occupy
        hours_needed = tuple((d, sh + k) for k in range(dur))
        if any(h in occupied[pid] for h in hours_needed):
            continue
        # claim the slots
        for h in hours_needed:
            occupied[pid].add(h)

        start_time = datetime(d.year, d.month, d.day, sh, 0, 0,
                              tzinfo=timezone(timedelta(hours=1)))
        team_id  = random.choice(teams)
        status   = random.choices(
            ["confirmed","cancelled","completed","no_show"],
            weights=[55, 5, 35, 5])[0]
        cur.execute(
            "INSERT INTO booking (pitch_id, team_id, start_time, duration_hours, status) "
            "VALUES (%s,%s,%s,%s,%s) RETURNING booking_id",
            (pid, team_id, start_time, dur, status))
        bid = cur.fetchone()[0]

        # payment: amount = peak × peak_hours + off_peak × off_peak_hours (NGN)
        dow = d.weekday()  # Mon=0…Sun=6; PostgreSQL EXTRACT(DOW) gives Sun=0…Sat=6
        pg_dow = (dow + 1) % 7
        peak_rate    = 25000 if pg_dow in (0,6) else 18000
        offpeak_rate = 9000
        amt = 0
        for h in range(sh, sh + dur):
            amt += peak_rate if peak_period(pg_dow, h) == "peak" else offpeak_rate
        # cancelled bookings: refund half; no_show: refund nothing (still pay deposit)
        if status == "cancelled":
            amt_pay = max(amt // 2, 1)
            pay_status = "refunded"
        else:
            amt_pay = amt
            pay_status = "succeeded"
        pay_method = random.choice(["card","transfer","wallet","cash"])
        payment_rows.append((bid, amt_pay, "NGN", pay_method, pay_status, start_time))

        # match_result for completed bookings only
        if status == "completed":
            # pick a home team = the booking team; away team another random team
            away = random.choice([t for t in teams if t != team_id]) if len(teams) > 1 else team_id
            hs = random.randint(0, 8); as_ = random.randint(0, 8)
            match_rows.append((bid, team_id, away, hs, as_, start_time))

        bookings_done += 1
        if bookings_done % 5_000 == 0:
            print(f"    … {bookings_done} bookings generated")
            conn.commit()  # commit periodically to avoid huge WAL

    # bulk-insert payments + match_results
    print("[3b] Inserting payments + match_results …")
    cur.executemany(
        "INSERT INTO payment (booking_id, amount, currency, method, status, paid_at) "
        "VALUES (%s,%s,%s,%s,%s,%s)", payment_rows)
    cur.executemany(
        "INSERT INTO match_result (booking_id, home_team_id, away_team_id, "
        "home_score, away_score, played_at) VALUES (%s,%s,%s,%s,%s,%s)",
        match_rows)
    conn.commit()
    print(f"[3c] bookings={bookings_done}  payments={len(payment_rows)}  "
          f"match_results={len(match_rows)}")

    # 4) final counts
    cur.execute("""SELECT
        (SELECT count(*) FROM location),
        (SELECT count(*) FROM pitch),
        (SELECT count(*) FROM team),
        (SELECT count(*) FROM player),
        (SELECT count(*) FROM team_member),
        (SELECT count(*) FROM pricing),
        (SELECT count(*) FROM booking),
        (SELECT count(*) FROM payment),
        (SELECT count(*) FROM match_result)""")
    locs, pits, tms, plys, mems, prc, bks, pays, mrs = cur.fetchone()
    print("==========================================================")
    print(f"  locations     = {locs}")
    print(f"  pitches       = {pits}")
    print(f"  teams         = {tms}")
    print(f"  players       = {plys}")
    print(f"  team_members  = {mems}")
    print(f"  pricing_rows  = {prc}")
    print(f"  bookings      = {bks}")
    print(f"  payments      = {pays}")
    print(f"  match_results = {mrs}")
    print("==========================================================")
    if bks < 50_000:
        print(f"WARNING: only {bks} bookings generated (< 50 000 target).", file=sys.stderr)
        return 1
    cur.close(); conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
