# Website Horizon design — 8 October 2026

Published to https://wavebreak.com.tr with turquoise and blue accents, a rotating
NASA Earth texture, glass surfaces and the original pointer-responsive wave.
Shared styling covers the homepage, pricing, technology, downloads and legal
pages. New visual copy is translated into Russian, English and Turkish.

The Earth renderer uses a single WebGL pass, a local 280 KB texture, lazy loading,
30 fps, offscreen/tab suspension and `prefers-reduced-motion`. A CSS sphere remains
available when JavaScript, WebGL or the texture is unavailable. The existing
`wavebreak-motion.js` and its wave interaction are unchanged.

## Verification

- Laravel: 25 tests passed, 415 assertions.
- Browser: 18 localized pages at widths 1440, 768, 390 and 320; no horizontal overflow.
- Navigation, mobile menu, Escape, FAQ and installer link targets checked.
- Rotation, reduced motion and no-JavaScript fallback checked; no JavaScript errors.
- Website container healthy after deployment; Core API `/readyz` returns `ready`.
- External HTTPS/browser checks passed for `/`, `/pricing`, `/access`, `/download`,
  `/en` and `/tr`; the new Earth renderer loaded successfully on each page.
- Production Windows and Android installer URLs both returned HTTP 200 with their
  original download sizes; no application JavaScript errors.

## Deployment and recovery

Only `wavebreak-web` was recreated. Existing installer downloads retain their bind
mount. API, worker, admin, database and transport containers were not recreated.

New image: `wavebreak-web:horizon-20261008`, also tagged
`wavebreak_pilot-wavebreak-web` for the existing Compose service.

Previous image: `wavebreak-web:horizon-before-20261008`.

Backup directory on the server:
`/home/wavebreakdeploy/wavebreak-pilot/backups/web-horizon-20261008-132244`.
Contains source templates, runtime templates and the previous image ID.

The running image had older metadata/translation differences compared with the
server checkout. The deployment applied only the design delta to that running
image, preserving its manifest URL and existing metadata behavior. The server
checkout also received the design files without removing its pre-existing changes.

To roll back the running website:

```sh
cd /home/wavebreakdeploy/wavebreak-pilot/current/wavebreak-infrastructure
docker tag wavebreak-web:horizon-before-20261008 wavebreak_pilot-wavebreak-web
docker compose --env-file .env.pilot -f docker-compose.yml -f docker-compose.pilot.yml -p wavebreak_pilot up -d --no-deps --no-build wavebreak-web
```

Before any subsequent rebuild after rollback, restore the backed-up source files
as well. The new image and backups remain available for recovery.
