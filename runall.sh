#!/usr/bin/env bash
# runall.sh - runs portfolios 1-5 in order, saves a log for each, commits + pushes each.
# Usage (from the repo folder in your Codespace terminal):   bash runall.sh
# Resume from portfolio 3:                                    bash runall.sh 3
set -uo pipefail
START="${1:-1}"
cd "$(dirname "$(readlink -f "$0")")"
REPO="$PWD"
export PGPASSWORD=kickoff_dev_pw

# 1. Find the kit (re-unzip the FIXED zip if the Codespace lost ~/kit)
KIT="$HOME/kit/advanced-database-portfolio"
if [ ! -d "$KIT/portfolio-1-database-design" ]; then
  Z="$(ls "$REPO"/*FIXED*.zip 2>/dev/null | head -1)"
  [ -z "$Z" ] && { echo "!!! kit not found and no *FIXED*.zip in $REPO - drag the zip in again"; exit 1; }
  mkdir -p "$HOME/kit" && unzip -qo "$Z" -d "$HOME/kit"
fi
cp -f "$KIT/collect_results.sh" "$KIT/setup.sh" "$REPO/" 2>/dev/null || true

# 2. Start PostgreSQL and MongoDB (a sleeping Codespace stops them)
sudo pg_ctlcluster 16 main start 2>/dev/null || true
if ! pgrep -x mongod >/dev/null 2>&1; then
  sudo mkdir -p /data/db /var/log/mongodb
  sudo chown -R mongodb:mongodb /data/db /var/log/mongodb 2>/dev/null || true
  sudo runuser -u mongodb -- mongod --dbpath /data/db --logpath /var/log/mongodb/mongod.log --bind_ip 127.0.0.1 --fork >/dev/null 2>&1 \
   || sudo mongod --dbpath /data/db --logpath /var/log/mongodb/mongod.log --bind_ip 127.0.0.1 --fork >/dev/null 2>&1 || true
fi
for i in $(seq 1 20); do mongosh --quiet --eval "db.runCommand({ping:1}).ok" 2>/dev/null | grep -q 1 && break; sleep 1; done

# 3. Re-run setup if the database is missing
if ! psql -h /var/run/postgresql -U kickoff kickoff -c 'SELECT 1' >/dev/null 2>&1; then
  echo ">>> database missing - running setup.sh first"
  bash "$KIT/setup.sh" 2>&1 | tee "$REPO/setup_output.log" || { echo "!!! SETUP FAILED - send Joseph setup_output.log"; exit 1; }
fi

# 4. Python drivers (fallback chain), then verify
python3 -c 'import psycopg, pymongo' 2>/dev/null || {
  for PKG in "psycopg[binary]" pymongo; do
    pip3 install -q "$PKG" 2>/dev/null || pip3 install -q --user "$PKG" 2>/dev/null || \
    pip3 install -q --break-system-packages "$PKG" 2>/dev/null || pip3 install -q --user --break-system-packages "$PKG" 2>/dev/null
  done
  python3 -c 'import psycopg, pymongo' || { echo "!!! python drivers missing - send Joseph this message"; exit 1; }
}

# 5. Run each portfolio
for N in 1 2 3 4 5; do
  [ "$N" -lt "$START" ] && continue
  case "$N" in
    1) D=portfolio-1-database-design;        S=run_p1.sh ;;
    2) D=portfolio-2-query-optimisation;     S=run_p2.sh ;;
    3) D=portfolio-3-transactions-concurrency; S=run_p3.sh ;;
    4) D=portfolio-4-nosql;                  S=run_p4.sh ;;
    5) D=portfolio-5-distributed-cloud;      S=run_p5.sh ;;
  esac
  echo; echo "################ PORTFOLIO $N ################"
  rm -rf "$REPO/$D"; cp -r "$KIT/$D" "$REPO/$D"
  bash "$REPO/$D/$S" 2>&1 | tee "$REPO/$D/p${N}_output.log"
  RC="${PIPESTATUS[0]}"
  if [ "$RC" -ne 0 ]; then echo "!!! P$N FAILED - send Joseph $D/p${N}_output.log"; exit 1; fi
  git add "$D" && git commit -q -m "P$N: run output and results" && echo "committed P$N"
  git push -q 2>/dev/null && echo "pushed P$N" || echo "(push skipped - run: git push)"
done

# 6. Collect results
bash collect_results.sh
git add my_results.txt collect_results.sh 2>/dev/null; git commit -q -m "Collected results" 2>/dev/null; git push -q 2>/dev/null || true
command -v code >/dev/null 2>&1 && code my_results.txt
echo "ALL DONE - open my_results.txt, press Ctrl+A, Ctrl+C and paste it to Joseph."
