# WAVEBREAK Infrastructure

Docker Compose MVP infrastructure for WAVEBREAK.

## Services

- PostgreSQL
- Redis
- RabbitMQ with management and Prometheus metrics
- WAVEBREAK Core API
- WAVEBREAK Core worker
- WAVEBREAK node agent profile
- Prometheus, Grafana, Loki, Tempo, OpenTelemetry Collector, Alertmanager
- node_exporter and cAdvisor

## Start

```bash
docker compose up -d postgres redis rabbitmq
docker compose up -d wavebreak-api wavebreak-worker
docker compose up -d prometheus grafana loki tempo otel-collector alertmanager node-exporter cadvisor
```

Run Core migrations before first use:

```bash
cd ../wavebreak-core
goose -dir migrations postgres "$WAVEBREAK_DATABASE_URL" up
```
