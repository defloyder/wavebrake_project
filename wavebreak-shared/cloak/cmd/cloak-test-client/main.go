// Command cloak-test-client drives the real apernet/hysteria client
// library (the same core/client package wavebreak-mobile/native/
// hysteria_bridge/bridge.go embeds into the Android app) with its
// ConnFactory pointed at cloak.Conn instead of a bare UDP socket. It exists
// to prove the full real protocol — not just raw bytes — survives the
// cloak wrapping end to end, before wiring this into the actual mobile
// bridge or touching a phone.
//
// Usage:
//
//	cloak-test-client -server host:port -auth "id:id" -sni host \
//	  -fetch https://example.com/
//
// -fetch is optional; without it, the program just proves the handshake
// completes and exits 0.
package main

import (
	"context"
	"crypto/tls"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"strings"
	"time"

	hyclient "github.com/apernet/hysteria/core/v2/client"

	"wavebreak.app/cloak"
)

// cloakConnFactory implements hyclient's ConnFactory interface (New(net.Addr)
// (net.PacketConn, error)) by opening a real UDP socket and wrapping it with
// cloak.Conn — the exact shape bridge.go's own hyConnFactory has, just
// swapping in the cloak layer instead of Android's VPN-protect socket.
type cloakConnFactory struct {
	profile cloak.Profile
}

func (f cloakConnFactory) New(remote net.Addr) (net.PacketConn, error) {
	raw, err := net.ListenUDP("udp", nil)
	if err != nil {
		return nil, err
	}
	return cloak.NewConn(raw, remote, f.profile), nil
}

func main() {
	server := flag.String("server", "", "hysteria2 server address, host:port")
	auth := flag.String("auth", "", "auth string, usually \"id:id\"")
	sni := flag.String("sni", "", "TLS SNI / server name")
	insecure := flag.Bool("insecure", false, "skip TLS certificate verification")
	fetchURL := flag.String("fetch", "", "optional: fetch this URL through the tunnel via client.TCP to prove real proxying works")
	minSize := flag.Int("min-size", cloak.DefaultProfile.MinSize, "cloak min packet size")
	maxSize := flag.Int("max-size", cloak.DefaultProfile.MaxSize, "cloak max packet size")
	timeout := flag.Duration("timeout", 15*time.Second, "overall timeout")
	flag.Parse()

	if *server == "" || *auth == "" {
		log.Fatal("cloak-test-client: -server and -auth are required")
	}

	addr, err := net.ResolveUDPAddr("udp", *server)
	if err != nil {
		log.Fatalf("cloak-test-client: resolve server address: %v", err)
	}

	profile := cloak.DefaultProfile
	profile.MinSize = *minSize
	profile.MaxSize = *maxSize

	cfg := &hyclient.Config{
		ServerAddr: addr,
		Auth:       *auth,
		TLSConfig: hyclient.TLSConfig{
			ServerName:         *sni,
			InsecureSkipVerify: *insecure,
		},
		ConnFactory: cloakConnFactory{profile: profile},
	}

	done := make(chan struct{})
	var client hyclient.Client
	var dialErr error
	go func() {
		defer close(done)
		client, _, dialErr = hyclient.NewClient(cfg)
	}()

	select {
	case <-done:
	case <-time.After(*timeout):
		log.Fatalf("cloak-test-client: handshake did not complete within %s (this is the exact symptom being tested for — the wrapped session either works or hangs the same way the bare one did)", *timeout)
	}
	if dialErr != nil {
		log.Fatalf("cloak-test-client: handshake failed: %v", dialErr)
	}
	defer client.Close()
	log.Printf("cloak-test-client: handshake OK through the cloak layer (packet size %d-%d bytes)", profile.MinSize, profile.MaxSize)

	if *fetchURL == "" {
		return
	}

	httpClient := &http.Client{
		Timeout: *timeout,
		Transport: &http.Transport{
			DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
				return client.TCP(addr)
			},
			TLSClientConfig: &tls.Config{InsecureSkipVerify: *insecure}, //nolint:gosec // test tool only
		},
	}
	resp, err := httpClient.Get(*fetchURL)
	if err != nil {
		log.Fatalf("cloak-test-client: fetch through tunnel failed (this is the failure mode we're actually chasing: handshake ok, real data doesn't flow): %v", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 4096))
	if err != nil {
		log.Fatalf("cloak-test-client: reading response body failed mid-stream: %v", err)
	}
	log.Printf("cloak-test-client: fetched %s through the tunnel: HTTP %d, %d bytes: %s",
		*fetchURL, resp.StatusCode, len(body), strings.TrimSpace(fmt.Sprintf("%.200s", body)))
}
