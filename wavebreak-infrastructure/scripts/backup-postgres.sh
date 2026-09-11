#!/usr/bin/env sh
set -eu

: "${WAVEBREAK_DATABASE_URL:?WAVEBREAK_DATABASE_URL is required}"
BACKUP_DIR="${WAVEBREAK_BACKUP_DIR:-./backups}"
RETENTION_DAYS="${WAVEBREAK_BACKUP_RETENTION_DAYS:-14}"
ENCRYPTION_RECIPIENT="${WAVEBREAK_BACKUP_AGE_RECIPIENT:-}"

mkdir -p "$BACKUP_DIR"
timestamp="$(date -u +%Y%m%d%H%M%S)"
target="$BACKUP_DIR/wavebreak-postgres-$timestamp.dump.gz"

pg_dump "$WAVEBREAK_DATABASE_URL" --format=custom | gzip -9 > "$target"

if [ -n "$ENCRYPTION_RECIPIENT" ]; then
    age -r "$ENCRYPTION_RECIPIENT" -o "$target.age" "$target"
    rm -f "$target"
    target="$target.age"
fi

find "$BACKUP_DIR" -type f -name 'wavebreak-postgres-*' -mtime +"$RETENTION_DAYS" -delete
printf '%s\n' "$target"
