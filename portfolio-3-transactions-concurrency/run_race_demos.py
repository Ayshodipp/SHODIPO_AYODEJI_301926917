#!/usr/bin/env python3
"""run_race_demos.py - Portfolio 3 concurrency demos, all in ONE run.
Two real PostgreSQL sessions (threads) race each other; every line printed is
real output from this run. Needs: pip install "psycopg[binary]". Run after P1.
Parts: 1 race bug | 2 exclusion constraint on the real booking table |
3 SELECT ... FOR UPDATE | 4 SERIALIZABLE | 5 READ COMMITTED vs REPEATABLE READ | 6 deadlock
"""
import threading, time, psycopg
from psycopg import errors

DSN = "dbname=kickoff user=kickoff host=/var/run/postgresql password=kickoff_dev_pw"
def conn(iso=None):
    c = psycopg.connect(DSN, autocommit=False)
    c.execute("SET TIME ZONE 'Africa/Lagos'")
    if iso: c.execute(f"SET TRANSACTION ISOLATION LEVEL {iso}")
    return c
def say(*a): print(*a, flush=True)
def hdr(t): say(f"\n=== {t} ===")

adm = psycopg.connect(DSN, autocommit=True)
adm.execute("""DROP TABLE IF EXISTS p3_slot; DROP TABLE IF EXISTS p3_price; DROP TABLE IF EXISTS p3_acct;
CREATE TABLE p3_slot(pitch int, slot int, team text);
CREATE TABLE p3_price(id int PRIMARY KEY, rate int);
CREATE TABLE p3_acct(id int PRIMARY KEY, bal int);
INSERT INTO p3_price VALUES (1, 9000);
INSERT INTO p3_acct VALUES (1,100),(2,100);""")

def race(worker_a, worker_b):
    bar = threading.Barrier(2); out = {}
    def run(name, fn):
        try: out[name] = fn(bar)
        except Exception as e: out[name] = f"{type(e).__name__}: {str(e).splitlines()[0]}"
    ts = [threading.Thread(target=run, args=(n, f)) for n, f in (("A", worker_a), ("B", worker_b))]
    [t.start() for t in ts]; [t.join(30) for t in ts]
    return out

# ---- Part 1: the bug -------------------------------------------------------
hdr("PART 1 - THE BUG: check-then-insert with no protection (both sessions want pitch 1, slot 10)")
def naive(team):
    def f(bar):
        c = conn(); free = c.execute("SELECT count(*) FROM p3_slot WHERE pitch=1 AND slot=10").fetchone()[0] == 0
        say(f"  team {team}: slot looks free = {free}"); bar.wait()
        if free: c.execute("INSERT INTO p3_slot VALUES (1,10,%s)", (team,)); c.commit(); return "inserted"
        c.rollback(); return "refused"
    return f
say("  results:", race(naive("A"), naive("B")))
n = adm.execute("SELECT count(*) FROM p3_slot WHERE pitch=1 AND slot=10").fetchone()[0]
say(f"  rows for the same slot: {n}  -> {'DOUBLE BOOKING (bug reproduced)' if n > 1 else 'no double booking this time'}")

# ---- Part 2: exclusion constraint on the real booking table ---------------
hdr("PART 2 - FIX 1: booking_no_overlap EXCLUDE constraint on the real booking table")
adm.execute("DELETE FROM booking WHERE pitch_id=(SELECT pitch_id FROM pitch WHERE name='P3 Demo Pitch') AND start_time >= CURRENT_DATE + 20")
ids = adm.execute("SELECT (SELECT pitch_id FROM pitch WHERE name='P3 Demo Pitch'), (SELECT team_id FROM team WHERE name='P3 Demo Team')").fetchone()
def real(team_label):
    def f(bar):
        c = conn(); free = c.execute("""SELECT count(*) FROM booking WHERE pitch_id=%s AND status='confirmed'
              AND time_range && tstzrange(((CURRENT_DATE+20)+TIME '15:00') AT TIME ZONE 'Africa/Lagos', ((CURRENT_DATE+20)+TIME '16:00') AT TIME ZONE 'Africa/Lagos')""", (ids[0],)).fetchone()[0] == 0
        say(f"  session {team_label}: slot looks free = {free}"); bar.wait()
        c.execute("INSERT INTO booking(pitch_id,team_id,start_time,duration_hours) VALUES (%s,%s,((CURRENT_DATE+20)+TIME '15:00') AT TIME ZONE 'Africa/Lagos',1)", (ids[0], ids[1]))
        c.commit(); return "booking inserted"
    return f
say("  results:", race(real("A"), real("B")))
say("  confirmed bookings for that slot:", adm.execute("SELECT count(*) FROM booking WHERE pitch_id=%s AND start_time >= CURRENT_DATE+20", (ids[0],)).fetchone()[0], "(must be 1)")

# ---- Part 3: FOR UPDATE ----------------------------------------------------
hdr("PART 3 - FIX 2: SELECT ... FOR UPDATE on a lock row, then check, then insert")
adm.execute("DELETE FROM p3_slot; DROP TABLE IF EXISTS p3_lock; CREATE TABLE p3_lock(pitch int PRIMARY KEY); INSERT INTO p3_lock VALUES (1);")
def locked(team, delay):
    def f(bar):
        c = conn(); bar.wait(); time.sleep(delay)
        c.execute("SELECT * FROM p3_lock WHERE pitch=1 FOR UPDATE")
        say(f"  team {team}: got the lock")
        free = c.execute("SELECT count(*) FROM p3_slot WHERE pitch=1 AND slot=10").fetchone()[0] == 0
        time.sleep(1.0 if team == "A" else 0)
        if free: c.execute("INSERT INTO p3_slot VALUES (1,10,%s)", (team,)); c.commit(); return "inserted"
        c.rollback(); return "refused (slot already taken - the second session saw the first one's row)"
    return f
say("  results:", race(locked("A", 0), locked("B", 0.3)))
say("  rows for the slot:", adm.execute("SELECT count(*) FROM p3_slot WHERE pitch=1 AND slot=10").fetchone()[0], "(must be 1)")

# ---- Part 4: SERIALIZABLE --------------------------------------------------
hdr("PART 4 - FIX 3: SERIALIZABLE isolation (one session is aborted with 'could not serialize')")
adm.execute("DELETE FROM p3_slot")
def ser(team):
    def f(bar):
        c = conn("SERIALIZABLE"); free = c.execute("SELECT count(*) FROM p3_slot WHERE pitch=1 AND slot=10").fetchone()[0] == 0
        bar.wait()
        if free: c.execute("INSERT INTO p3_slot VALUES (1,10,%s)", (team,))
        c.commit(); return "committed"
    return f
say("  results:", race(ser("A"), ser("B")))
say("  rows for the slot:", adm.execute("SELECT count(*) FROM p3_slot WHERE pitch=1 AND slot=10").fetchone()[0], "(must be 1)")

# ---- Part 5: isolation levels ---------------------------------------------
hdr("PART 5 - READ COMMITTED vs REPEATABLE READ (price read twice while another session updates it)")
for iso in ("READ COMMITTED", "REPEATABLE READ"):
    adm.execute("UPDATE p3_price SET rate = 9000 WHERE id = 1")
    r = conn(iso); first = r.execute("SELECT rate FROM p3_price WHERE id=1").fetchone()[0]
    w = conn(); w.execute("UPDATE p3_price SET rate = 12000 WHERE id=1"); w.commit()
    second = r.execute("SELECT rate FROM p3_price WHERE id=1").fetchone()[0]; r.rollback()
    say(f"  {iso:16}: first read {first}, other session sets 12000 and commits, second read {second}  -> {'non-repeatable read' if first != second else 'repeatable'}")

# ---- Part 6: deadlock ------------------------------------------------------
hdr("PART 6 - DEADLOCK: two transfers lock accounts in opposite order")
def xfer(first, second):
    def f(bar):
        c = conn(); c.execute("UPDATE p3_acct SET bal=bal-1 WHERE id=%s", (first,)); bar.wait(); time.sleep(0.3)
        try:
            c.execute("UPDATE p3_acct SET bal=bal+1 WHERE id=%s", (second,)); c.commit(); return "committed"
        except errors.DeadlockDetected as e:
            c.rollback(); return "ABORTED by PostgreSQL: " + str(e).splitlines()[0]
    return f
say("  results:", race(xfer(1, 2), xfer(2, 1)))
say("  fix = always lock in the same order (lowest id first); balances now:", adm.execute("SELECT id, bal FROM p3_acct ORDER BY id").fetchall())
say("\nDone. All lines above are real output from this run.")
