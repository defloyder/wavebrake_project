package bridge

import (
	"fmt"
	"sync"

	"github.com/xjasonlyu/tun2socks/v2/engine"
)

// StartTun2Socks runs an in-process TUN-to-SOCKS5 bridge (MIT-licensed
// github.com/xjasonlyu/tun2socks) instead of the standalone libtun2socks.so
// binary the Kotlin side used to launch as a subprocess via ProcessBuilder.
// That worked initially but Android's platform-level "phantom process"
// killer terminates unrecognized child processes shortly after they start
// on stricter OEM builds (confirmed via on-device logcat: "Process
// PhantomProcessRecord {...:libtun2socks.so/...} died" a few seconds into
// an otherwise-successful connection) — the TUN interface stayed up with
// nothing left reading from it, which is exactly the "connected, but
// nothing loads" symptom for BOTH engines (they shared that one
// subprocess). Running the bridge as goroutines inside this already-
// running, already-foreground-service-registered process isn't a
// "process" Android's killer can see at all.
//
// fd is the raw TUN file descriptor from Android's
// VpnService.Builder.establish() — Kotlin must detach it
// (ParcelFileDescriptor.detachFd()) before calling this, handing this
// engine sole ownership; socksAddr is the local SOCKS5 proxy address
// (either engine's own — Bridge.start's returned port for Hysteria, or
// the fixed 127.0.0.1:1080 Xray-core's config always listens on).
var (
	tun2socksMu      sync.Mutex
	tun2socksRunning bool
)

func StartTun2Socks(fd int, mtu int, socksAddr string) error {
	tun2socksMu.Lock()
	defer tun2socksMu.Unlock()
	if tun2socksRunning {
		// See bridge.go's Start() for why this self-heals instead of
		// erroring.
		stopTun2SocksLocked()
	}

	key := &engine.Key{
		MTU:      mtu,
		Device:   fmt.Sprintf("fd://%d", fd),
		Proxy:    "socks5://" + socksAddr,
		LogLevel: "error",
	}
	engine.Insert(key)
	if err := engine.Start(); err != nil {
		return fmt.Errorf("start tun2socks: %w", err)
	}
	tun2socksRunning = true
	return nil
}

func StopTun2Socks() {
	tun2socksMu.Lock()
	defer tun2socksMu.Unlock()
	stopTun2SocksLocked()
}

func stopTun2SocksLocked() {
	if !tun2socksRunning {
		return
	}
	_ = engine.Stop()
	tun2socksRunning = false
}
