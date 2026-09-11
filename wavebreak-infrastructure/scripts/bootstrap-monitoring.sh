#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")/.."
docker compose up -d prometheus grafana loki tempo otel-collector alertmanager node-exporter cadvisor
