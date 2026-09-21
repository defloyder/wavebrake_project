#!/usr/bin/env bash
# Rebuilds android/app/libs/hysteria_bridge.aar from this module's Go
# sources — one gomobile binding covering both Xray-core (xray.go:
# VLESS/VMess/Trojan/Shadowsocks/REALITY, MPL-2.0) and apernet/hysteria
# (bridge.go: Hysteria2, MIT). Run this after changing anything under
# native/hysteria_bridge.
#
# This app deliberately does NOT also depend on flutter_v2ray's own
# Xray-core (libv2ray.aar) — two independently gomobile-bound libraries
# in one Android process turned out not to be binary-compatible with
# each other despite matching Java-level signatures (confirmed via
# on-device logcat: both native libraries loaded fine, then the process
# died with no Java exception the moment one touched the other's shared
# go.Seq bridge). One binding, one go.Seq: don't reintroduce a second one.
#
# Requires: Go, the SagerNet gomobile fork (v0.1.13 — see go.mod's
# require on github.com/sagernet/gomobile), a JDK, and the Android
# SDK+NDK. Adjust the paths below to match your machine.
set -euo pipefail
cd "$(dirname "$0")"

: "${JAVA_HOME:=/c/dev-tools/jdk-17.0.20.1+1}"
: "${ANDROID_HOME:=/c/dev-tools/android-sdk}"
: "${ANDROID_NDK_HOME:=/c/dev-tools/android-sdk/ndk/28.2.13676358}"
export JAVA_HOME ANDROID_HOME ANDROID_NDK_HOME
export PATH="/c/Program Files/Go/bin:$HOME/go/bin:$JAVA_HOME/bin:$PATH"

gomobile bind -v -o hysteria_bridge.aar -target android -androidapi 24 \
  -javapkg=app.wavebreak.bridge -libname=hysteriabridge .

cp hysteria_bridge.aar ../../android/app/libs/hysteria_bridge.aar
echo "Built and copied to android/app/libs/hysteria_bridge.aar"
