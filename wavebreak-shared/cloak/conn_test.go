package cloak

import (
	"bytes"
	"net"
	"testing"
	"time"
)

// TestConnRoundTripOverLoopback exercises Conn over a real UDP socket pair
// (not just the in-memory Wrap/Unwrap functions) to catch anything that
// only shows up once actual net.PacketConn semantics are involved —
// buffer reuse, address handling, the chaff goroutine actually running.
func TestConnRoundTripOverLoopback(t *testing.T) {
	serverRaw, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatalf("listen server: %v", err)
	}
	defer serverRaw.Close()

	clientRaw, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatalf("listen client: %v", err)
	}
	defer clientRaw.Close()

	// Fast chaff so the test actually exercises the goroutine within its
	// timeout, without waiting on DefaultProfile's real-world intervals.
	profile := Profile{MinSize: 32, MaxSize: 64, ChaffMinInterval: 5, ChaffMaxInterval: 15}

	client := NewConn(clientRaw, serverRaw.LocalAddr(), profile)
	defer client.Close()
	server := NewConn(serverRaw, clientRaw.LocalAddr(), profile)
	defer server.Close()

	// Let a few chaff packets fly in both directions before any real
	// traffic — this is the exact scenario that matters: a connection that
	// hasn't "started talking" yet must not go silent on the wire.
	time.Sleep(80 * time.Millisecond)

	msg := []byte("hello over cloak")
	if _, err := client.WriteTo(msg, serverRaw.LocalAddr()); err != nil {
		t.Fatalf("client WriteTo: %v", err)
	}

	buf := make([]byte, 2048)
	serverRaw.SetReadDeadline(time.Now().Add(2 * time.Second))
	n, _, err := server.ReadFrom(buf)
	if err != nil {
		t.Fatalf("server ReadFrom: %v (chaff packets may not be getting filtered)", err)
	}
	if !bytes.Equal(buf[:n], msg) {
		t.Fatalf("server got %q, want %q", buf[:n], msg)
	}

	reply := []byte("hello back")
	if _, err := server.WriteTo(reply, clientRaw.LocalAddr()); err != nil {
		t.Fatalf("server WriteTo: %v", err)
	}
	clientRaw.SetReadDeadline(time.Now().Add(2 * time.Second))
	n, _, err = client.ReadFrom(buf)
	if err != nil {
		t.Fatalf("client ReadFrom: %v", err)
	}
	if !bytes.Equal(buf[:n], reply) {
		t.Fatalf("client got %q, want %q", buf[:n], reply)
	}
}

// TestChaffKeepsWireActiveDuringIdle checks the actual property this whole
// package exists for: with no real traffic at all, the wire still carries
// packets at roughly the configured interval, so a passive observer never
// sees a multi-hundred-millisecond gap that would reveal "nothing is
// happening here right now."
func TestChaffKeepsWireActiveDuringIdle(t *testing.T) {
	serverRaw, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatalf("listen server: %v", err)
	}
	defer serverRaw.Close()

	clientRaw, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatalf("listen client: %v", err)
	}
	defer clientRaw.Close()

	profile := Profile{MinSize: 32, MaxSize: 64, ChaffMinInterval: 10, ChaffMaxInterval: 20}
	client := NewConn(clientRaw, serverRaw.LocalAddr(), profile)
	defer client.Close()

	// Observe the raw wire directly (not through a Conn) — this is what a
	// passive DPI box would see: undecoded packets and their arrival gaps.
	serverRaw.SetReadDeadline(time.Now().Add(500 * time.Millisecond))
	raw := make([]byte, 2048)
	var gaps []time.Duration
	last := time.Now()
	for i := 0; i < 10; i++ {
		n, _, err := serverRaw.ReadFrom(raw)
		if err != nil {
			t.Fatalf("only observed %d chaff packets before a read error: %v", i, err)
		}
		if n < headerSize {
			t.Fatalf("observed packet shorter than the cloak header (%d bytes)", n)
		}
		now := time.Now()
		gaps = append(gaps, now.Sub(last))
		last = now
	}

	maxAllowedGap := time.Duration(profile.ChaffMaxInterval) * time.Millisecond * 3 // generous scheduler slack
	for i, g := range gaps[1:] {
		if g > maxAllowedGap {
			t.Fatalf("gap #%d between idle packets was %v, exceeding %v — wire went quiet", i, g, maxAllowedGap)
		}
	}
}
