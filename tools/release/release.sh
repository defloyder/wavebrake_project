#!/usr/bin/env bash
# WAVEBREAK release — the one way to build and publish Android/Windows
# updates, the same on every machine. Read CLAUDE.md first.
#
#   tools/release/release.sh check   [all|android|windows]   preflight only
#   tools/release/release.sh build   [all|android|windows]   release + rollback builds
#   tools/release/release.sh stage                           upload, print test links
#   tools/release/release.sh publish                         go live (after the phone check)
#
# What it guarantees (each of these went wrong at least once by hand):
# - builds only from branch app-main-sync, clean, identical to origin;
# - version numbers come from tools/release/releases.json + the live
#   manifests, never reused; Windows names are three numbers;
# - the 4 production dart-defines are always passed, and every binary is
#   checked to really contain the production Core URL (no mock builds);
# - the bridge .aar is rebuilt when its sources changed;
# - the rollback is the last published release, built from its own commit;
# - the Android signature is the release key (fingerprint check);
# - publishing: files first, manifests last, every link checked, history
#   committed and tagged so the other machine sees it.
# Machine-specific paths: tools/release/local.env (see local.env.example).
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
HERE=tools/release
[ -f "$HERE/local.env" ] && . "$HERE/local.env"

BRANCH=app-main-sync
CORE_URL=https://core.wavebreak.com.tr
DEFINES=(--dart-define=FLAVOR=production "--dart-define=CORE_BASE_URL=$CORE_URL"
         --dart-define=USE_MOCK_API=false --dart-define=ACCESS_PROTOCOL=vless)
OUT="$ROOT/.artifacts/release"
STATE="$OUT/state.env"
WT=${RELEASE_WORKTREE:-/c/wbrb}          # short path: long ones break worktree removal on Windows
SSH_KEY=${SSH_KEY:-$HOME/.ssh/wavebreak_pilot}
ISCC=${ISCC:-"$LOCALAPPDATA/Programs/Inno Setup 6/ISCC.exe"}
MIRROR_HOST=root@135.106.227.90
SITE_HOST=root@45.15.41.3
MIRROR_DIR=/var/www/dl/downloads
SITE_DIR=/home/wavebreakdeploy/wavebreak-pilot/current/wavebreak-web/public/downloads
SSH=(ssh -n -i "$SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ServerAliveInterval=30)
SCP=(scp -q -i "$SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ServerAliveInterval=30)
[ -n "${FLUTTER_BIN:-}" ] && export PATH="$FLUTTER_BIN:$PATH"

say()  { printf '\n== %s\n' "$*"; }
die()  { printf '\nОСТАНОВКА: %s\n' "$*" >&2; exit 1; }
rel()  { dart run "$HERE/rel.dart" "$@"; }

tool() {  # latest Android build-tools binary
  local t; t=$(ls "$ANDROID_HOME"/build-tools/*/"$1"* 2>/dev/null | sort -V | tail -1)
  [ -n "$t" ] || die "нет $1 в \$ANDROID_HOME/build-tools ($ANDROID_HOME)"
  echo "$t"
}

bridge_src() {  # identity of the bridge sources at a commit (tree hashes)
  echo "$(git rev-parse "$1:wavebreak-mobile/native/hysteria_bridge")-$(git rev-parse "$1:wavebreak-shared/cloak")"
}

# --- preflight ---------------------------------------------------------------
preflight() {
  local want=$1
  say "Проверка репозитория"
  [ "$(git branch --show-current)" = "$BRANCH" ] || die "ветка $(git branch --show-current), нужна $BRANCH: git switch $BRANCH"
  [ -z "$(git status --porcelain --untracked-files=no)" ] || { git status --short --untracked-files=no; die "есть незакоммиченные изменения — закоммитьте или уберите их"; }
  git fetch -q origin "$BRANCH"
  local head origin; head=$(git rev-parse HEAD); origin=$(git rev-parse "origin/$BRANCH")
  if [ "$head" != "$origin" ]; then
    git merge-base --is-ancestor "$head" "$origin" && die "ветка отстаёт от origin: git pull --rebase origin $BRANCH"
    git merge-base --is-ancestor "$origin" "$head" && die "есть незапушенные коммиты: git push origin $BRANCH"
    die "ветка разошлась с origin: git pull --rebase origin $BRANCH"
  fi
  echo "ok: $BRANCH = origin ($(git rev-parse --short HEAD)), чисто"

  say "Проверка инструментов и файлов вне git"
  command -v flutter >/dev/null || die "нет flutter в PATH (FLUTTER_BIN в $HERE/local.env)"
  command -v dart >/dev/null || die "нет dart в PATH"
  [ -f "$SSH_KEY" ] || die "нет SSH-ключа $SSH_KEY (SSH_KEY в $HERE/local.env)"
  if [ "$want" != windows ]; then
    [ -n "${ANDROID_HOME:-}" ] || die "не задан ANDROID_HOME ($HERE/local.env)"
    [ -f wavebreak-mobile/android/key.properties ] || die "нет wavebreak-mobile/android/key.properties (ключ подписи — docs/BUILD-MACHINE-SETUP.md, раздел 3)"
    [ -f wavebreak-mobile/android/app/wavebreak-release.jks ] || die "нет wavebreak-mobile/android/app/wavebreak-release.jks"
    tool aapt >/dev/null; tool apksigner >/dev/null
  fi
  if [ "$want" != android ]; then
    [ -f "$ISCC" ] || die "нет Inno Setup: $ISCC"
    for f in sing-box.exe wintun.dll cloak-client-proxy.exe; do
      [ -f "wavebreak-pc/windows/runtime_deps/$f" ] || die "нет wavebreak-pc/windows/runtime_deps/$f (docs/BUILD-MACHINE-SETUP.md, раздел 5)"
    done
  fi
  "${SSH[@]}" "$MIRROR_HOST" true 2>/dev/null || die "нет SSH до зеркала $MIRROR_HOST"
  "${SSH[@]}" "$SITE_HOST" true 2>/dev/null || die "нет SSH до сайта $SITE_HOST"
  echo "ok: инструменты, ключи, доступ к серверам"
}

# --- build -------------------------------------------------------------------
ensure_aar() {  # $1 = checkout root
  local root=$1 commit=$2 aar="$1/wavebreak-mobile/android/app/libs/hysteria_bridge.aar"
  local want; want=$(bridge_src "$commit")
  if [ -f "$aar" ] && [ "$(cat "$aar.src" 2>/dev/null)" = "$want" ]; then
    echo "ok: мост .aar соответствует исходникам"; return
  fi
  if [ "$root" != "$ROOT" ] && [ "$(cat "$ROOT/wavebreak-mobile/android/app/libs/hysteria_bridge.aar.src" 2>/dev/null)" = "$want" ]; then
    mkdir -p "$(dirname "$aar")"; cp "$ROOT/wavebreak-mobile/android/app/libs/hysteria_bridge.aar" "$aar"
    echo "$want" > "$aar.src"; echo "ok: мост .aar взят из основной копии (исходники те же)"; return
  fi
  say "Сборка моста .aar (исходники изменились) — около 10 минут"
  bash "$root/wavebreak-mobile/native/hysteria_bridge/build_aar.sh" | tail -2
  echo "$want" > "$aar.src"
}

build_android() {  # $1 root $2 name $3 code $4 outprefix
  local root=$1 name=$2 code=$3 prefix=$4
  ( cd "$root/wavebreak-mobile"
    flutter pub get >/dev/null
    flutter build apk --release --build-name="$name" --build-number="$code" "${DEFINES[@]}" | grep -E "Built|FAIL|rror" | tail -1
    cp build/app/outputs/flutter-apk/app-release.apk "$OUT/$prefix.apk"
    if [ -z "${5:-}" ]; then
      for abi in arm64-v8a:android-arm64 armeabi-v7a:android-arm; do
        flutter build apk --release --target-platform "${abi#*:}" --build-name="$name" --build-number="$code" "${DEFINES[@]}" | grep -E "Built|FAIL|rror" | tail -1
        cp build/app/outputs/flutter-apk/app-release.apk "$OUT/$prefix-${abi%%:*}.apk"
      done
    fi )
}

build_windows() {  # $1 root $2 name $3 code $4 outfile
  local root=$1 name=$2 code=$3 out=$4
  ( cd "$root/wavebreak-pc"
    flutter pub get >/dev/null
    flutter build windows --release --build-name="$name" --build-number="$code" "${DEFINES[@]}" | grep -E "Built|rror" | tail -1
    [ -f build/windows/x64/runner/Release/data/app.so ] || die "неполная сборка Windows (нет data/app.so)"
    "$ISCC" windows/installer/wavebreak.iss | tail -1
    cp "windows/installer/Output/WaveBreak-Setup-$name.exe" "$out" )
}

verify_apk() {  # $1 file $2 name $3 code
  local f=$1 badge cert
  badge=$("$(tool aapt)" dump badging "$f" | grep -oE "versionCode='[0-9]+' versionName='[^']+'")
  [ "$badge" = "versionCode='$3' versionName='$2'" ] || die "$f: $badge, ожидалось $2 ($3)"
  cert=$("$(tool apksigner)" verify --print-certs "$f" | grep -m1 "SHA-256" | awk '{print $NF}')
  [ "$cert" = "$(rel cert)" ] || die "$f подписан не релизным ключом (SHA-256 $cert)"
  local so; so=$(unzip -l "$f" | grep -oE "lib/[^ ]+/libapp.so" | head -1)
  # The library goes to a temp file first: piped into grep -q, grep quit at
  # the first match, unzip got SIGPIPE and pipefail failed the check (1.3.0).
  local lib; lib=$(mktemp); unzip -p "$f" "$so" > "$lib"
  grep -aq "$CORE_URL" "$lib" || { rm -f "$lib"; die "$f: нет боевого адреса Core — сборка с заглушками"; }
  ! grep -aq "127.0.0.1:18080" "$lib" || { rm -f "$lib"; die "$f: собран с адресом по умолчанию (заглушки)"; }
  rm -f "$lib"
  echo "ok: $(basename "$f") — $2 ($3), релизный ключ, боевой Core"
}

verify_windows() {  # $1 root $2 name $3 code
  local rel_dir="$1/wavebreak-pc/build/windows/x64/runner/Release" v
  v=$(powershell -NoProfile -c "(Get-Item '$(cygpath -w "$rel_dir/wavebreak.exe")').VersionInfo.ProductVersion" | tr -d '\r')
  [ "$v" = "$2+$3" ] || die "версия exe $v, ожидалась $2+$3"
  grep -aq "$CORE_URL" "$rel_dir/data/app.so" || die "Windows: нет боевого адреса Core — сборка с заглушками"
  for f in sing-box.exe wintun.dll cloak-client-proxy.exe; do [ -f "$rel_dir/$f" ] || die "Windows: нет $f рядом с exe"; done
  echo "ok: Windows $v, боевой Core, sing-box/wintun/cloak-client-proxy на месте"
}

worktree_at() {  # $1 commit
  git worktree remove --force "$WT" 2>/dev/null || true; git worktree prune
  git -c core.longpaths=true worktree add -f "$WT" "$1" >/dev/null
}
worktree_drop() { git -c core.longpaths=true worktree remove --force "$WT" 2>/dev/null || true; git worktree prune; }

cmd_build() {
  local want=${1:-all} aname=${2:-}
  preflight "$want"
  mkdir -p "$OUT"; rm -f "$OUT"/*.apk "$OUT"/*.exe "$OUT"/*.json
  : > "$STATE"
  local an ac arn arc arcommit wn wc wrn wrc wrcommit
  if [ "$want" != windows ]; then read -r an ac arn arc arcommit < <(rel next android $aname); fi
  if [ "$want" != android ]; then read -r wn wc wrn wrc wrcommit < <(rel next windows); fi
  say "Версии: ${an:+Android $an ($ac), откат $arn ($arc)} ${wn:+Windows $wn ($wc), откат $wrn ($wrc)}"

  [ -n "${an:-}" ] && sed -i -E "s/^version: .*/version: $(echo "$an" | cut -d. -f1-3)+$ac/" wavebreak-mobile/pubspec.yaml
  if [ -n "${wn:-}" ]; then
    sed -i -E "s/^version: .*/version: $wn+$wc/" wavebreak-pc/pubspec.yaml
    sed -i -E "s/^#define MyAppVersion \".*\"/#define MyAppVersion \"$wn\"/" wavebreak-pc/windows/installer/wavebreak.iss
  fi

  say "Тесты"
  (cd wavebreak-shared/wavebreak_links && dart test 2>&1 | tail -1)
  [ -n "${an:-}" ] && (cd wavebreak-mobile && flutter test 2>&1 | tail -1 | tee /dev/stderr | grep -q "All tests passed") || [ -z "${an:-}" ] || die "тесты Android не прошли"
  [ -n "${wn:-}" ] && (cd wavebreak-pc && flutter test 2>&1 | tail -1 | tee /dev/stderr | grep -q "All tests passed") || [ -z "${wn:-}" ] || die "тесты Windows не прошли"

  if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    git commit -qam "Release prep: ${an:+Android $an ($ac)}${an:+${wn:+, }}${wn:+Windows $wn ($wc)}"
    git push -q origin "$BRANCH" || die "не удалось запушить коммит с версиями (кто-то запушил раньше?): git pull --rebase и заново"
  fi
  local commit; commit=$(git rev-parse --short HEAD)
  {
    echo "COMMIT=$commit"; echo "ID=$(date +%Y%m%d-%H%M)"
    echo "AN=${an:-}"; echo "AC=${ac:-}"; echo "ARN=${arn:-}"; echo "ARC=${arc:-}"; echo "ARCOMMIT=${arcommit:-}"
    echo "WN=${wn:-}"; echo "WC=${wc:-}"; echo "WRN=${wrn:-}"; echo "WRC=${wrc:-}"; echo "WRCOMMIT=${wrcommit:-}"
  } > "$STATE"

  if [ -n "${an:-}" ]; then
    say "Android $an ($ac)"
    ensure_aar "$ROOT" HEAD
    build_android "$ROOT" "$an" "$ac" "wavebreak-android-$an"
    for f in "$OUT"/wavebreak-android-"$an"*.apk; do verify_apk "$f" "$an" "$ac"; done
    say "Откат Android $arn ($arc) из $arcommit"
    worktree_at "$arcommit"
    cp wavebreak-mobile/android/key.properties wavebreak-mobile/android/local.properties "$WT/wavebreak-mobile/android/" 2>/dev/null || cp wavebreak-mobile/android/key.properties "$WT/wavebreak-mobile/android/"
    cp wavebreak-mobile/android/app/wavebreak-release.jks "$WT/wavebreak-mobile/android/app/"
    ensure_aar "$WT" "$arcommit"
    build_android "$WT" "$arn" "$arc" "wavebreak-android-rollback-$arn" universal-only
    worktree_drop   # holds a copy of the signing key
    verify_apk "$OUT/wavebreak-android-rollback-$arn.apk" "$arn" "$arc"
  fi
  if [ -n "${wn:-}" ]; then
    say "Windows $wn ($wc)"
    build_windows "$ROOT" "$wn" "$wc" "$OUT/wavebreak-windows-$wn-setup.exe"
    verify_windows "$ROOT" "$wn" "$wc"
    say "Откат Windows $wrn ($wrc) из $wrcommit"
    worktree_at "$wrcommit"
    cp wavebreak-pc/windows/runtime_deps/{sing-box.exe,wintun.dll,cloak-client-proxy.exe} "$WT/wavebreak-pc/windows/runtime_deps/"
    build_windows "$WT" "$wrn" "$wrc" "$OUT/wavebreak-windows-rollback-$wrn-setup.exe"
    verify_windows "$WT" "$wrn" "$wrc"
    worktree_drop
  fi
  [ -n "${an:-}" ] && rel manifest android "$an" "$ac" "$arn" "$arc" "$OUT/version.json"
  [ -n "${wn:-}" ] && rel manifest windows "$wn" "$wc" "$wrn" "$wrc" "$OUT/version-windows.json"
  say "Собрано из $commit:"; ls -la "$OUT" | grep -E "apk|exe|json"
  echo; echo "Дальше: tools/release/release.sh stage"
}

# --- stage -------------------------------------------------------------------
cmd_stage() {
  [ -s "$STATE" ] || die "нет сборки: сначала build"
  . "$STATE"
  cd "$OUT"
  local files; files=$(ls *.apk *.exe 2>/dev/null | tr '\n' ' ')
  say "Загрузка на зеркало (incoming-$ID)"
  "${SSH[@]}" "$MIRROR_HOST" "mkdir -p $MIRROR_DIR/incoming-$ID"
  for f in $files *.json; do
    [ -f "$f" ] || continue
    for t in 1 2 3; do "${SCP[@]}" "$f" "$MIRROR_HOST:$MIRROR_DIR/incoming-$ID/" && break; echo "повтор $f"; done
  done
  sha256sum $files | sed 's/ \*/  /' | LC_ALL=C sort -k2 > local.sha
  "${SSH[@]}" "$MIRROR_HOST" "cd $MIRROR_DIR/incoming-$ID && sha256sum $files" | LC_ALL=C sort -k2 > mirror.sha
  diff -q local.sha mirror.sha >/dev/null || die "хэши на зеркале не совпали"
  say "Копия на сервер сайта (сервер-сервер)"
  "${SSH[@]}" "$SITE_HOST" "set -e; mkdir -p /root/staging/$ID && cd /root/staging/$ID; for f in $files version.json version-windows.json; do curl -sf -m 600 -o \$f https://dl.wavebreak.com.tr/downloads/incoming-$ID/\$f || [ \$f = version.json ] || [ \$f = version-windows.json ]; done; sha256sum $files" | LC_ALL=C sort -k2 > site.sha
  diff -q local.sha site.sha >/dev/null || die "хэши на сервере сайта не совпали"
  cd "$ROOT"
  [ -n "$AC" ] && rel take android "$ARC"
  [ -n "$WC" ] && rel take windows "$WRC"
  git add "$HERE/releases.json"; git commit -qm "Release staged: ${AN:+Android $AN ($AC)} ${WN:+Windows $WN ($WC)} — numbers taken" || true
  git push -q origin "$BRANCH" || die "не удалось запушить releases.json: git pull --rebase и заново stage не нужен, просто git push"
  say "Готово к проверке на телефоне/ПК:"
  [ -n "$AN" ] && echo "  Android: https://dl.wavebreak.com.tr/downloads/incoming-$ID/wavebreak-android-$AN-arm64-v8a.apk"
  [ -n "$WN" ] && echo "  Windows: https://dl.wavebreak.com.tr/downloads/incoming-$ID/wavebreak-windows-$WN-setup.exe"
  echo; echo "После проверки: tools/release/release.sh publish"
}

# --- publish -----------------------------------------------------------------
cmd_publish() {
  [ -s "$STATE" ] || die "нет сборки: сначала build и stage"
  . "$STATE"
  local ts files="" puts=""
  ts=$(date +%Y%m%d-%H%M)
  if [ -n "$AN" ]; then
    files="$files wavebreak-android-$AN.apk wavebreak-android-$AN-arm64-v8a.apk wavebreak-android-$AN-armeabi-v7a.apk wavebreak-android-rollback-$ARN.apk"
    puts="$puts wavebreak-android-$AN-arm64-v8a.apk:wavebreak-android-$AN-arm64-v8a.apk wavebreak-android-$AN-armeabi-v7a.apk:wavebreak-android-$AN-armeabi-v7a.apk wavebreak-android-rollback-$ARN.apk:wavebreak-android-rollback.apk wavebreak-android-$AN.apk:wavebreak-android.apk"
  fi
  if [ -n "$WN" ]; then
    files="$files wavebreak-windows-$WN-setup.exe wavebreak-windows-rollback-$WRN-setup.exe"
    puts="$puts wavebreak-windows-rollback-$WRN-setup.exe:wavebreak-windows-rollback.exe wavebreak-windows-$WN-setup.exe:wavebreak-windows.exe"
  fi
  local manifests=""; [ -n "$AN" ] && manifests="version.json"; [ -n "$WN" ] && manifests="$manifests version-windows.json"

  say "1. Зеркало: файлы"
  "${SSH[@]}" "$MIRROR_HOST" "set -e; cd $MIRROR_DIR; for f in $files; do [ -e \$f ] && mv \$f \$f.bak-before-$ts; case \$f in *.exe) chmod 755 incoming-$ID/\$f;; *) chmod 644 incoming-$ID/\$f;; esac; mv incoming-$ID/\$f ./; done"
  say "2. Сайт: файлы в папку хоста (она подключена к контейнеру сайта)"
  "${SSH[@]}" "$SITE_HOST" "set -e; H=$SITE_DIR; for p in $puts; do src=/root/staging/$ID/\${p%%:*}; name=\${p#*:}; [ -e \$H/\$name ] && cp -p \$H/\$name \$H/\$name.bak-before-$ts; cp \$src \$H/\$name.tmp; chown --reference=\$H \$H/\$name.tmp; chmod 644 \$H/\$name.tmp; mv \$H/\$name.tmp \$H/\$name; echo \"  \$name\"; done"
  say "3. Манифесты — последними"
  "${SSH[@]}" "$MIRROR_HOST" "set -e; cd $MIRROR_DIR; for m in $manifests; do python3 -m json.tool incoming-$ID/\$m >/dev/null; cp -p \$m \$m.bak-before-$ts; cp incoming-$ID/\$m \$m.new; chmod 644 \$m.new; mv \$m.new \$m; done; rm -rf incoming-$ID"
  "${SSH[@]}" "$SITE_HOST" "set -e; H=$SITE_DIR; for m in $manifests; do python3 -m json.tool /root/staging/$ID/\$m >/dev/null; cp -p \$H/\$m \$H/\$m.bak-before-$ts; cp /root/staging/$ID/\$m \$H/\$m.tmp; chown --reference=\$H \$H/\$m.tmp; chmod 644 \$H/\$m.tmp; mv \$H/\$m.tmp \$H/\$m; done; rm -rf /root/staging/$ID"

  say "4. Проверка ссылок"
  local bad=0
  for m in $manifests; do
    for base in https://dl.wavebreak.com.tr/downloads https://wavebreak.com.tr/downloads; do
      curl -s "$base/$m?t=$RANDOM" | grep -E '"versionName"' | head -1 | tr -d '\n'; echo "  <- $base/$m"
    done
    for u in $(curl -s "https://dl.wavebreak.com.tr/downloads/$m?t=$RANDOM" | grep -oE 'https://[^"]+' | sort -u); do
      code=$(curl -s -o /dev/null -I -w "%{http_code}" "$u"); echo "$code $u"; [ "$code" = 200 ] || bad=1
    done
  done
  [ $bad = 0 ] || die "есть недоступные ссылки — проверьте вручную (старые файлы сохранены как .bak-before-$ts)"

  say "5. История релизов"
  [ -n "$AN" ] && rel record android "$AN" "$AC" "$COMMIT" "$ARN" "$ARC" "$ARCOMMIT"
  [ -n "$WN" ] && rel record windows "$WN" "$WC" "$COMMIT" "$WRN" "$WRC" "$WRCOMMIT"
  git add "$HERE/releases.json"
  git commit -qm "Release ${AN:+Android $AN ($AC)}${AN:+${WN:+ and }}${WN:+Windows $WN ($WC)}" || true
  [ -n "$AN" ] && git tag -f "android/$AN" "$COMMIT"
  [ -n "$WN" ] && git tag -f "windows/$WN" "$COMMIT"
  git push -q origin "$BRANCH" && git push -q -f origin ${AN:+"android/$AN"} ${WN:+"windows/$WN"}
  : > "$STATE"
  say "Опубликовано. Не забудьте запись в CHANGELOG.md (что вошло) — коммит и пуш."
}

case "${1:-}" in
  check)   preflight "${2:-all}"
           [ "${2:-all}" != windows ] && echo "Следующий Android: $(rel next android)"
           [ "${2:-all}" != android ] && echo "Следующий Windows: $(rel next windows)"; true ;;
  build)   cmd_build "${2:-all}" "${3:-}" ;;   # build android 1.3.0 — своё имя версии Android
  stage)   cmd_stage ;;
  publish) cmd_publish ;;
  *) sed -n '2,8p' "$0"; exit 1 ;;
esac
