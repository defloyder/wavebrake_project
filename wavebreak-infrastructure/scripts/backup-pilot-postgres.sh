#!/usr/bin/env sh
set -eu
umask 077

COMPOSE_DIR="${WAVEBREAK_COMPOSE_DIR:-/home/wavebreakdeploy/wavebreak-pilot/current/wavebreak-infrastructure}"
BACKUP_DIR="${WAVEBREAK_BACKUP_DIR:-/home/wavebreakdeploy/wavebreak-pilot/shared/backups}"
RETENTION_DAYS="${WAVEBREAK_BACKUP_RETENTION_DAYS:-14}"
POSTGRES_CONTAINER="${WAVEBREAK_POSTGRES_CONTAINER:-wavebreak_pilot-postgres-1}"

mkdir -p "$BACKUP_DIR"
timestamp="$(date -u +%Y%m%d%H%M%S)"
target="$BACKUP_DIR/wavebreak-postgres-$timestamp.dump.gz"
partial="$target.partial"

cleanup() {
    rm -f "$partial"
}
trap cleanup EXIT HUP INT TERM

cd "$COMPOSE_DIR"
docker exec "$POSTGRES_CONTAINER" sh -eu -c \
    'pg_dump --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --format=custom' \
    | gzip -9 > "$partial"

gzip -t "$partial"
test -s "$partial"
mv "$partial" "$target"
find "$BACKUP_DIR" -type f -name 'wavebreak-postgres-*.dump.gz' -mtime +"$RETENTION_DAYS" -delete

printf '%s\n' "$target"
