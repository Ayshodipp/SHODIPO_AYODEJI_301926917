#!/usr/bin/env bash
# =============================================================================
# setup.sh — Bootstrap PostgreSQL 16 + MongoDB 8 in GitHub Codespaces
# Course: MIT 8103 Advanced Database Systems (Miva Open University)
# Case study: KickOff Arena — 5-a-side football pitch booking (Lagos)
# Student: Ayodeji Shodipo · 2026/A/MIT/0725
# =============================================================================
#
# Run from the repo root in a GitHub Codespace terminal:
#
#     bash setup.sh
#
# What this script does:
#   1. Removes the broken /etc/apt/sources.list.d/yarn.list that breaks apt
#      update inside the default Codespaces Ubuntu image.
#   2. Installs PostgreSQL 16 and MongoDB 8 community server.
#   3. Initialises and starts both services.
#   4. Creates the `kickoff` PostgreSQL database and its superuser role.
#   5. Creates the `kickoff_mongo` MongoDB database and an application user.
#   6. Loads the PostgreSQL extensions needed by P1/P3/P5 (btree_gist, pgcrypto).
#
# IMPORTANT Codespaces rules respected by this script:
#   * The codespace user can sudo only as root. To act as the postgres OS user
#     we use `sudo runuser -u postgres -- ...`, NEVER `sudo -u postgres ...`.
#   * Ubuntu keeps PostgreSQL 16 config in /etc/postgresql/16/main/ ; the data
#     directory is /var/lib/postgresql/16/main/ ; pg_ctl is at
#     /usr/lib/postgresql/16/bin/pg_ctl.
#   * TCP logins need a password, so the scripts in this repo connect through
#     the Unix socket (host=/var/run/postgresql) — no password required.
#   * No use of postgres_fdw (forbidden by the CA brief).
# =============================================================================

set -euo pipefail

echo "============================================================"
echo "  KickOff Arena — DB environment bootstrap (Codespaces)"
echo "============================================================"

# 0. Fix the broken yarn source list that ships in the Codespaces image.
if [ -f /etc/apt/sources.list.d/yarn.list ]; then
  echo "[0] Removing /etc/apt/sources.list.d/yarn.list (breaks apt update)."
  sudo rm -f /etc/apt/sources.list.d/yarn.list
fi

# 1. Apt update + install prerequisites.
echo "[1] apt-get update + base packages"
sudo apt-get update -y || true
sudo apt-get install -y curl ca-certificates gnupg lsb-release wget \
                        python3 python3-pip

# 2. ---- PostgreSQL 16 ----
echo "[2] Installing PostgreSQL 16"
if ! command -v psql >/dev/null 2>&1; then
  # Import the PGDG signing key and repo. On Ubuntu 24.04 (noble) use noble.
  CODENAME="$(lsb_release -cs)"
  curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | \
    sudo gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] \
http://apt.postgresql.org/pub/repos/apt ${CODENAME}-pgdg main" | \
    sudo tee /etc/apt/sources.list.d/pgdg.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y postgresql-16 postgresql-client-16
else
  echo "    psql already present ($(psql --version)). Skipping install."
fi

# Start PostgreSQL 16 via the Ubuntu service wrapper (not pg_ctl directly).
echo "[2b] Starting PostgreSQL 16 cluster"
sudo pg_ctlcluster 16 main start 2>/dev/null || true
sudo pg_ctlcluster 16 main status || sudo pg_ctlcluster 16 main start

# Create role + database (idempotent). Connect via Unix socket as the postgres
# OS user — never over TCP, because that would prompt for a password.
echo "[2c] Creating PostgreSQL role 'kickoff' and database 'kickoff'"
if ! sudo runuser -u postgres -- psql -tAc \
     "SELECT 1 FROM pg_roles WHERE rolname='kickoff'" | grep -q 1; then
  sudo runuser -u postgres -- psql -c \
    "CREATE ROLE kickoff WITH LOGIN SUPERUSER PASSWORD 'kickoff_dev_pw';"
fi
if ! sudo runuser -u postgres -- psql -tAc \
     "SELECT 1 FROM pg_database WHERE datname='kickoff'" | grep -q 1; then
  sudo runuser -u postgres -- createdb -O kickoff kickoff
fi

# Allow the kickoff role over the Unix socket with a password (hba line goes at the TOP).
HBA=/etc/postgresql/16/main/pg_hba.conf
if ! sudo grep -q 'kickoff scram' "$HBA"; then
  sudo sed -i '1i local   all   kickoff   scram-sha-256   # kickoff scram' "$HBA"
  sudo pg_ctlcluster 16 main reload
fi
sudo runuser -u postgres -- psql -c "ALTER DATABASE kickoff SET timezone TO 'Africa/Lagos';" >/dev/null

# Extensions used by P1 (btree_gist for tstzrange exclusion constraint,
# pgcrypto for gen_random_uuid), P3 (pgcrypto), P5 (pgcrypto for replica key).
echo "[2d] Loading PostgreSQL extensions"
sudo runuser -u postgres -- psql -d kickoff <<'SQL'
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
SQL

# 3. ---- MongoDB 8 ----
echo "[3] Installing MongoDB 8 community server"
if ! command -v mongod >/dev/null 2>&1; then
  curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | \
    sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg
  CODENAME="$(lsb_release -cs)"
  echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] \
https://repo.mongodb.org/apt/ubuntu ${CODENAME}/mongodb-org/8.0 multiverse" | \
    sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y mongodb-org
else
  echo "    mongod already present ($(mongod --version | head -1)). Skipping install."
fi

echo "[3b] Starting MongoDB 8 via systemd (or direct fallback)"
if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q mongod; then
  sudo systemctl enable --now mongod 2>/dev/null || \
    sudo systemctl start mongod 2>/dev/null || true
fi
# Codespaces sometimes has no real systemd; fall back to a direct daemon.
if ! pgrep -x mongod >/dev/null 2>&1; then
  sudo mkdir -p /data/db /var/log/mongodb
  sudo chown -R mongodb:mongodb /data/db /var/log/mongodb 2>/dev/null || true
  sudo runuser -u mongodb -- mongod --fork --logpath /var/log/mongodb/mongod.log \
              --dbpath /data/db --bind_ip 127.0.0.1 || \
  sudo mongod --fork --logpath /var/log/mongodb/mongod.log \
              --dbpath /data/db --bind_ip 127.0.0.1
fi

# Wait for MongoDB to be reachable.
echo "[3c] Waiting for MongoDB to be ready on 127.0.0.1:27017"
for i in $(seq 1 30); do
  if mongosh --quiet --eval "db.runCommand({ping:1}).ok" 2>/dev/null | grep -q 1; then
    echo "    MongoDB is up."
    break
  fi
  sleep 1
done

# Create the MongoDB application database + a non-root user (idempotent).
echo "[3d] Creating MongoDB database 'kickoff_mongo' + user 'kickoff_user'"
mongosh --quiet <<'JS' || true
db = db.getSiblingDB("kickoff_mongo");
if (!db.getUser("kickoff_user")) {
  db.createUser({
    roles: [{ role: "readWrite", db: "kickoff_mongo" }],
    pwd: "kickoff_dev_pw",
    user: "kickoff_user"
  });
}
JS

# 3e. Python drivers (psycopg v3 + pymongo) - fallback chain, then verify.
echo "[3e] Installing Python drivers"
for PKG in "psycopg[binary]" pymongo; do
  pip3 install -q "$PKG" 2>/dev/null || pip3 install -q --user "$PKG" 2>/dev/null || \
  pip3 install -q --break-system-packages "$PKG" 2>/dev/null || \
  pip3 install -q --user --break-system-packages "$PKG"
done
python3 -c 'import psycopg, pymongo; print("    python drivers OK")'

# 4. Sanity checks.
echo "============================================================"
echo "  Sanity checks"
echo "============================================================"
echo "[PostgreSQL]"
sudo runuser -u postgres -- psql -d kickoff -c \
  "SELECT version();"
sudo runuser -u postgres -- psql -d kickoff -c \
  "SELECT extname FROM pg_extension ORDER BY extname;"

echo "[MongoDB]"
mongosh --quiet --eval "db.runCommand({buildInfo:1}).version"
mongosh --quiet kickoff_mongo --eval "db.getCollectionNames()"

echo "============================================================"
echo "  Bootstrap complete."
echo "  PostgreSQL  : host=/var/run/postgresql  db=kickoff  user=kickoff"
echo "                (connect with:  PGPASSWORD=kickoff_dev_pw psql -h /var/run/postgresql -U kickoff kickoff)"
echo "  MongoDB     : mongodb://127.0.0.1:27017/kickoff_mongo"
echo "============================================================"
