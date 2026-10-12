#!/usr/bin/env bash
# Builds build/WAVEBREAK-Launcher.exe — one 32-bit exe that runs on 32- and
# 64-bit (and ARM64) Windows 10/11. Pure Go (no cgo): WebView2 is loaded at
# run time (go-webview2 with its embedded loader).
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/c/Program Files/Go/bin:$PATH"
go vet ./...
go test ./...
mkdir -p build
GOOS=windows GOARCH=386 CGO_ENABLED=0 \
  go build -trimpath -ldflags="-s -w -H windowsgui" -o build/WAVEBREAK-Launcher.exe .
ls -la build/WAVEBREAK-Launcher.exe
