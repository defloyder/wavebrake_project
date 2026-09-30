// Package bridge is the gomobile bind surface WAVEBREAK's Android side
// calls into for Hysteria2. Xray-core (used for every other protocol via
// flutter_v2ray) never implemented Hysteria2 at all — it's not a missing
// setting, the protocol doesn't exist in that engine — and sing-box (which
// does support it) is GPLv3, which is not something to link into a closed
// -source app without that being a deliberate call by whoever owns the
// product. The upstream Hysteria2 project itself (github.com/apernet/
// hysteria) is MIT licensed, so this package wraps its `core/client`
// directly instead.
//
// It doesn't try to become a TUN device itself — Android only lets an
// unprivileged app own a TUN interface through VpnService, and only the
// Kotlin side can do that. What this exposes instead is a local SOCKS5
// proxy backed by the Hysteria connection, i.e. exactly the shape
// flutter_v2ray's own bundled tun2socks binary already expects from
// Xray-core's local SOCKS inbound (see V2rayVPNService.java's
// runTun2socks) — so the already-proven fd-handoff/tun2socks plumbing on
// the Kotlin side can be reused unmodified, just pointed at this port
// instead of Xray-core's.
package bridge

import (
	"context"
	"fmt"
	"net"
	"net/url"
	"strconv"
	"strings"
	"sync"

	hyclient "github.com/apernet/hysteria/core/v2/client"

	"wavebreak.app/cloak"
	"wavebreak.app/hysteria_bridge/socks5"
)

var (
	mu       sync.Mutex
	listener net.Listener
	hyClient hyclient.Client
	running  bool
)

// See the fixed-port comment inside Start() for why this can no longer be
// an ephemeral ":0" pick. Arbitrary, high, and distinct from
// XRAY_SOCKS_PORT (1080, WaveEngineVpnService.kt) even though the two
// engines are never active at once (stopOtherEngine) — no reason to make
// a future third caller reason about a shared port.
const localSocksPort = 17835

// Start parses a hysteria2:// or hy2:// share link, connects to the
// server (blocking until the handshake succeeds or fails — callers get a
// real yes/no, not just "the process started"), and opens a local SOCKS5
// listener wired to that connection. Returns the local port to hand to
// tun2socks, or an error if the link was malformed or the handshake
// failed (bad auth, unreachable server, TLS/cert rejection, ...).
func Start(link string) (int, error) {
	mu.Lock()
	defer mu.Unlock()
	if running {
		// Kotlin's disconnect()->connect() sequencing across two IPC hops
		// (Dart->Kotlin MethodChannel, then Kotlin->the VpnService via a
		// fire-and-forget startForegroundService Intent) doesn't guarantee
		// the previous session's stopAll() has actually finished by the
		// time a new one starts — confirmed on-device: switching servers
		// quickly could hit "hysteria bridge already running" and hang.
		// Self-heal instead of erroring: tear down the stale session first.
		stopLocked()
	}

	if _, err := parseLink(link); err != nil {
		return 0, fmt.Errorf("parse link: %w", err)
	}

	// Reconnectable, not a single NewClient connection (bugs 1/8): once
	// the one QUIC connection died (idle timeout or NAT rebinding while the
	// phone slept, a network switch) every new stream failed until the
	// Kotlin side restarted the whole engine — and nothing could tell it
	// to, because the old health check never saw the tunnel as dead. This
	// wrapper redials on the next TCP()/UDP() after the connection closes.
	// The config is rebuilt per dial so the server address is re-resolved
	// on the current network. Not lazy: Start still reports a failed first
	// handshake to the caller.
	client, err := hyclient.NewReconnectableClient(
		func() (*hyclient.Config, error) { return parseLink(link) },
		nil,
		false,
	)
	if err != nil {
		return 0, fmt.Errorf("connect: %w", err)
	}

	// Fixed local port, not an ephemeral ":0" pick — this is the one
	// change that makes a TUN-preserving reconnect possible for Hysteria2.
	// WaveEngineVpnService.kt's reconnectEngineOnly() restarts this client
	// (Bridge.stop() + Bridge.start()) on a network flap/health-check
	// failure/fd-count-high event WITHOUT ever touching the Android TUN
	// interface or the in-process tun2socks bridge (tun2socks.go). That
	// only works if tun2socks — which is pointed at whichever port the
	// FIRST Start() call returned, via engine.Key.Proxy, and is never told
	// about a new one afterward (confirmed by reading xjasonlyu/tun2socks'
	// own engine.go: the only way to change the proxy target is
	// engine.Stop()+Start() again, and Stop() unconditionally closes the
	// device — i.e. the TUN fd — so re-pointing tun2socks is exactly as
	// destructive as recreating TUN from scratch) — keeps dialing a port
	// this client is still actually listening on after the restart. An
	// ephemeral, different-every-time port would silently break that on
	// literally every automatic reconnect, leaving tun2socks dialing a
	// dead port forever with no TUN-preserving way to fix it. Both engines
	// need a stable local address for this to work: Xray-core's already is
	// (share_link_config.dart's config always listens on 127.0.0.1:1080),
	// this makes Hysteria2's match.
	ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", localSocksPort))
	if err != nil {
		_ = client.Close()
		return 0, fmt.Errorf("listen: %w", err)
	}

	srv := &socks5.Server{HyClient: client}
	go func() {
		// Serve returns once the listener is closed by Stop() — nothing
		// else to do with that error, the listener being gone is exactly
		// what a caller-initiated stop looks like.
		_ = srv.Serve(ln)
	}()

	listener = ln
	hyClient = client
	running = true
	return ln.Addr().(*net.TCPAddr).Port, nil
}

// Stop tears down the local SOCKS5 listener and the underlying Hysteria
// connection. Safe to call even if Start was never called or already
// failed.
func Stop() {
	mu.Lock()
	defer mu.Unlock()
	stopLocked()
}

// stopLocked is Stop()'s body, factored out so Start() can self-heal a
// stale "already running" state without recursively taking mu (which
// Stop() itself does).
func stopLocked() {
	if !running {
		return
	}
	_ = listener.Close()
	_ = hyClient.Close()
	listener = nil
	hyClient = nil
	running = false
}

// IsRunning reports whether a Hysteria connection + local SOCKS5 listener
// is currently active.
func IsRunning() bool {
	mu.Lock()
	defer mu.Unlock()
	return running
}

func parseLink(link string) (*hyclient.Config, error) {
	u, err := url.Parse(strings.TrimSpace(link))
	if err != nil {
		return nil, err
	}
	if u.Scheme != "hysteria2" && u.Scheme != "hy2" {
		return nil, fmt.Errorf("unsupported scheme: %s", u.Scheme)
	}
	host := u.Hostname()
	if host == "" {
		return nil, fmt.Errorf("link is missing a host")
	}
	port := u.Port()
	if port == "" {
		port = "443"
	}
	addr, err := net.ResolveUDPAddr("udp", net.JoinHostPort(host, port))
	if err != nil {
		return nil, fmt.Errorf("resolve %s:%s: %w", host, port, err)
	}

	q := u.Query()
	sni := firstNonEmpty(q.Get("sni"), q.Get("peer"), host)
	insecure := q.Get("insecure") == "1" || strings.EqualFold(q.Get("insecure"), "true")

	// cloak=1 wraps the QUIC socket in the traffic-shape masking layer
	// (see wavebreak-shared/cloak): random packet-size padding, jitter,
	// and idle chaff, on top of whatever TLS/obfs the link already does.
	// Built in response to a specific field finding (2026-09-30): the
	// handshake completed and then real proxied data reliably stalled
	// with "no recent network activity" the moment it started flowing,
	// identically whether or not salamander/gecko obfuscation was on —
	// i.e. something on the path was recognizing the *shape* of a tunnel
	// carrying real traffic, not the wire signature of Hysteria2/QUIC
	// itself. cloak targets that shape directly. Off by default: it costs
	// some throughput (padding overhead, an idle chaff trickle) that
	// locations without this specific problem shouldn't pay.
	cloakEnabled := q.Get("cloak") == "1" || strings.EqualFold(q.Get("cloak"), "true")
	cloakProfile := cloak.DefaultProfile
	if v := q.Get("cloak-min"); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			cloakProfile.MinSize = n
		}
	}
	if v := q.Get("cloak-max"); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			cloakProfile.MaxSize = n
		}
	}
	if v := q.Get("cloak-chaff-min-ms"); v != "" {
		if n, err := strconv.ParseInt(v, 10, 64); err == nil {
			cloakProfile.ChaffMinInterval = n
		}
	}
	if v := q.Get("cloak-chaff-max-ms"); v != "" {
		if n, err := strconv.ParseInt(v, 10, 64); err == nil {
			cloakProfile.ChaffMaxInterval = n
		}
	}

	// hysteria2:// links carry the auth password as the URI's userinfo —
	// url.Parse puts a bare `password@host` into Username() (there's no
	// colon to split on), and a `user:pass@host` shape into
	// Username()+Password(). Username()/Password() already give the
	// percent-decoded raw values, unlike Userinfo.String() which
	// re-encodes them — using String() here would send Hysteria a
	// mangled password for anything with special characters in it.
	auth := u.User.Username()
	if pass, ok := u.User.Password(); ok {
		auth = auth + ":" + pass
	}

	return &hyclient.Config{
		ServerAddr: addr,
		Auth:       auth,
		TLSConfig: hyclient.TLSConfig{
			ServerName:         sni,
			InsecureSkipVerify: insecure,
		},
		// Without this, Hysteria's QUIC socket is an ordinary unprotected
		// UDP socket — Android's VpnService captures it right back into
		// this app's own tunnel instead of letting it reach the real
		// server. See protect.go for the full explanation.
		ConnFactory: hyConnFactory{cloakEnabled: cloakEnabled, cloakProfile: cloakProfile},
	}, nil
}

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
	// remote is the server address Hysteria is about to dial — cloak.Conn
	// needs it up front to send chaff to the right peer even before the
	// real handshake traffic starts flowing.
	return cloak.NewConn(conn, remote, f.cloakProfile), nil
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if v != "" {
			return v
		}
	}
	return ""
}
