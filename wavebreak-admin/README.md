# WAVEBREAK Admin

Laravel admin application for WAVEBREAK.

The application calls `wavebreak-core` through HTTP only. It does not own or migrate Core tables.

## Local

```bash
composer install
php artisan serve --host=0.0.0.0 --port=8002
```

Set:

```text
WAVEBREAK_CORE_URL=http://localhost:8080
```
