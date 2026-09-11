#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")/.."
docker compose --profile node up -d wavebreak-node
