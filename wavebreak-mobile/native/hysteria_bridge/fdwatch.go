package bridge

import (
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"

	"github.com/xjasonlyu/tun2socks/v2/tunnel/statistic"
)

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
// Xray-core's own per-connection handling, both third-party. Where exactly
// is what [FdBreakdown] is for.
func OpenFdCount() int {
	entries, err := os.ReadDir("/proc/self/fd")
	if err != nil {
		return -1
	}
	return len(entries)
}

// FdBreakdown says what the open descriptors are and how many flows
// tun2socks is relaying, e.g.
// "fds=4012 socket=3900 file=78 anon=20 pipe=6 · flows tcp=1250 udp=40".
// Written to the engine log when the count runs high (15.10): a proxied
// flow holds ~3 sockets (tun2socks→SOCKS, the engine's accepted side, its
// outbound), so sockets ≈ 3×flows means flows that never end, and sockets
// far above that means sockets kept after their flow ended — two
// different leaks with two different fixes.
func FdBreakdown() string {
	entries, err := os.ReadDir("/proc/self/fd")
	if err != nil {
		return "fds unreadable: " + err.Error()
	}
	kinds := map[string]int{}
	for _, e := range entries {
		target, err := os.Readlink("/proc/self/fd/" + e.Name())
		if err != nil {
			kinds["gone"]++
			continue
		}
		kinds[fdKind(target)]++
	}
	tcp, udp := 0, 0
	for _, c := range statistic.DefaultManager.Snapshot().Connections {
		raw, err := json.Marshal(c)
		if err != nil {
			continue
		}
		var t trackerJSON
		if json.Unmarshal(raw, &t) != nil {
			continue
		}
		if t.Metadata.Network == "udp" {
			udp++
		} else {
			tcp++
		}
	}
	return fmt.Sprintf("fds=%d %s · flows tcp=%d udp=%d",
		len(entries), formatKinds(kinds), tcp, udp)
}

// fdKind names what a /proc/self/fd link points at.
func fdKind(target string) string {
	switch {
	case strings.HasPrefix(target, "socket:"):
		return "socket"
	case strings.HasPrefix(target, "pipe:"):
		return "pipe"
	case target == "anon_inode:[eventpoll]":
		return "epoll"
	case strings.HasPrefix(target, "anon_inode:"):
		return "anon"
	case strings.HasPrefix(target, "/dev/"):
		return "dev"
	default:
		return "file"
	}
}

// formatKinds lists the kinds largest first ("socket=3900 file=78 …").
func formatKinds(kinds map[string]int) string {
	names := make([]string, 0, len(kinds))
	for k := range kinds {
		names = append(names, k)
	}
	sort.Slice(names, func(i, j int) bool {
		if kinds[names[i]] != kinds[names[j]] {
			return kinds[names[i]] > kinds[names[j]]
		}
		return names[i] < names[j]
	})
	parts := make([]string, len(names))
	for i, k := range names {
		parts[i] = fmt.Sprintf("%s=%d", k, kinds[k])
	}
	return strings.Join(parts, " ")
}
