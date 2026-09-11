# WAVEBREAK Backup and Restore

## PostgreSQL Backup

```bash
cd wavebreak-infrastructure
WAVEBREAK_DATABASE_URL=postgres://... ./scripts/backup-postgres.sh
```

## PostgreSQL Restore

```bash
cd wavebreak-infrastructure
WAVEBREAK_DATABASE_URL=postgres://... ./scripts/restore-postgres.sh ./backups/wavebreak-postgres-YYYYMMDDHHMMSS.dump.gz
```

Backups support gzip compression, retention via `WAVEBREAK_BACKUP_RETENTION_DAYS`, and optional age encryption via `WAVEBREAK_BACKUP_AGE_RECIPIENT`.

## RabbitMQ

Keep queue topology declarative in code. RabbitMQ should be recoverable by replaying Core startup topology declaration and republishing any pending `outbox_events`.

## Redis

Redis stores ephemeral state only and does not require durable backup for the MVP.
