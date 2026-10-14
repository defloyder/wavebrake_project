#!/usr/bin/env bash
# Publishes an Android TV build made by `tv.ps1 -BuildNumber N`:
#
#   tools/release/tv-publish.sh N
#
# Both APKs (full: arm64/arm32/x86_64; light: 32-bit ARM) go to the mirror
# (dl.) and the site under versioned names and under the stable names the
# download page links to (wavebreak-tv.apk, wavebreak-tv-arm32.apk); then,
# last, version-tv.json — the TV app's own update manifest (owner, 14.10:
# the TV gets updates like the phone and the PC). 64-bit boxes are offered
# the full build, 32-bit ones the light build (update_service.dart picks by
# the device's ABIs). Only after the owner's "публикуй".
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
[ -f "$HERE/local.env" ] && . "$HERE/local.env"
: "${SSH_KEY:=$HOME/.ssh/wavebreak_pilot}"
MIRROR_HOST=root@135.106.227.90
SITE_HOST=root@45.15.41.3
MIRROR_DIR=/var/www/dl/downloads
SITE_DIR=/home/wavebreakdeploy/wavebreak-pilot/current/wavebreak-web/public/downloads
SSH=(ssh -n -i "$SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ServerAliveInterval=30)
SCP=(scp -q -i "$SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ServerAliveInterval=30)
die() { echo "ОШИБКА: $*" >&2; exit 1; }

N=${1:-}
[[ "$N" =~ ^[0-9]+$ ]] || die "укажите номер ТВ-сборки: tv-publish.sh N"
full=$(ls "$ROOT"/.artifacts/tv/wavebreak-tv-*-"$N"-preview.apk 2>/dev/null | grep -v arm32 | head -1 || true)
[ -n "$full" ] || die "нет .artifacts/tv/wavebreak-tv-*-$N-preview.apk (сначала tv.ps1 -BuildNumber $N)"
arm32=${full%-preview.apk}-arm32-preview.apk
[ -f "$arm32" ] || die "нет $(basename "$arm32")"
ver=$(basename "$full" | sed -E "s/^wavebreak-tv-(.*)-$N-preview\.apk$/\1/")
F=wavebreak-tv-$ver-$N.apk
A=wavebreak-tv-$ver-$N-arm32.apk

# What's live must be older: never re-publish or go back by accident.
live=$(curl -sf -m 20 "https://wavebreak.com.tr/downloads/version-tv.json" \
  | sed -nE 's/.*"versionCode": *([0-9]+).*/\1/p' | head -1 || true)
if [ -n "$live" ] && [ "$live" -ge "$N" ]; then
  die "на сайте уже ТВ-сборка $live (≥ $N)"
fi

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
cp "$full" "$work/$F"; cp "$arm32" "$work/$A"
dl=https://dl.wavebreak.com.tr/downloads; site=https://wavebreak.com.tr/downloads
cat > "$work/version-tv.json" <<JSON
{
  "versionCode": $N,
  "versionName": "$ver",
  "url": "$dl/$F",
  "mirrors": ["$site/$F"],
  "abis": {
    "arm64-v8a": ["$dl/$F", "$site/$F"],
    "x86_64": ["$dl/$F", "$site/$F"],
    "armeabi-v7a": ["$dl/$A", "$site/$A"]
  }
}
JSON

ts=$(date +%Y%m%d-%H%M%S)
put() {  # host dir — the APKs (versioned + stable names), the manifest last
  local host=$1 dir=$2
  for f in "$F" "$A"; do
    for t in 1 2 3; do "${SCP[@]}" "$work/$f" "$host:$dir/.$f.part" && break; echo "повтор $f"; done
  done
  "${SCP[@]}" "$work/version-tv.json" "$host:$dir/.version-tv.json.part"
  "${SSH[@]}" "$host" "set -e; cd $dir
    for f in $F $A; do chown --reference=. .\$f.part; chmod 644 .\$f.part; mv .\$f.part \$f; done
    for p in $F:wavebreak-tv.apk $A:wavebreak-tv-arm32.apk; do
      src=\${p%%:*}; name=\${p#*:}
      [ -e \$name ] && cp -p \$name \$name.bak-before-$ts
      cp \$src .\$name.tmp; chown --reference=. .\$name.tmp; chmod 644 .\$name.tmp; mv .\$name.tmp \$name
    done
    python3 -m json.tool .version-tv.json.part >/dev/null
    [ -e version-tv.json ] && cp -p version-tv.json version-tv.json.bak-before-$ts
    chown --reference=. .version-tv.json.part; chmod 644 .version-tv.json.part
    mv .version-tv.json.part version-tv.json"
}
echo "== Зеркало"; put "$MIRROR_HOST" "$MIRROR_DIR"
echo "== Сайт"; put "$SITE_HOST" "$SITE_DIR"

echo "== Проверка"
for u in "$dl/version-tv.json" "$site/version-tv.json"; do
  echo "  $(curl -sf -m 20 "$u?t=$ts" | sed -nE 's/.*"versionCode": *([0-9]+).*/versionCode \1/p') <- $u"
done
for u in "$dl/$F" "$dl/$A" "$site/$F" "$site/$A" "$site/wavebreak-tv.apk" "$site/wavebreak-tv-arm32.apk"; do
  echo "$(curl -s -o /dev/null -w '%{http_code}' -I -m 20 "$u") $u"
done
echo "Опубликована ТВ-сборка $ver ($N). Запишите в CHANGELOG.md и docs/PROJECT-STATE.md."
