# WAVEBREAK Roadmap

1. Add admin MFA, recovery codes UI, and audit review workflows.
2. Add fine-grained RBAC management endpoints and Laravel Admin screens.
3. Add Core integration tests with PostgreSQL, Redis, and RabbitMQ containers.
4. Add real billing provider adapters and webhook idempotency tests.
5. Generate Go database access with sqlc from checked-in query files.
6. Add WireGuard and Outline protocol adapters in `wavebreak-node`.
7. Add full OpenTelemetry traces around HTTP, PostgreSQL, Redis, and RabbitMQ.
8. Add Grafana dashboards for Core, Nodes, HTTP API, RabbitMQ, PostgreSQL, Redis, and Infrastructure.
9. Split MVP Compose into VM-specific production Compose files.
10. Add PostgreSQL PITR, restore drills, container scanning, and deployment promotion gates.
