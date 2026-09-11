# WAVEBREAK Core

Go control plane for WAVEBREAK.

## Responsibilities

- Own business logic and PostgreSQL schema.
- Expose the Core REST API.
- Publish domain events through a transactional outbox.
- Keep Redis usage ephemeral under the `wavebreak:*` namespace.
- Declare RabbitMQ exchanges, queues, bindings, retries, and DLQs.

## Local Commands

```bash
go mod tidy
go test ./...
go test -race ./...
go build ./cmd/wavebreak-api ./cmd/wavebreak-worker
```

Run migrations with Goose:

```bash
wavebreak-migrate
```

OpenAPI lives at `api/openapi.yaml`.

## Admin Bootstrap

```bash
wavebreak-cli admin create --email admin@example.com --role superadmin
wavebreak-cli admin reset-password --email admin@example.com
wavebreak-cli node token --region TR --ttl 24h
```
