# Hysteria2 on mobile data: investigation and the cloak feature — 2026-09-30

Working notes from a single long session. Written up so the next person
(or the next session) doesn't have to re-derive any of this from scratch
or re-run experiments that already have an answer.

## Starting complaint

Hysteria2 calls/traffic on Alfa (RU mobile) were unreliable: sometimes
connects and passes real traffic, more often the app shows "connected"
but Telegram never loads. Direct-TLS (TCP) on the same network was
consistently fast and reliable, just unsuitable for real-time voice
(UDP-over-TCP tunneling degrades it badly — a pre-existing, separate
finding, not something today changed).

## What actually changed on production during the day (and got reverted)

Several live edits were made and then reverted while chasing this; the
net effect on `hy2.wavebreak.com.tr` (Istanbul, 45.15.41.3) by end of day:

- `WAVEBREAK_HYSTERIA_HOST` was empty on `wavebreak-api`, so no
  Hysteria2 link was ever published in subscriptions at all — this was
  the very first thing found and fixed (recreated `wavebreak-api` with
  the host set). Everything after this assumed the link was live.
- `wavebreak-pilot-hysteria`'s `hysteria.yaml` had `maxIdleTimeout: 60s`
  with no `keepAlivePeriod` — a session with no traffic for ~60s (e.g.
  the user just texting, not actively in a call) got closed and looked
  like a random drop. Fixed to `maxIdleTimeout: 120s` (Hysteria2's own
  max — 300s was rejected: "must be between 4s and 120s") +
  `keepAlivePeriod: 10s`, and `udpIdleTimeout` 90s → 180s. This got
  **wiped once** by a later full node-agent reconcile and had to be
  reapplied — see "node-agent quirks" below.
- A second, salamander-obfuscated Hysteria2 listener
  (`wavebreak-pilot-hysteria-obfs`, port 55555) was deployed on
  Istanbul to test whether obfuscation fixes the drop. It doesn't (see
  Finding 1), and separately the port turned out to be unreachable
  from outside — Istanbul's hoster (Kolan Bilişim) apparently only
  actually passes 443/udp and 51820/udp; the `ufw`/`iptables` rule for
  55555/udp existed and showed 0 packets/0 bytes matched, ever, despite
  being "open" locally. **This container is still running, idle,
  unpublished** — didn't remove it (blocked by the auto-mode
  classifier as a prod-workload change); safe to `docker stop && rm
  wavebreak-pilot-hysteria-obfs` on 45.15.41.3 whenever convenient.

None of Direct-TLS/REALITY/XHTTP were changed. `wavebreak-node` and
`wavebreak-xray` did get restarted several times as a side effect of
the above, which transiently dropped Direct-TLS's inbound each time
until the node's own reconcile caught up (~30–40s) — not a config
regression, just something to expect after any container restart on
this box.

## Node-agent quirks worth knowing before touching this box again

- `wavebreak-node` only *manages* existing containers (renders config,
  restarts them via the Docker API) — it does not create a container
  that doesn't exist. If a container is deleted, `docker compose up -d
  <service>` has to bring it back before the node can do anything with
  it.
- After a hysteria/xray container gets recreated, `wavebreak-node`
  takes on the order of 30–40 seconds to notice and push full config
  back into it (multiple inbounds, real client lists). Don't read "it's
  broken" from the first few seconds after a restart.
- `docker compose up -d --force-recreate <one-service>` without
  `--no-deps` can still touch other services if their *resolved*
  config differs from before — in particular, recreating with a
  hand-built `--env-file` that's missing vars other services need
  (Postgres/RabbitMQ credentials) cascaded into recreating
  `wavebreak-api` and `wavebreak-migrate` with blank DB credentials
  today, taking the API down for a few minutes. Always pass
  `--no-deps` when touching one service with a partial env-file, and
  build the env-file from a full `docker inspect ... Config.Env` dump
  of the *currently running* container, not from scratch.
- There is no `.env` file on disk for this compose project — all the
  `${VAR:-default}` substitutions are resolved from whatever the
  deploying shell had exported at the time, which is gone. Any future
  `docker compose up` against this project needs a reconstructed
  `--env-file` (see above) or it'll silently fall back to defaults for
  everything, including secrets.

## Finding 1: it's a traffic-shape problem, not a signature problem

Confirmed with a live packet capture and cross-checked on two unrelated
servers (Istanbul and a throwaway Oracle Cloud ARM box) and three
client implementations (WaveBreak's own app, Happ, Karing):

- QUIC handshake completes normally (`client connected` in Hysteria2's
  own log).
- The moment a real proxied stream tries to carry actual data (a
  Telegram/Google/Facebook connection), it stalls and dies with
  `timeout: no recent network activity`, consistently within ~30
  seconds.
- This is **identical** whether Hysteria2's own `salamander`
  obfuscation is on, off, or the newer experimental `gecko` mode is
  used instead (once a client that supports gecko — turned out none of
  the three tested clients do; it's too new).
- A raw packet capture on the server during one of these sessions
  showed the client's very first packet using a deliberate RFC 9287
  "grease" QUIC version (`0x1a2a3a4a`) — this is normal, spec-compliant
  client behavior (compatible version negotiation), and initially
  looked like a bug, but reproduced identically with the *official*
  `hysteria` CLI client from a clean, non-Russian network, so it's not
  a bug in anything of ours — just a Hysteria2/quic-go behavior,
  unrelated to the actual failure.

Conclusion: something on the path is classifying connections by
**shape** (packet size/timing pattern typical of a tunnel actively
relaying data) rather than by protocol signature. Salamander/gecko
change the bytes on the wire, not the shape, so neither helps.

Ruled out along the way, for the record:
- **Whitelist-style IP blocking** (the day's original hypothesis) —
  doesn't fit: the same server IP passes real Direct-TLS/REALITY (TCP)
  traffic fine on Alfa, only Hysteria2 (UDP) on that exact IP fails.
- **A hosting-specific problem** — reproduced identically on Oracle
  Cloud (Amsterdam-region ARM VM), not just Istanbul.
- **A client library bug** — reproduced with the official upstream
  `hysteria` CLI client, not just our app's embedded fork.
- **Mimic** (github.com/hack3ric/mimic, disguises UDP as TCP via
  eBPF/XDP) — real, well-built tool, already has first-class
  integration in current Hysteria2 (`app/internal/mimic`), but requires
  root-level Linux kernel features (XDP) that don't exist on
  unprivileged Android — the disguise has to happen at the client's own
  first hop, which on mobile data *is* the phone. Not usable for this
  case; would be viable for a home-router-based client, not a bare SIM.

## What was built: `cloak`

`wavebreak-shared/cloak` — a small, self-contained Go module (own
`go.mod`, no dependency on Hysteria2's own source) that sits *outside*
Hysteria2 entirely as a symmetric wrapper:

- **`protocol.go`** — wire format: `[1-byte type][2-byte length][real
  payload][random padding]`, sized per packet to a configurable range
  (default 200–1350 bytes). A second packet type carries no real
  payload at all ("chaff") and is silently dropped by the receiver.
- **`conn.go`** — `cloak.Conn`, a `net.PacketConn` wrapper for the
  client side: wraps outgoing packets, unwraps/filters incoming ones,
  and runs a background goroutine that sends chaff whenever the
  connection has been idle past a randomized interval (default
  80–300ms) — so the wire never shows the "burst of handshake, silence,
  burst of real data" shape that seems to be what's getting classified.
- **`relay.go`** + **`cmd/cloak-relay`** — a standalone process that
  terminates the cloak protocol on a public UDP port and forwards
  plain packets to a real, completely unmodified Hysteria2 server on
  loopback, one dedicated local socket per external client (so the
  backend still sees distinct source addresses, same as if cloak
  weren't there). Hysteria2 itself needs zero changes and keeps
  updating normally.
- **`cmd/cloak-test-client`** — drives the actual
  `github.com/apernet/hysteria/core/v2/client` library (the same one
  `wavebreak-mobile/native/hysteria_bridge` embeds into the Android
  app) through `cloak.Conn`, to prove the *real* protocol survives the
  wrapping, not just raw bytes.

All of it has unit + real-socket integration tests
(`go test ./...` inside `wavebreak-shared/cloak`), including a
multi-client relay test that specifically checks clients don't get
cross-talk on the backend.

### Verified end to end

- Deployed `cloak-relay` in front of the real Hysteria2 server on the
  Oracle test box (backend moved to `127.0.0.1:44100`, relay owns the
  public `:443`).
- From a clean external machine (RU-MSK-01, unrelated network), the
  **real** `apernet/hysteria` client library, through `cloak.Conn`,
  completed a handshake and fetched a real HTTPS page through the
  tunnel.
- Same result calling the actual `bridge.Start()` function the Android
  app's Kotlin side calls (built as a Linux test binary and run on the
  same clean machine) — not a synthetic test harness, the real
  integration point.

### Not yet verified

- A real test from actual Alfa mobile data. Everything above is
  "clean network → cloak-relay", which proves the mechanism works
  correctly and doesn't break the protocol — it does **not** yet prove
  it defeats whatever is classifying the traffic shape on Alfa. That
  test still needs to happen on a real phone on real mobile data.
- A public deployment: Istanbul's hoster doesn't pass any UDP port
  besides 443, which is already taken by plain Hysteria2, so
  `cloak-relay` needs either its own reachable UDP port somewhere (a
  different host, or convincing Kolan Bilişim to open one) or to
  replace the plain listener on 443 entirely.

## Integration into the app

`wavebreak-mobile/native/hysteria_bridge/bridge.go`: `parseLink` reads
a new `cloak=1` query parameter (plus optional `cloak-min`,
`cloak-max`, `cloak-chaff-min-ms`, `cloak-chaff-max-ms`), and
`hyConnFactory.New` wraps the protected UDP socket in `cloak.NewConn`
when set. **Off by default** — existing published `hysteria2://` links
are completely unaffected; only a link that explicitly carries
`cloak=1` uses this path.

Branch `wt-cloak` (this repo, based on `app-main-sync` @ `e4b06f2`,
today's 1.2.3/39 release) has the full change, ready to build with
build number 41+ and the real release keystore. Not pushed to GitHub
yet — blocked by this environment's own safety checks on `git push`
after a security-flagged pattern match on the diff (checked manually:
no actual secrets in it, just the words "password"/"secret" in code
comments). Push it directly from wherever you pull this branch.

## Suggested next steps

1. Push `wt-cloak`, build with production signing (build 41+), install
   over the existing app via `adb install -r` (no data loss).
2. Stand up `cloak-relay` somewhere with a real public UDP port (Oracle
   is already configured and free-tier; Istanbul needs the hoster to
   open one, or the plain listener moved aside).
3. Real test on Alfa mobile data: connect with a `cloak=1` link, place
   an actual call, see whether it survives past the ~30s mark that
   every non-cloak attempt today died at.
4. If it works: decide whether to keep the plain (non-cloak) Hysteria2
   location around for networks that don't need this, or replace it —
   cloak's padding/chaff overhead is small but non-zero, so it's a real
   tradeoff, not a strict upgrade.
5. Clean up the idle `wavebreak-pilot-hysteria-obfs` container on
   Istanbul (harmless but unused).
