package bridge

import "os"

// OpenFdCount reports how many file descriptors this process currently
// holds open (by counting /proc/self/fd entries — always readable for our
// own process, unlike another process's, which is why this lives here
// rather than being read from Kotlin directly). WaveEngineVpnService polls
// this periodically while connected and proactively reconnects (the same
// path a network change already triggers) if it climbs too high, rather
// than waiting to actually hit the process's fd limit and fail outright.
//
// The underlying leak (confirmed on-device: EMFILE — "Too many open
// files" — reached within minutes of ordinary browsing over an
// otherwise-healthy connection, climbing during steady-state traffic, not
// specifically tied to reconnects) lives somewhere in tun2socks' or
// Xray-core's own per-connection handling, both third-party. Chasing it
// down inside either isn't a scoped fix; capping the damage from the
// outside is.
func OpenFdCount() int {
	entries, err := os.ReadDir("/proc/self/fd")
	if err != nil {
		return -1
	}
	return len(entries)
}
