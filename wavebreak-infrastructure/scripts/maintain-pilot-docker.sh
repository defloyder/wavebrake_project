#!/usr/bin/env sh
set -eu

# Build layers are reproducible and can otherwise consume the small pilot disk.
# Running images, containers, volumes and database data are never pruned here.
docker builder prune --force --filter 'until=168h'

usage_percent="$(df -P / | awk 'NR == 2 { gsub(/%/, "", $5); print $5 }')"
if [ "$usage_percent" -ge 80 ]; then
    printf 'warning: root filesystem usage remains at %s%% after cache cleanup\n' "$usage_percent" >&2
    exit 1
fi

printf 'root filesystem usage: %s%%\n' "$usage_percent"
