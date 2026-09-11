# WAVEBREAK RabbitMQ Topology

Exchanges:

- `wavebreak.events`
- `wavebreak.jobs`
- `wavebreak.deadletter`

Queues:

- `wavebreak.jobs.notification`
- `wavebreak.jobs.subscription`
- `wavebreak.jobs.node`
- `wavebreak.jobs.access`

Dead letter queues:

- `wavebreak.deadletter.notification`
- `wavebreak.deadletter.subscription`
- `wavebreak.deadletter.node`
- `wavebreak.deadletter.access`

Routing keys currently emitted by Core:

- `subscription.activated`
- `node.online`
- `access.created`

Core writes events to `outbox_events` inside the same PostgreSQL transaction as the domain mutation. `wavebreak-worker` publishes pending outbox events to RabbitMQ and marks them published after RabbitMQ acknowledges the publish call.

Pass 1 hardening:

- Exchanges and queues are durable.
- Messages are persistent.
- Publisher confirms are enabled before `outbox_events.published_at` is set.
- Failed publish attempts update `attempts` and schedule the next attempt with bounded exponential backoff.
