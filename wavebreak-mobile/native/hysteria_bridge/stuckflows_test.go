package bridge

import (
	"net"
	"net/netip"
	"strings"
	"testing"
	"time"

	M "github.com/xjasonlyu/tun2socks/v2/metadata"
	"github.com/xjasonlyu/tun2socks/v2/tunnel/statistic"
)

func track(dst string) (net.Conn, net.Conn) {
	a, b := net.Pipe()
	md := &M.Metadata{Network: M.TCP, DstIP: netip.MustParseAddr(dst), DstPort: 443}
	return statistic.NewTCPTracker(a, md, statistic.DefaultManager), b
}

func drain(c net.Conn) {
	go func() {
		buf := make([]byte, 256)
		for {
			if _, err := c.Read(buf); err != nil {
				return
			}
		}
	}()
}

// Opened, spoke first, never answered: closed after openSec. A quiet
// connection whose last message expected no reply (an ack): kept.
func TestCloseStuckFlows(t *testing.T) {
	silentOpen, far1 := track("149.154.167.51")
	quiet, far2 := track("142.250.1.1")
	drain(far1)
	drain(far2)
	go func() { far2.Write([]byte("update")) }()
	buf := make([]byte, 16)
	quiet.Read(buf)            // a reply came…
	quiet.Write([]byte("ack")) // …then an ack nobody answers
	silentOpen.Write([]byte("hello"))

	CloseStuckFlows(1, 2)
	time.Sleep(1300 * time.Millisecond)
	got := CloseStuckFlows(1, 2)
	if !strings.Contains(got, "149.154.167.51:443") || strings.Contains(got, "142.250.1.1") {
		t.Fatalf("closed %q, want only the never-answered one", got)
	}
	if _, err := silentOpen.Write([]byte("x")); err == nil {
		t.Fatal("the stuck connection is still open")
	}
	if _, err := quiet.Write([]byte("x")); err != nil {
		t.Fatal("the quiet connection was closed")
	}
	quiet.Close()
}

func TestCloseAllFlowsWithNothingOpen(t *testing.T) {
	if n := CloseAllFlows(); n != 0 {
		t.Fatalf("closed %d flows with none open", n)
	}
}
