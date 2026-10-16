#!/usr/bin/env bash
# Old builds out of a downloads folder (owner, 17.10: the mirror's disk on
# RU-MSK-01 filled up to 100 % with every build since 1.3.2 — the node,
# Xray, Hysteria and the personal-data database share that disk).
#
# Runs ON the server, from release.sh / tv-publish.sh after a publish:
#
#   ssh host 'bash -s' < prune-downloads.sh -- DIR [KEEP]
#
# Per kind of file — Android (and its per-ABI builds), Android rollback,
# TV (and its 32-bit build), Windows, Windows rollback — the KEEP (2)
# newest versions stay. Never removed: anything the live manifests
# (version*.json) name, the stable names (wavebreak-android.apk, …),
# the launcher, the manifests. Backups (*.bak-before-*): the newest one
# per file stays. Unfinished uploads (.*.part) older than a day go.
set -euo pipefail
DIR=${1:?folder}
KEEP=${2:-2}
cd "$DIR"

# Files the live manifests point at, by name.
live=$(cat version*.json 2>/dev/null | grep -oE '/downloads/[^"?]+' | sed 's#.*/##' | sort -u || true)
is_live() { printf '%s\n' "$live" | grep -qxF "$1"; }

removed=0
drop() {  # file
  local f=$1
  [ -e "$f" ] || return 0
  is_live "$f" && return 0
  rm -f -- "$f"
  echo "  - $f"
  removed=$((removed + 1))
}

# Versions of one kind, oldest first, minus the KEEP newest: their files go.
# $1: a sed -E expression printing the version of a matching file name;
# $2...: the file name patterns of that version (VER is replaced).
prune_kind() {
  local extract=$1; shift
  local versions old v p
  versions=$(ls -1 2>/dev/null | sed -nE "$extract" | sort -uV)
  [ -n "$versions" ] || return 0
  old=$(printf '%s\n' "$versions" | head -n -"$KEEP")
  for v in $old; do
    for p in "$@"; do drop "${p//VER/$v}"; done
  done
}

prune_kind 's/^wavebreak-android-([0-9][0-9.]*)(-arm64-v8a|-armeabi-v7a)?\.apk$/\1/p' \
  wavebreak-android-VER.apk wavebreak-android-VER-arm64-v8a.apk wavebreak-android-VER-armeabi-v7a.apk
prune_kind 's/^wavebreak-android-rollback-([0-9][0-9.]*)\.apk$/\1/p' \
  wavebreak-android-rollback-VER.apk
prune_kind 's/^wavebreak-tv-([0-9][0-9.]*-[0-9]+)(-arm32)?\.apk$/\1/p' \
  wavebreak-tv-VER.apk wavebreak-tv-VER-arm32.apk
prune_kind 's/^wavebreak-windows-([0-9][0-9.]*)-setup\.exe$/\1/p' \
  wavebreak-windows-VER-setup.exe
prune_kind 's/^wavebreak-windows-rollback-([0-9][0-9.]*)-setup\.exe$/\1/p' \
  wavebreak-windows-rollback-VER-setup.exe

# Backups: the newest per file stays (the timestamps sort as text).
for base in $(ls -1 2>/dev/null | sed -nE 's/^(.+)\.bak-before-[0-9-]+$/\1/p' | sort -u); do
  ls -1 2>/dev/null | grep -E "^$(printf '%s' "$base" | sed 's/[.[\*^$]/\\&/g')\.bak-before-[0-9-]+$" \
    | sort | head -n -1 | while read -r b; do rm -f -- "$b"; echo "  - $b"; done
done

# Unfinished uploads older than a day.
find . -maxdepth 1 -name '.*.part' -mmin +1440 -print -delete | sed 's#^\./#  - #'

echo "  удалено старых сборок: $removed; свободно: $(df -h . | awk 'NR==2 {print $4}')"
