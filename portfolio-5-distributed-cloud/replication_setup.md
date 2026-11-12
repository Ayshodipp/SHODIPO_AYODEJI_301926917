# Replication Setup — Primary + Streaming Read Replica (Codespaces)

**Portfolio 5 · MIT 8103 · Ayodeji Shodipo · 2026/A/MIT/0725**

This guide builds a physical streaming-replication pair **inside a single
Codespace**: one PostgreSQL 16 cluster acts as the primary, a second cluster
on a different port + data directory acts as a hot-standby read-only replica.
We then demonstrate:

1. The primary accepts a write.
2. The replica **rejects** a write with `cannot execute INSERT in a read-only
   transaction`.
3. The new row **arrives on the replica** via streaming replication, after
   a short catch-up delay.

The Codespaces rules are respected throughout: the codespace user can sudo
only as root, so every `postgres`-OS-user command is run with
`sudo runuser -u postgres -- …`; the secondary cluster gets its own
`postgresql.conf` (as required, because `pg_basebackup` does not copy it);
all `psql` connections go through Unix sockets or `127.0.0.1:port` with a
password.

---

## Step 0 — Pre-flight

Run `bash setup.sh` first (it installs PostgreSQL 16 and creates the
`kickoff` database). Then make sure P1 has been applied so the primary has
something to replicate:

```bash
bash portfolio-1-database-design/run_p1.sh   # if you haven't already
sudo runuser -u postgres -- psql -d kickoff -c "SELECT count(*) FROM booking;"
```

## Step 1 — Create a replication role on the primary

```bash
sudo runuser -u postgres -- psql -d kickoff <<'SQL'
CREATE ROLE repl WITH REPLICATION LOGIN PASSWORD 'repl_pw';
SQL
```

## Step 2 — Configure the primary for streaming replication

Edit the primary's `postgresql.conf` (Ubuntu path:

`/etc/postgresql/16/main/postgresql.conf`) — we will do it via
`sudo runuser` to keep the file ownership correct.

```bash
# Set the WAL level to replica (default in PG16, but make it explicit)
sudo sed -i "s/^#*wal_level.*/wal_level = replica/" /etc/postgresql/16/main/postgresql.conf
# Allow standby connections
sudo sed -i "s/^#*max_wal_senders.*/max_wal_senders = 10/" /etc/postgresql/16/main/postgresql.conf
sudo sed -i "s/^#*max_replication_slots.*/max_replication_slots = 10/" /etc/postgresql/16/main/postgresql.conf
# Force sync commit OFF so the demo is faster (still safe — sync_commit only
# controls when the COMMIT acknowledgement is sent, not correctness)
sudo sed -i "s/^#*synchronous_commit.*/synchronous_commit = on/" /etc/postgresql/16/main/postgresql.conf

# Allow the repl role to connect locally in pg_hba.conf
echo "host  replication  repl  127.0.0.1/32  md5" | \
  sudo tee -a /etc/postgresql/16/main/pg_hba.conf

# Restart the primary so the changes take effect
sudo pg_ctlcluster 16 main restart
```

## Step 3 — Take a base backup of the primary into a new data directory

The primary's data lives in `/var/lib/postgresql/16/main`. We will put the
replica's data in `/var/lib/postgresql/16/standby`. `pg_basebackup` does
**not** copy `postgresql.conf` (it lives in `/etc`, not in the data dir), so
we will give the standby its own config afterwards (as the Codespaces rules
require).

```bash
# Stop the primary cluster briefly so the base backup is consistent.
sudo pg_ctlcluster 16 main stop

# Wipe any previous standby data dir
sudo rm -rf /var/lib/postgresql/16/standby
sudo mkdir -p /var/lib/postgresql/16/standby
sudo chown postgres:postgres /var/lib/postgresql/16/standby
sudo chmod 700 /var/lib/postgresql/16/standby

# Start the primary again
sudo pg_ctlcluster 16 main start

# Take the base backup as the postgres OS user.
# We connect with host=127.0.0.1 because pg_basebackup uses a TCP replication
# connection (we already added the pg_hba.conf line above).
sudo runuser -u postgres -- /usr/lib/postgresql/16/bin/pg_basebackup \
  -h 127.0.0.1 -p 5432 -U repl -D /var/lib/postgresql/16/standby \
  -X stream -S standby_slot -c fast -P -R
# The -R flag writes standby.signal + primary_conninfo into the data dir,
# which is what tells PostgreSQL 16 that this cluster is a standby.
```

(`-S standby_slot` creates a replication slot named `standby_slot` so the
primary holds onto WAL until the replica has consumed it. Replication slots
prevent the primary from recycling WAL the replica has not yet received —
important when the replica is offline for a while.)

## Step 4 — Give the standby its own postgresql.conf

`pg_basebackup` does not copy the primary's `postgresql.conf`, so we create
one for the standby. We will run it on port **5433** so it does not clash
with the primary on 5432.

```bash
sudo mkdir -p /etc/postgresql/16/standby
sudo tee /etc/postgresql/16/standby/postgresql.conf >/dev/null <<'CONF'
# Standby configuration (Portfolio 5, MIT 8103)
data_directory = '/var/lib/postgresql/16/standby'
hba_file       = '/etc/postgresql/16/standby/pg_hba.conf'
ident_file     = '/etc/postgresql/16/standby/pg_ident.conf'
external_pid_file = '/var/run/postgresql/16-standby.pid'

port = 5433
listen_addresses = '127.0.0.1'

# Hot standby = allow read-only queries during recovery
hot_standby = on

# Where to log
logging_collector = off
log_directory = 'log'
log_filename = 'postgresql-standby-%Y-%m-%d.log'
log_min_messages = info

# Connect back to the primary
# (this is also written by pg_basebackup -R into postgresql.auto.conf,
#  but we set it explicitly here so it survives a re-basebackup)
primary_conninfo = 'host=127.0.0.1 port=5432 user=repl password=repl_pw dbname=postgres application_name=standby1'

# Replication slot (created by pg_basebackup -S standby_slot)
primary_slot_name = 'standby_slot'

# Misc
unix_socket_directories = '/var/run/postgresql'
shared_buffers = 128MB
CONF

# Copy pg_hba.conf + pg_ident.conf into the standby's config dir.
sudo cp /etc/postgresql/16/main/pg_hba.conf  /etc/postgresql/16/standby/pg_hba.conf
sudo cp /etc/postgresql/16/main/pg_ident.conf /etc/postgresql/16/standby/pg_ident.conf

# Remove the auto-generated config from pg_basebackup so OURS wins.
sudo rm -f /var/lib/postgresql/16/standby/postgresql.auto.conf
```

## Step 5 — Start the standby cluster with `pg_ctl` directly

The Ubuntu `pg_ctlcluster` wrapper only manages clusters registered with it,
so for the standby we use `pg_ctl` directly (it lives at
`/usr/lib/postgresql/16/bin/pg_ctl`, exactly as the Codespaces rules
require).

```bash
sudo runuser -u postgres -- /usr/lib/postgresql/16/bin/pg_ctl \
  -D /var/lib/postgresql/16/standby \
  -o "-c config_file=/etc/postgresql/16/standby/postgresql.conf" \
  -l /var/lib/postgresql/16/standby/startup.log \
  start
```

Wait a few seconds and check that streaming replication is up:

```bash
sudo runuser -u postgres -- psql -d kickoff -c \
  "SELECT application_name, state, sync_state, sent_lsn, write_lsn, flush_lsn, replay_lsn
     FROM pg_stat_replication;"
```

You should see a row with `application_name = standby1` and `state =
streaming`.

## Step 6 — Demonstrate: replica rejects writes, primary accepts them

Open **two** terminals:

### Terminal A — write to the PRIMARY (port 5432)

```bash
sudo runuser -u postgres -- psql -p 5432 -d kickoff
```

```sql
-- primary
SELECT pg_is_in_recovery();    -- returns false
INSERT INTO location (name, area, address, opens_at, closes_at)
VALUES ('KickOff Test Replica', 'Ikeja', 'Demo address', '07:00', '23:00')
RETURNING location_id;
-- succeeds → row visible on the primary
```

### Terminal B — try to write to the REPLICA (port 5433)

```bash
# TCP needs a password — we set repl_pw above. The student uses the kickoff
# role here instead.
PGPASSWORD=kickoff_dev_pw psql -h 127.0.0.1 -p 5433 -U kickoff kickoff
```

```sql
-- replica
SELECT pg_is_in_recovery();    -- returns true
INSERT INTO location (name, area, address, opens_at, closes_at)
VALUES ('Should be rejected', 'Ikeja', 'Demo', '07:00', '23:00');
-- ERROR: cannot execute INSERT in a read-only transaction
```

**Screenshot to capture:** the `cannot execute INSERT in a read-only
transaction` error on Terminal B.

## Step 7 — Demonstrate: the new row arrives on the replica

After Terminal A's `INSERT … COMMIT`, the replica streams the WAL and
applies it. Wait a moment and read from the replica:

```sql
-- replica (Terminal B)
SELECT location_id, name, area FROM location WHERE name = 'KickOff Test Replica';
-- returns the row that was just inserted on the primary, proving that
-- streaming replication has caught up.
```

For an extra check, watch the WAL lag shrink on the primary:

```sql
-- primary (Terminal A)
SELECT application_name,
       pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS bytes_lag
  FROM pg_stat_replication;
-- bytes_lag should be near 0 (a few hundred bytes is fine).
```

## Step 8 — Cleanup (optional, before re-running)

```bash
# Stop the standby
sudo runuser -u postgres -- /usr/lib/postgresql/16/bin/pg_ctl \
  -D /var/lib/postgresql/16/standby stop -m fast

# Drop the replication slot on the primary so it stops holding WAL
sudo runuser -u postgres -- psql -d kickoff -c \
  "SELECT pg_drop_replication_slot('standby_slot');"

# Wipe the standby data dir for next run
sudo rm -rf /var/lib/postgresql/16/standby /etc/postgresql/16/standby

# Optional: drop the demo row
sudo runuser -u postgres -- psql -d kickoff -c \
  "DELETE FROM location WHERE name = 'KickOff Test Replica';"
```

---

## Sync vs async trade-off (links to Study Session 2)

In the demo above we left `synchronous_commit = on` on the primary, which
makes the COMMIT acknowledgement wait for the WAL to be flushed **locally**.
That is **asynchronous replication** as far as the replica is concerned:
the COMMIT returns to the client before the replica has applied the change.
This is the right call for KickOff Arena:

- **Async replication** (the default): low write latency, but if the primary
  crashes after COMMIT and before the replica has applied the change, the
  change is lost. Acceptable for match reports and pitch bookings because
  the booking system can re-create a missing booking from the payment
  gateway's audit log.

- **Sync replication** (set `synchronous_standby_names = 'standby1'` on the
  primary): the COMMIT waits for the replica to confirm write/flush. No data
  is lost on primary crash, but every write now takes at least one round
  trip to the replica, which adds latency. We would enable this only for
  the `payment` table — the booking row can be regenerated, a payment
  confirmation cannot.

The choice is a textbook CAP trade-off (Study Session 2): KickOff Arena
places `payment` in **CP** (synchronous replication = consistency over
availability) and the bulk of `booking` data in **AP** (async replication =
availability over consistency, accepting the tiny risk of losing a
just-committed booking in a primary crash).
