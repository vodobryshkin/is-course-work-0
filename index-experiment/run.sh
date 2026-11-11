#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
mkdir -p results

docker compose up -d --build --wait
echo 'Заполняем тестовую БД...'
docker compose exec -T db psql -U postgres -d goalissimo_test -v ON_ERROR_STOP=1 \
  -f /lab/01_schema.sql -f /lab/02_fill.sql -f /lab/03_routines.sql \
  -c 'SELECT validate_tournament_personnel(tournament_id) FROM tournaments;' \
  -c 'VACUUM ANALYZE;' > results/load.txt

docker compose exec -T db psql -U postgres -d goalissimo_test -v ON_ERROR_STOP=1 \
  -f /lab/04_hypopg.sql > results/hypopg.txt

bench() {
  docker compose exec -T -e LC_ALL=C db pgbench -U postgres -n -c 4 -j 2 \
    --random-seed=42 -f /lab/bench/schedule.sql -f /lab/bench/events.sql \
    -f /lab/bench/player.sql -f /lab/bench/statistics.sql "$@" goalissimo_test
}

echo 'Замер без дополнительных индексов...'
docker compose exec -T db psql -U postgres -d goalissimo_test -v ON_ERROR_STOP=1 \
  -f /lab/05_explain.sql > results/explain_before.txt
bench -T 5 > /dev/null 2>&1
bench -T 30 -r > results/before.txt 2>&1

docker compose exec -T db psql -U postgres -d goalissimo_test -v ON_ERROR_STOP=1 \
  -f /lab/final_indexes.sql > results/indexes.txt

echo 'Замер с индексами...'
docker compose exec -T db psql -U postgres -d goalissimo_test -v ON_ERROR_STOP=1 \
  -f /lab/05_explain.sql > results/explain_after.txt
bench -T 5 > /dev/null 2>&1
bench -T 30 -r > results/after.txt 2>&1

docker compose exec -T db psql -U postgres -d goalissimo_test \
  -c "SELECT indexrelname, pg_size_pretty(pg_relation_size(indexrelid)) AS size
      FROM pg_stat_user_indexes WHERE indexrelname LIKE 'idx_%';" > results/sizes.txt
docker compose stop db
echo 'Готово. Сравни results/before.txt и results/after.txt.'
