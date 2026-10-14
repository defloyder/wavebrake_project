# Adding a node as a second location ("mirror") — the real procedure

Written after RU-LTE-01 took way longer than it should have to show up for
subscribers, because the actual deployed logic for this isn't on `main` at
all, and the public_config has a non-obvious required flag. This doc exists
so that never happens again.

## Branch reality check (read this first)

**`main` is stale relative to what's actually deployed.** The real, running
source lives in separate snapshot/sync branches:

- `prod-core-snapshot` — what's actually deployed for wavebreak-core.
- `app-main-sync` — what's actually shipped in the mobile app.
- `server-admin-snapshot` — what's actually deployed for wavebreak-admin.

Before debugging ANY "why doesn't X show up" question against this codebase,
check the relevant `*-snapshot`/`*-sync` branch, not `main`. Evidence this
bit us concretely: `main`'s `wavebreak-mobile` still has `bundled_locations.dart`
(a hardcoded 3-link list, removed from the real app in "Bug 10"), its
`subscription_section.dart` titles the card "WAVEBREAK Plus" where the real
app says "WAVEBREAK Flagship", and `main`'s Core doesn't even have the
`shares_grants_of`/mirror-node mechanism at all — that's only in
`prod-core-snapshot`.

## What actually decides whether a node is visible to subscribers

It is **not** `/v1/locations` (that's the ADMIN listing, explicitly
"without mirror nodes" per its own code comment) and it is **not** simply
having active `access_grants` rows on the node. The real app, and the
public subscription endpoint (`GET /v1/sub/{grantID}`, what a share link
points to), both build their link list from `POST /v1/me/access`'s
underlying logic: one primary `AccessGrantConfig` per account, plus
`mirrorConfigs()` which walks `nodes.shares_grants_of`.

## The correct procedure (and only this procedure)

Use the actual admin tool — don't hand-write SQL, it's easy to get subtly
wrong in ways that silently produce zero visible effect:

```
wavebreak-cli node mirror --node=<NEW_NODE_CODE> --of=<PRIMARY_NODE_CODE> --config=<path-to-json>
```

Run it via `docker exec` into the already-running `wavebreak-api` container
(it already has the right DB credentials loaded — don't use
`docker compose run`, the compose file's own env defaults are stale and
don't match the real deployed secrets).

The `--config` JSON must be shaped as `config.VLESSConfig`
(`wavebreak-core/internal/config/config.go`, no json tags — field names
matched case-insensitively). At minimum:

```json
{
  "LinkName": "🇷🇺 Friendly Name",
  "PublicHost": "<public IP or domain>",
  "PublicPort": 443,
  "PublishDirect": true,
  "RealityShortID": "...",
  "RealityPublicKey": "...",
  "RealityServerName": "..."
}
```

**`PublishDirect: true` is required** if REALITY is the transport you want
published — without it, `applyVLESSRuntimeConfigFor` silently builds ZERO
links for that mirror (no error, no warning, it just doesn't show up
anywhere, for anyone). This is the single thing that wasted the most time.
If the node instead serves Direct-TLS/CDN-WS/CDN-XHTTP, the matching
`DirectTLSHost`/`CDNHost` etc. fields gate those instead — same silent-zero
behavior if they're half-set.

## Verifying it worked (do this, don't just trust the CLI's success message)

The CLI succeeding only means the DB write succeeded — it says nothing
about whether the resulting config actually renders a link. Verify with a
real, disposable public read:

```
curl -s https://api.wavebreak.com.tr/v1/sub/<any real grant ID on the primary node> | base64 -d
```

This is a public, unauthenticated endpoint by design (that's the whole
point of a subscription link) — reading it is not a production-data risk,
and it shows you exactly what a real client would get. Confirm the new
node's link is present before telling anyone it's fixed.

## Don't bother with

- Cloning `access_grants` rows per-user onto the new node — the real
  mechanism doesn't read grants per-mirror-node that way, it derives the
  mirror's link from the PRIMARY node's single grant at request time. This
  wastes effort and leaves harmless-but-confusing extra rows behind.
- Touching `nodeCities` in `wavebreak-core/internal/httpapi/product.go` —
  that map is a leftover cosmetic fallback for the admin-only `/v1/locations`
  view, not what subscribers see. The actual display name is
  `public_config.LinkName`, set via the same `node mirror` command above.
