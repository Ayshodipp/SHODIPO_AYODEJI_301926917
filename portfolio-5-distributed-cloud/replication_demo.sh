#!/usr/bin/env bash
# replication_demo.sh - one-script primary + hot-standby demo (same machine, port 5433).
# Streaming replication via pg_basebackup. Everything printed is real output.
set -euo pipefail
R=/var/lib/postgresql/16/replica
PGBIN=/usr/lib/postgresql/16/bin
AS_PG="sudo runuser -u postgres --"
P="$AS_PG psql -X -At -h /var/run/postgresql -p 5432 -d kickoff"
S="$AS_PG psql -X -At -h /var/run/postgresql -p 5433 -d kickoff"

echo "=== Setting up the replica (stop old one, base backup, config) ==="
$AS_PG $PGBIN/pg_ctl -D $R stop -m fast >/dev/null 2>&1 || true
sudo rm -rf $R
$AS_PG $PGBIN/pg_basebackup -h /var/run/postgresql -p 5432 -D $R -R -X stream -c fast
# Ubuntu keeps config in /etc, so the backup has no postgresql.conf: write a minimal one.
sudo cp /etc/postgresql/16/main/pg_hba.conf /etc/postgresql/16/main/pg_ident.conf $R/
sudo tee $R/postgresql.conf >/dev/null <<CONF
port = 5433
hba_file = '$R/pg_hba.conf'
ident_file = '$R/pg_ident.conf'
unix_socket_directories = '/var/run/postgresql'
listen_addresses = ''
hot_standby = on
max_connections = 100
CONF
sudo chown -R postgres:postgres $R
sudo chmod 700 $R
$AS_PG $PGBIN/pg_ctl -D $R -l /tmp/replica.log -w start >/dev/null
echo "replica started on port 5433"

echo; echo "=== 1. Who is who (pg_is_in_recovery: f = primary, t = replica) ==="
echo "primary port $($P -c "SELECT current_setting('port')") in_recovery = $($P -c 'SELECT pg_is_in_recovery()')"
echo "replica port $($S -c "SELECT current_setting('port')") in_recovery = $($S -c 'SELECT pg_is_in_recovery()')"

echo; echo "=== 2. Write on the REPLICA must be rejected ==="
$S -c "CREATE TABLE repl_demo(id int)" 2>&1 || true

echo; echo "=== 3. Insert on the PRIMARY, then read it on the REPLICA ==="
$P -c "DROP TABLE IF EXISTS repl_demo; CREATE TABLE repl_demo(id serial PRIMARY KEY, note text, created timestamptz DEFAULT now()); INSERT INTO repl_demo(note) VALUES ('written on primary at '||now()::text);" >/dev/null
sleep 2
echo "row seen on replica: $($S -c 'SELECT note FROM repl_demo')"

echo; echo "=== 4. Replication lag and sender status ==="
echo "replica replay lag: $($S -c "SELECT coalesce(now() - pg_last_xact_replay_timestamp(), interval '0')")"
$P -c "SELECT 'pg_stat_replication: state='||state||', sync_state='||sync_state||', replay_lag='||coalesce(replay_lag::text,'0') FROM pg_stat_replication"
echo "replica row count booking = $($S -c 'SELECT count(*) FROM booking')  (primary = $($P -c 'SELECT count(*) FROM booking'))"

echo; echo "=== Cleaning up the replica ==="
$AS_PG $PGBIN/pg_ctl -D $R stop -m fast >/dev/null
$P -c "DROP TABLE IF EXISTS repl_demo" >/dev/null
sudo rm -rf $R
echo "Replication demo finished."
