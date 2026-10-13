# WaveBreak RU entry node — ready to deploy

Built and validated tonight (2026-10-08) against the real xray-core binary
(`Configuration OK` both server- and client-side). Not deployed anywhere
yet — waiting on a target IP.

## What it is

One Russia-hosted entry point exposing **three independent transports on
the same public IP, all multiplexed onto port 443** (non-standard ports
proved unreliable earlier tonight — Istanbul's own nginx config has the
exact same lesson baked into a comment):

1. **REALITY + XTLS Vision** (primary) — masquerades as a real external
   site (default `ya.ru`) with a genuine TLS1.3 handshake borrowed via
   REALITY; Vision randomizes packet shape/timing specifically against
   behavioral DPI (the "cuts the connection after ~20-30s of real traffic"
   pattern we hit tonight). Clients can actually present **any of several**
   SNI values (`REALITY_SERVER_NAMES` in `deploy.sh`, default `ya.ru`,
   `yandex.ru`, `mail.ru`, `vk.com`) against this one inbound — REALITY
   never presents a real certificate to the client (that's the whole
   trick), so the accepted SNIs don't need to share hosting with
   `REALITY_SNI` (the one site the server itself probes to borrow a
   handshake from). The deploy script prints a ready link per SNI; if one
   gets blocked on a given network, try another without redeploying
   anything.
2. **gRPC + TLS** (fallback) — HTTP/2-framed, real cert on a domain you
   control. No camouflage, but a different fingerprint than #1.
3. **WebSocket + TLS** (fallback) — the most broadly client-compatible of
   the three, same real cert.

All three forward everything to an existing WaveBreak foreign node (default:
Istanbul, `45.15.41.3:443`) for actual internet egress, since this node's
own country is where Telegram etc. are blocked — confirmed tonight that a
Russia-hosted exit cannot itself reach Telegram's DC IPs.

## Deploy

```
./deploy.sh <PUBLIC_IP> <OWN_DOMAIN> [REALITY_SNI] [CHAIN_IP] [CHAIN_PORT] [CHAIN_SNI] [HOP_ID]
```

- `PUBLIC_IP` — the new box's own IPv4.
- `OWN_DOMAIN` — a domain you already control, DNS-A'd to `PUBLIC_IP`
  (needed for #2/#3's real cert via certbot standalone — port 80 must be
  free). Doesn't need to look innocuous; it's never shown to anyone except
  as the SNI for the two non-camouflaged fallbacks. **Also DNS-A
  `ws.<OWN_DOMAIN>` to the same `PUBLIC_IP` before running this** — gRPC
  uses `OWN_DOMAIN` itself, WS uses that subdomain (same cert, one extra
  SAN). Found the hard way: nginx's SNI router dispatches purely by SNI
  string, so gRPC and WS can't share one — whichever got the map entry
  silently swallowed the other's traffic until this was split.
- Everything else has sane defaults (masquerade as `ya.ru`, chain to the
  existing Istanbul landing). Only override `CHAIN_*`/`HOP_ID` if deploying
  a fresh landing elsewhere instead of reusing Istanbul's.

Run as root on a fresh Debian/Ubuntu box. Installs Docker + certbot if
missing. Idempotent — safe to re-run.

On success it prints (and saves to `/opt/wavebreak-ru-entry/client-links.txt`)
three ready-to-paste `vless://` links, one per transport.

## Client config

`client-template.json` is the fuller option — real Xray-core (so Happ, not
our own sing-box-based apps), with an `observatory` health-check
(`leastPing`, pings every 10s like the reference config) and a `balancer`
that automatically prefers whichever of the three transports is currently
healthy, plus the same RU-domain-direct routing split as the proven
reference config (ya.ru/vk/mail/gosuslugi/wildberries/ozon/etc. bypass the
tunnel entirely). Fill in the six `__PLACEHOLDER__` values from the
deploy script's output before handing it to anyone.

**Caveat learned tonight**: Happ's "import by link" didn't reliably accept
either a raw full-JSON config or a hosted-URL subscription in our testing
on this specific network — but it did accept a bare `vless://...` string
pasted into that same field. If this template doesn't import cleanly,
fall back to the three separate links from `client-links.txt` pasted one
at a time; the user can then pick manually whichever one currently works,
which is strictly less convenient than automatic failover but was the one
import path confirmed working tonight.

## Before testing

Don't hammer one freshly-deployed IP with many different
protocols/reconnects in a short window — we have direct evidence tonight
(RU-MSK-01, `135.106.227.90`) that this pattern alone seems to tip a
carrier's behavioral filter against the IP, independent of which transport
is in use. Test each transport a handful of times, then wait, rather than
rapid-firing changes.
