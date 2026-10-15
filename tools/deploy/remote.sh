#!/usr/bin/env bash
# Runs ON the pilot server (as root), called by .github/workflows/deploy.yml:
#
#   remote.sh node|web|core <component.tgz> <git sha>
#
# The tarball is `git archive` of the component's directory at that sha.
# Same steps as the manual deploys of October 2026, now one script:
#   1. back up the component's files and tag the running image for rollback;
#   2. unpack the new files over the server tree (the compose build context);
#   3. build the image;
#   4. web: start it in a throwaway container and check the pages;
#      core: run the database migrations (goose, idempotent);
#   5. recreate the service and check it came up;
#   6. any failure after step 1: put the old files and image back.
set -euo pipefail

comp=${1:?node|web|core}
tgz=${2:?tarball}
sha=${3:?git sha}
ts=$(date +%Y%m%d-%H%M%S)
C=/home/wavebreakdeploy/wavebreak-pilot/current
INF=$C/wavebreak-infrastructure
COMPOSE=(docker compose -p wavebreak_pilot -f docker-compose.pilot.yml --env-file .env.pilot)
BK=/root/deploy-backups
mkdir -p "$BK"

case "$comp" in
  node) dir=wavebreak-node; svc=wavebreak-node; img=wavebreak_pilot-wavebreak-node ;;
  web)  dir=wavebreak-web;  svc=wavebreak-web;  img=wavebreak_pilot-wavebreak-web ;;
  core) dir=wavebreak-core; svc=wavebreak-api;  img=wavebreak_pilot-wavebreak-api ;;
  *) echo "unknown component $comp" >&2; exit 2 ;;
esac

say() { echo "== $*"; }

# The server's Core has run code that isn't in git since 06.10 (a
# separate personal-data database and more — docs/PROJECT-STATE.md item 0).
# Deploying git's Core over it would wipe that: refuse while the server
# tree has Go or SQL files this commit doesn't, before anything changes.
if [ "$comp" = core ]; then
  extra=$(comm -23 \
    <(cd "$C/$dir" && find . -type f \( -name '*.go' -o -name '*.sql' \) | sort) \
    <(tar tzf "$tgz" | sed -n "s#^$dir/#./#p" | sort))
  if [ -n "$extra" ]; then
    echo "REFUSED: the server's Core has files this commit doesn't:"
    echo "$extra" | head -30
    echo "Bring them into git (app-main-sync) first — docs/PROJECT-STATE.md item 0."
    echo "$ts $comp $sha REFUSED-DRIFT" >> /root/deploy-log.txt
    rm -f "$tgz"
    exit 3
  fi
fi

say "1. Backup ($dir, image $img)"
tar czf "$BK/$dir-$ts.tgz" -C "$C" \
  --exclude="$dir/public/downloads" --exclude="$dir/vendor" \
  --exclude="$dir/node_modules" --exclude="$dir/storage" "$dir"
docker tag "$img:latest" "$img:rollback-$ts"

rollback() {
  say "ROLLBACK to the state before $ts"
  tar xzf "$BK/$dir-$ts.tgz" -C "$C"
  docker tag "$img:rollback-$ts" "$img:latest"
  (cd "$INF" && "${COMPOSE[@]}" up -d --no-deps "$svc") || true
  echo "$ts $comp $sha ROLLED-BACK" >> /root/deploy-log.txt
  exit 1
}
trap rollback ERR

say "2. Files at $sha"
owner=$(stat -c %U:%G "$C/$dir")
tar xzf "$tgz" -C "$C"
chown -R "$owner" "$C/$dir" --from=root:root 2>/dev/null || true

say "3. Build"
# Base images through dockerd first: it falls back to IPv4, while the
# build's own registry lookup tried only IPv6, which this host doesn't
# have (15.10: "alpine:3.22 … network is unreachable" when the image had
# been pruned).
for base in $(sed -n 's/^FROM \([^ ]*\).*/\1/p' "$C/$dir/Dockerfile" | sort -u); do
  docker pull -q "$base" >/dev/null 2>&1 || echo "  (could not pull $base; the build tries itself)"
done
cd "$INF"
"${COMPOSE[@]}" build "$svc" 2>&1 | tail -3

if [ "$comp" = web ]; then
  say "4. Throwaway container check"
  umask 077
  docker inspect wavebreak_pilot-wavebreak-web-1 --format '{{range .Config.Env}}{{println .}}{{end}}' \
    | grep -E '^(APP_|SESSION_|WAVEBREAK_)' > /root/.webtest.env
  docker rm -f wb-deploytest >/dev/null 2>&1 || true
  docker run -d --rm --name wb-deploytest --env-file /root/.webtest.env \
    --network wavebreak_pilot_default -p 127.0.0.1:18099:8000 \
    -v "$C/wavebreak-web/public/downloads:/app/public/downloads:ro" "$img:latest" >/dev/null
  rm -f /root/.webtest.env
  for i in $(seq 1 30); do curl -sf -o /dev/null http://127.0.0.1:18099/ && break; sleep 1; done
  for p in / /download /en/download /tr/download /pricing /sitemap.xml; do
    code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:18099$p")
    echo "  $code $p"
    [ "$code" = 200 ] || { docker stop wb-deploytest >/dev/null; false; }
  done
  docker stop wb-deploytest >/dev/null
fi

if [ "$comp" = core ]; then
  say "4. Database migrations (goose, idempotent)"
  "${COMPOSE[@]}" build wavebreak-migrate 2>&1 | tail -1
  "${COMPOSE[@]}" run --rm wavebreak-migrate 2>&1 | tail -3
fi

say "5. Switch"
"${COMPOSE[@]}" up -d --no-deps "$svc" 2>&1 | tail -2

say "6. Check"
started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if [ "$comp" = node ]; then
  ok=0
  for i in $(seq 1 30); do
    if docker logs --since "$started" wavebreak_pilot-wavebreak-node-1 2>&1 | grep -q 'desired state applied'; then ok=1; break; fi
    sleep 3
  done
  [ $ok = 1 ] || { echo "the agent did not apply the desired state"; false; }
  sleep 5
  for c in wavebreak-pilot-xray wavebreak-pilot-hysteria; do
    [ "$(docker inspect -f '{{.State.Running}}' $c)" = true ] || { echo "$c is not running"; false; }
  done
  docker logs --since "$started" wavebreak-pilot-xray 2>&1 | grep -q 'Xray .* started' \
    || docker logs --tail 50 wavebreak-pilot-xray 2>&1 | grep -q 'started'
  echo "  agent applied, Xray and Hysteria running"
elif [ "$comp" = core ]; then
  for i in $(seq 1 30); do
    code=$(curl -s -o /dev/null -w "%{http_code}" https://core.wavebreak.com.tr/readyz) && [ "$code" = 200 ] && break
    sleep 2
  done
  code=$(curl -s -o /dev/null -w "%{http_code}" https://core.wavebreak.com.tr/readyz)
  echo "  $code https://core.wavebreak.com.tr/readyz"
  [ "$code" = 200 ] || false
  code=$(curl -s -o /dev/null -w "%{http_code}" -X POST https://core.wavebreak.com.tr/v1/auth/login -H "content-type: application/json" -d "{}")
  echo "  $code POST /v1/auth/login (expects 4xx, not 5xx)"
  case "$code" in 4*) ;; *) false ;; esac
else
  for i in $(seq 1 40); do
    s=$(docker inspect -f '{{.State.Health.Status}}' wavebreak_pilot-wavebreak-web-1)
    [ "$s" = healthy ] && break; sleep 2
  done
  [ "$s" = healthy ] || { echo "site container is $s"; false; }
  for p in / /download; do
    code=$(curl -s -o /dev/null -w '%{http_code}' "https://wavebreak.com.tr$p")
    echo "  $code https://wavebreak.com.tr$p"
    [ "$code" = 200 ] || false
  done
fi

trap - ERR
echo "$ts $comp $sha OK" >> /root/deploy-log.txt
rm -f "$tgz"
say "Done: $comp at $sha (backup $BK/$dir-$ts.tgz, image $img:rollback-$ts)"
