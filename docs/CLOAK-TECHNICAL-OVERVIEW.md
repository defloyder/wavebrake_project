# How `cloak` works — technical overview

Written for whoever needs to port, maintain, or extend this feature without
re-deriving it from scratch. Covers what problem it solves, the exact wire
protocol, every integration point on client and server, and the current
production state.

## The problem it solves

Hysteria2 (QUIC-based) connections on some RU mobile carriers (confirmed:
Alfa, MegaFon) complete their handshake normally, then die within ~30-40
seconds the moment real proxied data starts flowing, with
`timeout: no recent network activity`. This was confirmed (2026-09-30
investigation, see `docs/2026-09-30-hysteria-investigation-and-cloak.md`) to
be **traffic-shape classification**, not signature detection:

- Identical failure with Hysteria2's own `salamander` obfuscation on, off, or
  the newer `gecko` mode — changing the bytes on the wire doesn't help.
- Reproduced on two unrelated servers and three client implementations
  (WaveBreak's own app, Happ, Karing, and the official `hysteria` CLI).
- Something on the path recognizes the *pattern* of a tunnel actively
  relaying real data (packet size/timing signature) rather than any
  protocol-specific byte signature.

`cloak` targets that shape directly: it randomizes packet sizes and injects
idle "chaff" traffic so the wire never shows the "quiet handshake, then
burst of real data" pattern that appears to be what's getting flagged.

## Wire protocol (`wavebreak-shared/cloak/protocol.go`)

Every UDP datagram cloak sends is wrapped:

```
[1-byte type][2-byte length][real payload][random padding]
```

- `typeData byte = 0x17` — carries a real payload (length-prefixed), with
  random padding appended after it up to a size randomly chosen within
  `[Profile.MinSize, Profile.MaxSize]` (default **200–1350 bytes**). The
  padding is there purely to vary the datagram's on-wire size so it doesn't
  correlate with the real payload's actual size.
- `typeChaff byte = 0x2c` — no real payload at all, pure padding. Sent on a
  timer (see below) during idle periods, and silently dropped by whichever
  end receives it (`Unwrap()` returns `chaff=true`, caller discards).

`Wrap(profile, payload)`, `WrapChaff(profile)`, `Unwrap(pkt) (payload, chaff,
err)` are the three functions that do this; `headerSize = 3`.

`Profile{MinSize, MaxSize, ChaffMinInterval, ChaffMaxInterval}` —
`DefaultProfile = {200, 1350, 80, 300}` (sizes in bytes, intervals in ms).

## Client side (`wavebreak-shared/cloak/conn.go`)

`cloak.Conn` wraps an existing `net.PacketConn` (the real, already-protected
UDP socket) and implements `net.PacketConn` itself, so it's a drop-in
replacement wherever the underlying socket was used directly:

- `WriteTo(p, addr)` — wraps `p` via `protocol.Wrap` before sending.
- `ReadFrom(buf)` — reads the real underlying socket, calls `Unwrap`; if the
  packet is chaff, it's discarded and the read loops to the next packet
  (transparent to the caller — they never see chaff).
- A background goroutine (`chaffLoop`) sends a chaff packet to `remote`
  whenever the connection has been idle longer than a randomized interval
  picked fresh each time within `[ChaffMinInterval, ChaffMaxInterval]`. This
  is what keeps the wire "alive-looking" during gaps instead of going
  silent then bursting — the specific shape that seems to get flagged.
- `remote net.Addr` is required up front (passed at construction) so chaff
  has somewhere to go even before the real Hysteria2 handshake starts.

`NewConn(underlying net.PacketConn, remote net.Addr, profile Profile) *Conn`
is the only constructor; starts the chaff goroutine immediately.

## Server side (`wavebreak-shared/cloak/relay.go` + `cmd/cloak-relay`)

A **separate standalone process**, not a Hysteria2 patch — Hysteria2 itself
is completely unmodified and keeps updating normally:

- `Relay` owns the public UDP port (e.g. `:443`) and a `backend net.UDPAddr`
  (the real Hysteria2 server, reachable only on loopback, e.g.
  `127.0.0.1:44100`).
- For each distinct external client address it sees, it opens a **dedicated
  loopback socket** to the backend and pumps traffic both ways
  (`pumpBackendReplies` per peer) — so Hysteria2 still sees distinct source
  addresses per client, exactly as if cloak weren't there at all. Peers idle
  longer than `PeerIdleTimeout` are cleaned up (`cleanupLoop`).
- Incoming packets from the public side are `Unwrap()`'d (chaff dropped,
  real payload forwarded raw to the backend); outgoing replies from the
  backend are `Wrap()`'d before being sent back to the external client. Each
  peer also runs its own `chaffPeer` goroutine so chaff flows in both
  directions, not just client→server.
- `cmd/cloak-relay/main.go` is the CLI entrypoint: flags `-listen`,
  `-backend`, `-min-size`, `-max-size`, `-chaff-min-ms`, `-chaff-max-ms`.

**Current production deployment** (Istanbul, `45.15.41.3`, 2026-10-01):
`cloak-relay` runs as a systemd service (`/etc/systemd/system/cloak-relay.service`,
enabled, `ExecStart=/usr/local/bin/cloak-relay -listen :443 -backend
127.0.0.1:44100`), with Hysteria2 itself moved off the public port onto
`127.0.0.1:44100` (`listen: 127.0.0.1:44100` in `hysteria.yaml`, rendered by
`wavebreak-node`). This means **every Hysteria2 client hitting this server's
public 443/udp must speak cloak now** — a plain, non-cloak Hysteria2 client
gets nothing back (its raw packets fail `Unwrap()` and are dropped), and a
cloak-enabled client with `cloak=1` connects exactly as before cloak existed
from Hysteria2's point of view, just with the shape-masking in between.
Confirmed in production: a test session with `cloak=1` held **1m40s+ with
zero drops**, versus every prior plain session dying at ~30-40s.

## Client integration — Android (done, shipped)

**File:** `wavebreak-mobile/native/hysteria_bridge/bridge.go` — a Go package
compiled via `gomobile bind` into the native library the Android app's
Kotlin/Dart side calls (`Bridge.Start(link)`/`Bridge.Stop()`). It wraps
`github.com/apernet/hysteria/core/v2/client` directly (chosen over sing-box
specifically because sing-box is GPLv3 and this is closed-source).

`parseLink()` reads the share link's query string and recognizes:
- `cloak=1` (or `true`) — turns cloak on for this connection. **Off by
  default** — an ordinary `hysteria2://...` link with no `cloak` param
  behaves exactly as before; only a link explicitly carrying `cloak=1` uses
  this path.
- `cloak-min`, `cloak-max`, `cloak-chaff-min-ms`, `cloak-chaff-max-ms` —
  optional overrides of `cloak.DefaultProfile`'s four fields. Usually left
  at defaults.

The actual wrap happens in `hyConnFactory`, the `hyclient.Config.ConnFactory`
implementation that's already responsible for producing the OS-protected UDP
socket (so Android's VpnService doesn't capture Hysteria2's own QUIC socket
back into the tunnel — see `protect.go`):

```go
type hyConnFactory struct {
    cloakEnabled bool
    cloakProfile cloak.Profile
}

func (f hyConnFactory) New(remote net.Addr) (net.PacketConn, error) {
    conn, err := protectedListenPacket(context.Background())
    if err != nil {
        return nil, err
    }
    if !f.cloakEnabled {
        return conn, nil
    }
    return cloak.NewConn(conn, remote, f.cloakProfile), nil
}
```

`wavebreak-mobile/native/hysteria_bridge/go.mod` pulls in cloak as a local
module: `require wavebreak.app/cloak v0.0.0-...` +
`replace wavebreak.app/cloak => ../../../wavebreak-shared/cloak` (not a
published dependency — lives in this same repo).

This is the **only** change to existing, already-shipped code — everything
else about the bridge (the `NewReconnectableClient` pattern, the fixed local
SOCKS port for TUN-preserving reconnects, etc.) is untouched.

## What's NOT done yet

- **Windows/PC client** — not integrated. See the companion handoff doc for
  the concrete plan, since the PC app's native bridge architecture needs
  confirming before writing the integration (may or may not share the exact
  same `hysteria_bridge` Go source as Android — if it does, this could be as
  small as adding a new build target rather than new integration code).
- **Server-side rollout beyond Istanbul** — `cloak-relay` is only deployed
  on the one Istanbul box. Any other Hysteria2 location would need the same
  treatment (move Hysteria2 to loopback, run `cloak-relay` in front) before
  a `cloak=1` link pointed at it would work.
- **Making `cloak=1` the default in published links** — today it's strictly
  opt-in; nothing in production currently hands out a `cloak=1` link
  automatically. That's a deliberate separate decision (see
  `docs/HANDOFF-cloak-rollout.md`) since flipping it affects every existing
  user's link at once.
