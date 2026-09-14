# WAVEBREAK Deployment

For a practical one-server pilot runbook, see:

```text
docs/pilot-vps-deployment.md
```

MVP deployment target:

- VM 1: `wavebreak-web`, `wavebreak-admin`, Nginx, PHP runtime.
- VM 2: `wavebreak-api`, `wavebreak-worker`, PostgreSQL, Redis, RabbitMQ.
- VM 3: `wavebreak-node`.
- VM 4: Prometheus, Grafana, Loki, Tempo, Alertmanager, OpenTelemetry Collector.

Initial deployment uses Docker Compose plus systemd and Nginx. Kubernetes is intentionally out of scope for the MVP.

## Nginx

Use `wavebreak-infrastructure/nginx/wavebreak.conf.template` and substitute:

```text
WAVEBREAK_DOMAIN
```

Supported names:

- `www.<domain>`
- `api.<domain>`
- `admin.<domain>`
- `status.<domain>`
- `monitoring.<domain>`
- `tr.<domain>`
- `nl.<domain>`
- `fi.<domain>`

## Secrets

Set real production values for:

- `WAVEBREAK_DATABASE_URL`
- `WAVEBREAK_RABBITMQ_URL`
- `WAVEBREAK_REDIS_PASSWORD`
- `WAVEBREAK_JWT_SECRET`
- Laravel `APP_KEY`
- Grafana admin password

## Bootstrap

Apply migrations inside the Core image:

```bash
wavebreak-migrate
```

Create a first superadmin without manual SQL:

```bash
wavebreak-cli admin create --email admin@example.com --role superadmin
```

Create a node enrollment token:

```bash
wavebreak-cli node token --region TR --ttl 24h
```

Nodes should use `WAVEBREAK_NODE_ENROLLMENT_TOKEN` for first boot or `WAVEBREAK_NODE_API_TOKEN` after enrollment.
