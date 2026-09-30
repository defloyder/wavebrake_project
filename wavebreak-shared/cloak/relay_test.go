package cloak

import (
	"bytes"
	"fmt"
	"log"
	"net"
	"testing"
	"time"
)

// echoBackend starts a trivial UDP echo server standing in for the real
// Hysteria2 process, and returns its address plus a stop func.
func echoBackend(t *testing.T) (*net.UDPAddr, func()) {
	t.Helper()
	conn, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatalf("echo backend listen: %v", err)
	}
	done := make(chan struct{})
	go func() {
		buf := make([]byte, 2048)
		for {
			conn.SetReadDeadline(time.Now().Add(200 * time.Millisecond))
			n, addr, err := conn.ReadFromUDP(buf)
			if err != nil {
				select {
				case <-done:
					return
				default:
					continue
				}
			}
			reply := append([]byte("echo:"), buf[:n]...)
			conn.WriteToUDP(reply, addr)
		}
	}()
	stop := func() {
		close(done)
		conn.Close()
	}
	return conn.LocalAddr().(*net.UDPAddr), stop
}

// TestRelayEndToEnd stands up a real Relay in front of a real (echo)
// backend and drives it with a real client-side Conn, over actual UDP
// sockets — the same three pieces (client Conn, public wire, Relay ->
// backend) that would be deployed for real, just with the echo backend
// standing in for "hysteria server -c hysteria.yaml".
func TestRelayEndToEnd(t *testing.T) {
	backendAddr, stopBackend := echoBackend(t)
	defer stopBackend()

	publicConn, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatalf("relay public listen: %v", err)
	}
	profile := Profile{MinSize: 32, MaxSize: 96, ChaffMinInterval: 20, ChaffMaxInterval: 50}
	relay := NewRelay(publicConn, backendAddr, profile, log.New(testWriter{t}, "", 0))
	go relay.Run()
	defer publicConn.Close()

	clientRaw, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatalf("client listen: %v", err)
	}
	client := NewConn(clientRaw, publicConn.LocalAddr(), profile)
	defer client.Close()

	msg := []byte("ping through the relay")
	if _, err := client.WriteTo(msg, publicConn.LocalAddr()); err != nil {
		t.Fatalf("client WriteTo: %v", err)
	}

	clientRaw.SetReadDeadline(time.Now().Add(2 * time.Second))
	buf := make([]byte, 2048)
	n, _, err := client.ReadFrom(buf)
	if err != nil {
		t.Fatalf("client ReadFrom: %v", err)
	}
	want := append([]byte("echo:"), msg...)
	if !bytes.Equal(buf[:n], want) {
		t.Fatalf("got %q, want %q", buf[:n], want)
	}
}

// TestRelayHandlesMultipleClientsIndependently is the case that would break
// first if the relay ever collapsed distinct clients onto one shared
// backend socket: each client's traffic must reach and return from the
// backend as if it were the only one connected, matching what a real
// Hysteria2 server expects (one source address:port per client).
func TestRelayHandlesMultipleClientsIndependently(t *testing.T) {
	backendAddr, stopBackend := echoBackend(t)
	defer stopBackend()

	publicConn, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatalf("relay public listen: %v", err)
	}
	profile := Profile{MinSize: 32, MaxSize: 96, ChaffMinInterval: 30, ChaffMaxInterval: 60}
	relay := NewRelay(publicConn, backendAddr, profile, log.New(testWriter{t}, "", 0))
	go relay.Run()
	defer publicConn.Close()

	const numClients = 5
	type client struct {
		conn *Conn
		msg  []byte
	}
	clients := make([]client, numClients)
	for i := 0; i < numClients; i++ {
		raw, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
		if err != nil {
			t.Fatalf("client %d listen: %v", i, err)
		}
		c := NewConn(raw, publicConn.LocalAddr(), profile)
		defer c.Close()
		clients[i] = client{conn: c, msg: []byte(fmt.Sprintf("client-%d-payload", i))}
	}

	for _, c := range clients {
		if _, err := c.conn.WriteTo(c.msg, publicConn.LocalAddr()); err != nil {
			t.Fatalf("WriteTo: %v", err)
		}
	}

	buf := make([]byte, 2048)
	for i, c := range clients {
		c.conn.PacketConn.(interface {
			SetReadDeadline(time.Time) error
		}).SetReadDeadline(time.Now().Add(2 * time.Second))
		n, _, err := c.conn.ReadFrom(buf)
		if err != nil {
			t.Fatalf("client %d ReadFrom: %v", i, err)
		}
		want := append([]byte("echo:"), c.msg...)
		if !bytes.Equal(buf[:n], want) {
			t.Fatalf("client %d got %q, want %q (cross-talk between clients?)", i, buf[:n], want)
		}
	}
}

type testWriter struct{ t *testing.T }

func (w testWriter) Write(p []byte) (int, error) {
	w.t.Logf("%s", p)
	return len(p), nil
}
