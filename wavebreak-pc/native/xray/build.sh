#!/usr/bin/env bash
# Builds xray.exe (windows/amd64) for the PC client's Xray engine (handoff
# docs/HANDOFF-pc-xray-migration.md, phase 1) from the SAME Xray-core the
# Android bridge pins — wavebreak-mobile/native/hysteria_bridge/go.mod — so
# phone and PC run one engine version. Output: windows/runtime_deps/xray.exe
# (next to sing-box.exe; Xray finds geoip.dat/geosite.dat through
# XRAY_LOCATION_ASSET, copied here from the Android module).
#
# Compile only: nothing here starts the engine or touches the network.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
pc=$(cd "$here/../.." && pwd)
bridge="$pc/../wavebreak-mobile/native/hysteria_bridge"
export PATH="/c/Program Files/Go/bin:$PATH"
out="$pc/windows/runtime_deps"
mkdir -p "$out"
(cd "$bridge" && GOOS=windows GOARCH=amd64 CGO_ENABLED=0 \
  go build -trimpath -ldflags="-s -w -checklinkname=0" \
  -o "$out/xray.exe" github.com/xtls/xray-core/main)
cp "$bridge/geodata/geoip.dat" "$bridge/geodata/geosite.dat" "$out/"
"$out/xray.exe" version | head -1
echo "Built $out/xray.exe"
