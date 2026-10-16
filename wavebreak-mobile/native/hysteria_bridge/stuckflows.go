package bridge

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/xjasonlyu/tun2socks/v2/tunnel/statistic"
)

// Stuck connections (owner, 13.10): Telegram kept "connecting" and a
// Google search hung until the app was switched or the VPN reconnected,
// while a fresh connection through the same tunnel worked at once. The
// local SOCKS proxy (Xray) accepts a connection before its own upstream
// is up, and keeps one that gets no answer for up to 5 minutes (its idle
// timeout), so an app whose request went nowhere just waits. This finds
// TCP connections whose app is waiting for a reply that is not coming and
// closes them: the app sees the connection end and redials at once — what
// switching apps or reconnecting did by hand — and every other
// connection is left alone.
//
// "Waiting" is strict, so a quiet but healthy connection is never cut
// (Telegram acknowledges messages and expects nothing back):
//   - opened, the app spoke first (TLS hello, HTTP request, MTProto) and
//     not one byte came back for openSec; or
//   - the app sent two or more separate bursts (a request, then a retry
//     or a ping) with no reply: the first silentSec ago, the last at
//     least 10 s ago.
// Big uploads are skipped (more than 32 KB sent while waiting).

type flowSeen struct {
	up, down  int64
	waitSince time.Time // first unanswered bytes since the last reply
	lastUp    time.Time
	bursts    int
	sentWait  int64
	lastSeen  time.Time
}

var (
	flowsMu sync.Mutex
	flows   = map[string]*flowSeen{}
)

type trackerJSON struct {
	ID       string    `json:"id"`
	Start    time.Time `json:"start"`
	Upload   int64     `json:"upload"`
	Download int64     `json:"download"`
	Metadata struct {
		Network string `json:"network"`
		DstIP   string `json:"destinationIP"`
		DstPort uint16 `json:"destinationPort"`
	} `json:"metadata"`
}

const (
	stuckMaxSent   = 32 * 1024
	stuckBurstGap  = 3 * time.Second
	stuckLastQuiet = 10 * time.Second
)

// CloseStuckFlows closes the TCP connections whose app is waiting in vain
// (see above) and returns what it closed, "" when nothing — e.g.
// "2: 149.154.167.51:443 31s, 142.250.1.1:443 17s". Call it every few
// seconds: it learns each connection's progress between calls.
func CloseStuckFlows(openSec, silentSec int64) string {
	now := time.Now()
	openWait := time.Duration(openSec) * time.Second
	silent := time.Duration(silentSec) * time.Second
	type closer interface{ Close() error }
	var closed []string

	flowsMu.Lock()
	defer flowsMu.Unlock()
	for _, c := range statistic.DefaultManager.Snapshot().Connections {
		raw, err := json.Marshal(c)
		if err != nil {
			continue
		}
		var t trackerJSON
		if json.Unmarshal(raw, &t) != nil || t.Metadata.Network != "tcp" {
			continue
		}
		f := flows[t.ID]
		first := f == nil
		if first {
			f = &flowSeen{}
			flows[t.ID] = f
		}
		f.lastSeen = now
		if t.Download > f.down {
			f.waitSince, f.lastUp = time.Time{}, time.Time{}
			f.bursts, f.sentWait = 0, 0
		} else if t.Upload > f.up {
			switch {
			case f.waitSince.IsZero():
				f.waitSince, f.bursts = now, 1
				// Seen for the first time, nothing back yet: it has
				// been waiting since it was opened.
				if first && t.Download == 0 {
					f.waitSince = t.Start
				}
			case now.Sub(f.lastUp) >= stuckBurstGap:
				f.bursts++
			}
			f.lastUp = now
			f.sentWait += t.Upload - f.up
		}
		f.up, f.down = t.Upload, t.Download
		if f.waitSince.IsZero() || f.sentWait > stuckMaxSent {
			continue
		}
		waited := now.Sub(f.waitSince)
		neverAnswered := t.Download == 0 && waited >= openWait
		retriedInVain := f.bursts >= 2 && waited >= silent &&
			now.Sub(f.lastUp) >= stuckLastQuiet
		if !neverAnswered && !retriedInVain {
			continue
		}
		if cl, ok := c.(closer); ok {
			_ = cl.Close()
			closed = append(closed, fmt.Sprintf("%s:%d %ds",
				t.Metadata.DstIP, t.Metadata.DstPort, int(waited.Seconds())))
		}
		delete(flows, t.ID)
	}
	for id, f := range flows {
		if now.Sub(f.lastSeen) > time.Minute {
			delete(flows, id)
		}
	}
	if len(closed) == 0 {
		return ""
	}
	sort.Strings(closed)
	return fmt.Sprintf("%d: %s", len(closed), strings.Join(closed, ", "))
}

// CloseAllFlows closes every connection tun2socks relays and returns how
// many. Called right after an engine-only reconnect (16.10, field log:
// after a wake the engine was restarted, its probes passed, yet nothing
// loaded for two minutes until a manual reconnect) — the apps' existing
// connections went through the engine that was just replaced and hang on
// it; closed, the apps redial at once through the new one.
func CloseAllFlows() int {
	type closer interface{ Close() error }
	flowsMu.Lock()
	defer flowsMu.Unlock()
	n := 0
	for _, c := range statistic.DefaultManager.Snapshot().Connections {
		if cl, ok := c.(closer); ok {
			_ = cl.Close()
			n++
		}
	}
	for id := range flows {
		delete(flows, id)
	}
	return n
}
