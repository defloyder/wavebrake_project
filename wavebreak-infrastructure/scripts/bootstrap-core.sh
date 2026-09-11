#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")/.."
docker compose up -d postgres redis rabbitmq
docker compose up -d wavebreak-api wavebreak-worker
