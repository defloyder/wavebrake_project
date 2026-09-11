# WAVEBREAK Web

Laravel public website and user cabinet for WAVEBREAK.

The application calls `wavebreak-core` through HTTP only. It does not own or migrate Core tables.

## Local

```bash
composer install
php artisan serve --host=0.0.0.0 --port=8000
```

Set:

```text
WAVEBREAK_CORE_URL=http://localhost:8080
```
