#!/usr/bin/env bash
# WAVEBREAK Lite (32-bit Windows): tests, x86 exe, installer.
#   wavebreak-lite/build.sh 1.0.0
# Needs Go, Inno Setup (ISCC from tools/release/local.env) and the x86
# sing-box.exe in runtime_deps/ (see README.md — not in git).
set -euo pipefail
cd "$(dirname "$0")"
VERSION=${1:?usage: build.sh <version, three numbers>}
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must be three numbers"; exit 1; }
[ -f ../tools/release/local.env ] && source ../tools/release/local.env
ISCC=${ISCC:-"$LOCALAPPDATA/Programs/Inno Setup 6/ISCC.exe"}

for f in runtime_deps/sing-box.exe runtime_deps/wintun.dll; do
  [ -f "$f" ] || { echo "missing $f (README.md)"; exit 1; }
  file "$f" | grep -q "Intel i386" || { echo "$f is not an x86 build"; exit 1; }
done

go vet ./...
GOARCH=386 go vet ./...
go test ./...
mkdir -p build
GOOS=windows GOARCH=386 CGO_ENABLED=0 go build -trimpath \
  -ldflags "-H windowsgui -s -w -X main.version=$VERSION" -o build/wavebreak-lite.exe .
file build/wavebreak-lite.exe | grep -q "Intel i386" || { echo "exe is not x86"; exit 1; }
"$ISCC" "-DMyAppVersion=$VERSION" installer/wavebreak-lite.iss | tail -1
ls -la "installer/Output/WaveBreak-Lite-Setup-$VERSION.exe"
sha256sum "installer/Output/WaveBreak-Lite-Setup-$VERSION.exe"
