package bridge

import (
	"context"
	"net"
	"sync"

	"github.com/sagernet/sing/common/control"
	"github.com/xtls/xray-core/transport/internet"
)

// Android's VpnService captures ALL traffic from this app's own UID by
// default — including the outbound connections Xray-core/Hysteria make to
// the real remote server — unless each such socket is explicitly handed
// to VpnService.protect() before it connects. Without this, those
// sockets loop back into the very tunnel they're trying to feed: the TUN
// interface comes up, the app shows "Connected", but nothing ever
// actually reaches the internet (confirmed via on-device testing after
// ruling out every other layer — TUN, tun2socks, and both proxy engines
// each looked healthy in isolation).
//
// protectPath is a Unix domain socket path the Kotlin side listens on
// (see WaveEngineVpnService's protect server) and calls the real
// VpnService.protect(fd) for whatever fd arrives there. control.ProtectPath
// (github.com/sagernet/sing/common/control, GPLv3 — a transitive
// dependency of Xray-core itself already, via its own system_dialer.go;
// not something this app added) implements the client half of that
// protocol: it's a standard net.Dialer/net.ListenConfig `Control` hook
// that ships the connecting socket's fd over to protectPath and blocks
// until it's been protected.
var (
	protectOnce        sync.Once
	protectFunc        control.Func
	protectRegisterErr string
)

// SetProtectPath wires up socket protection for both engines. Call once,
// before Start or StartXray, with the same path the Kotlin protect server
// is listening on.
func SetProtectPath(path string) {
	protectOnce.Do(func() {
		protectFunc = control.ProtectPath(path)
		if err := internet.RegisterDialerController(protectFunc); err != nil {
			protectRegisterErr = err.Error()
		}
	})
}

// ProtectRegisterError reports why Xray-core's own outbound dialer might
// not be protecting its sockets — empty string means registration
// succeeded (which only means Xray-core ACCEPTED the hook, not that any
// particular connection actually used it).
func ProtectRegisterError() string {
	return protectRegisterErr
}

// protectedListenPacket is Hysteria's ConnFactory hook (see bridge.go) —
// Xray-core's own dialer goes through RegisterDialerController above
// instead, since Xray-core owns its dialer internally and doesn't expose
// a plain net.Dialer the way Hysteria's client.Config does.
func protectedListenPacket(ctx context.Context) (net.PacketConn, error) {
	lc := &net.ListenConfig{}
	if protectFunc != nil {
		lc.Control = protectFunc
	}
	return lc.ListenPacket(ctx, "udp", ":0")
}
