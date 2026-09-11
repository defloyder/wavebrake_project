#!/usr/bin/env sh
set -eu

: "${WAVEBREAK_DATABASE_URL:?WAVEBREAK_DATABASE_URL is required}"
backup="${1:-}"
if [ -z "$backup" ]; then
    echo "usage: restore-postgres.sh BACKUP_FILE" >&2
    exit 2
fi

case "$backup" in
    *.age)
        : "${WAVEBREAK_BACKUP_AGE_IDENTITY:?WAVEBREAK_BACKUP_AGE_IDENTITY is required for encrypted backups}"
        tmp="$(mktemp)"
        age -d -i "$WAVEBREAK_BACKUP_AGE_IDENTITY" "$backup" > "$tmp"
        trap 'rm -f "$tmp"' EXIT
        gunzip -c "$tmp" | pg_restore --clean --if-exists --dbname "$WAVEBREAK_DATABASE_URL"
        ;;
    *.gz)
        gunzip -c "$backup" | pg_restore --clean --if-exists --dbname "$WAVEBREAK_DATABASE_URL"
        ;;
    *)
        pg_restore --clean --if-exists --dbname "$WAVEBREAK_DATABASE_URL" "$backup"
        ;;
esac
