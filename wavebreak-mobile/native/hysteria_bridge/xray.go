package bridge

import (
	"fmt"
	"strings"
	"sync"

	"github.com/xtls/xray-core/core"

	// Deliberately NOT the usual github.com/xtls/xray-core/main/distro/all
	// blank-import bundle: it includes proxy/wireguard, whose WireGuard
	// tun implementation pulls in gvisor.dev/gvisor APIs that have, in the
	// past, conflicted with the gvisor version github.com/xjasonlyu/
	// tun2socks needs for its own in-process TUN bridge (see
	// tun2socks.go) — both modules share this one dependency graph. This
	// app never offers WireGuard as an outbound protocol anyway, so it's
	// left out rather than risk that fight again on a future upgrade.
	// Mandatory core features.
	_ "github.com/xtls/xray-core/app/dispatcher"
	_ "github.com/xtls/xray-core/app/proxyman/inbound"
	_ "github.com/xtls/xray-core/app/proxyman/outbound"
	// Fixes a dependency cycle caused by core import in the internet package.
	_ "github.com/xtls/xray-core/transport/internet/tagged/taggedimpl"

	// DNS, routing, policy — needed for the dns/routing blocks this app's
	// own config always sends (see share_link_config.dart).
	_ "github.com/xtls/xray-core/app/dns"
	_ "github.com/xtls/xray-core/app/log"
	_ "github.com/xtls/xray-core/app/policy"
	_ "github.com/xtls/xray-core/app/router"

	// Inbound/outbound proxies this app actually uses. blackhole is the
	// fixed "outbound3" in every config this app builds (see
	// share_link_config.dart) — needed even though nothing routes to it
	// by default, since Xray-core rejects the whole config at load time
	// if any listed outbound's protocol isn't a registered type.
	_ "github.com/xtls/xray-core/proxy/blackhole"
	_ "github.com/xtls/xray-core/proxy/freedom"
	_ "github.com/xtls/xray-core/proxy/shadowsocks"
	_ "github.com/xtls/xray-core/proxy/socks"
	_ "github.com/xtls/xray-core/proxy/trojan"
	_ "github.com/xtls/xray-core/proxy/vless/outbound"
	_ "github.com/xtls/xray-core/proxy/vmess/outbound"

	// Transports and their stream security.
	_ "github.com/xtls/xray-core/transport/internet/grpc"
	_ "github.com/xtls/xray-core/transport/internet/httpupgrade"
	_ "github.com/xtls/xray-core/transport/internet/reality"
	_ "github.com/xtls/xray-core/transport/internet/splithttp"
	_ "github.com/xtls/xray-core/transport/internet/tcp"
	_ "github.com/xtls/xray-core/transport/internet/tls"
	_ "github.com/xtls/xray-core/transport/internet/websocket"

	// JSON config loading — core.LoadConfig("json", ...) below needs the
	// "json" ConfigFormat registered, which only this package's init() does.
	_ "github.com/xtls/xray-core/main/json"
)

// The Hysteria2 crash this file exists to route around (see bridge.go's
// package comment) came from mixing two independently gomobile-bound Go
// runtimes in one Android process — flutter_v2ray's bundled Xray-core and
// this module's Hysteria client each carry their own copy of gomobile's
// go.Seq bridge, and the two turn out not to be binary-compatible with
// each other despite matching Java-level method signatures (confirmed via
// on-device logcat: both native libraries load fine, then the process
// dies with no Java exception the moment Hysteria's Go code actually
// calls into the shared go.Seq). Embedding Xray-core directly in THIS
// module — one gomobile binding, one go.Seq, no cross-binary calls —
// sidesteps that entirely. Xray-core is MPL-2.0 (Mozilla's own license,
// file-level copyleft): safe to depend on unmodified from a closed-source
// app, unlike sing-box's GPLv3.
var (
	xrayMu       sync.Mutex
	xrayInstance *core.Instance
)

// StartXray loads a full Xray JSON config (the same shape
// FlutterV2ray.parseFromURL(...).getFullConfiguration() already builds on
// the Dart side — inbounds/outbounds/dns/routing) and starts it. The
// config's own `inbounds[0]` is expected to be the local SOCKS5 proxy
// (flutter_v2ray's default config always includes one on 127.0.0.1:1080)
// — same shape Hysteria's bridge.go produces, so the Kotlin side can
// bridge either into tun2socks identically.
func StartXray(configJSON string) error {
	xrayMu.Lock()
	defer xrayMu.Unlock()
	if xrayInstance != nil {
		// See bridge.go's Start() for why this self-heals instead of
		// erroring: Kotlin's disconnect()->connect() sequencing across two
		// IPC hops doesn't guarantee the previous session actually torn
		// down before a new one starts.
		stopXrayLocked()
	}

	config, err := core.LoadConfig("json", strings.NewReader(configJSON))
	if err != nil {
		return fmt.Errorf("load config: %w", err)
	}
	instance, err := core.New(config)
	if err != nil {
		return fmt.Errorf("create instance: %w", err)
	}
	if err := instance.Start(); err != nil {
		return fmt.Errorf("start: %w", err)
	}
	xrayInstance = instance
	return nil
}

func StopXray() {
	xrayMu.Lock()
	defer xrayMu.Unlock()
	stopXrayLocked()
}

func stopXrayLocked() {
	if xrayInstance == nil {
		return
	}
	_ = xrayInstance.Close()
	xrayInstance = nil
}

func IsXrayRunning() bool {
	xrayMu.Lock()
	defer xrayMu.Unlock()
	return xrayInstance != nil
}
