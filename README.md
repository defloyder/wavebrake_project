# WAVEBREAK

WAVEBREAK is a standalone platform composed of:

- `wavebreak-core`: Go API and worker. Owns business logic, PostgreSQL schema, Redis cache keys, RabbitMQ topology, OpenAPI, and domain events.
- `wavebreak-web`: Laravel public website and user cabinet. Calls Core by API only.
- `wavebreak-admin`: Laravel admin application. Calls Core by API only.
- `wavebreak-node`: Go node agent.
- `wavebreak-infrastructure`: Docker Compose, monitoring, Nginx templates, bootstrap scripts.

## Architecture

```text
Internet
  |
  +--> WAVEBREAK WEB    --+
  |                       |
  +--> WAVEBREAK ADMIN  --+--> WAVEBREAK CORE API/Worker
                              |
                              +--> PostgreSQL
                              +--> Redis
                              +--> RabbitMQ
                              |
                              +--> WAVEBREAK NODE agents

Observability:
Core / Node / Infra -> OpenTelemetry Collector -> Prometheus / Loki / Tempo -> Grafana -> Alertmanager
```

## Local MVP Flow

```bash
cd wavebreak-infrastructure
docker compose up -d postgres redis rabbitmq

docker compose up -d wavebreak-migrate wavebreak-api wavebreak-worker
docker compose up -d prometheus grafana loki tempo otel-collector alertmanager
```

Core API:

```text
http://localhost:8080
```

Web:

```text
http://localhost:8000
```

Admin:

```text
http://localhost:8002
```

Grafana:

```text
http://localhost:3000
```

## Verification

```bash
cd wavebreak-core
go test ./...
go test -race ./...

cd ../wavebreak-node
go test ./...
go test -race ./...
```

## Mobile/Desktop Integration

Send app developers:

- `MOBILE_DESKTOP_DEVELOPER_HANDOFF.md`
- `docs/mobile-desktop-api.md`
- `wavebreak-core/api/openapi.yaml`
- `docs/vpn-config-contract.md`

Mobile and desktop clients must call Core API only. The local Docker Core URL is `http://127.0.0.1:18080`; production should expose a dedicated HTTPS Core API URL.

## Production Notes

- Replace local secrets before production.
- Protect RabbitMQ UI, Grafana, SSH, PostgreSQL, Redis, and Prometheus behind private networks or VPN.
- Laravel apps must never mutate Core tables directly.
- Use PostgreSQL as the source of truth; Redis is ephemeral only.
- Use RabbitMQ for async execution, events, notifications, and integration.
- Create the first admin with `wavebreak-cli admin create`.
- Create node enrollment tokens with `wavebreak-cli node token`.
