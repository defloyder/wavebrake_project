// Command cloak-client-proxy is the Windows-side counterpart to cloak-relay.
//
// The Windows app doesn't run Hysteria2 through the same Go bridge Android
// uses (wavebreak-mobile/native/hysteria_bridge) — it shells out to
// sing-box.exe, which has its own built-in Hysteria2 client with no cloak
// awareness and no realistic way to add it without forking sing-box itself.
//
// Instead of touching sing-box at all, this binary sits between it and the
// real server: it listens on a local UDP port, wraps everything it receives
// there in the cloak protocol before forwarding to the real cloak-relay
// server, and unwraps whatever comes back before handing it to sing-box.
// sing-box's Hysteria2 outbound is simply pointed at this local port instead
// of the real host — from sing-box's point of view nothing about Hysteria2
// changed; the cloak wrapping happens entirely outside it.
//
// This mirrors cloak-relay's own role in reverse: cloak-relay unwraps public
// cloak traffic and forwards plain packets to a real Hysteria2 server on
// loopback; this forwards plain local traffic out as wrapped cloak traffic
// to a real cloak-relay. Being a plain cross-compiled Go binary (no cgo, no
// gomobile, no Dart FFI) is the whole point — it builds for Windows exactly
// the way cloak-relay already builds for Linux.
package main

import (
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"sync/atomic"

	"wavebreak.app/cloak"
)

func main() {
	listen := flag.String("listen", "127.0.0.1:0", "local UDP address for sing-box to connect to")
	remote := flag.String("remote", "", "real cloak-relay server address, host:port (required)")
	minSize := flag.Int("min-size", cloak.DefaultProfile.MinSize, "cloak minimum packet size")
	maxSize := flag.Int("max-size", cloak.DefaultProfile.MaxSize, "cloak maximum packet size")
	chaffMinMS := flag.Int64("chaff-min-ms", cloak.DefaultProfile.ChaffMinInterval, "cloak minimum chaff interval (ms)")
	chaffMaxMS := flag.Int64("chaff-max-ms", cloak.DefaultProfile.ChaffMaxInterval, "cloak maximum chaff interval (ms)")
	readyFile := flag.String("ready-file", "", "optional: write the actual bound local address to this file once listening (for :0 auto-port)")
	flag.Parse()

	if *remote == "" {
		fmt.Fprintln(os.Stderr, "cloak-client-proxy: -remote is required")
		os.Exit(2)
	}
	remoteAddr, err := net.ResolveUDPAddr("udp", *remote)
	if err != nil {
		log.Fatalf("cloak-client-proxy: resolve remote %q: %v", *remote, err)
	}

	local, err := net.ListenUDP("udp", mustResolveLocal(*listen))
	if err != nil {
		log.Fatalf("cloak-client-proxy: listen %q: %v", *listen, err)
	}
	defer local.Close()

	// Separate socket for talking to the real remote cloak-relay. This MUST
	// be a different socket than `local`: `local` carries sing-box's plain,
	// unwrapped Hysteria2 traffic, while this one carries only cloak-wrapped
	// bytes. Mixing them on one socket would make cloak.Conn try to Unwrap()
	// sing-box's own plain packets as if they were cloak frames.
	upstream, err := net.ListenUDP("udp", &net.UDPAddr{})
	if err != nil {
		log.Fatalf("cloak-client-proxy: open upstream socket: %v", err)
	}
	defer upstream.Close()

	actualAddr := local.LocalAddr().String()
	log.Printf("cloak-client-proxy: listening on %s, wrapping to %s (packet size %d-%d, chaff every %d-%dms)",
		actualAddr, remoteAddr, *minSize, *maxSize, *chaffMinMS, *chaffMaxMS)

	if *readyFile != "" {
		if err := os.WriteFile(*readyFile, []byte(actualAddr), 0o644); err != nil {
			log.Fatalf("cloak-client-proxy: write ready-file: %v", err)
		}
	}

	profile := cloak.Profile{
		MinSize:          *minSize,
		MaxSize:          *maxSize,
		ChaffMinInterval: *chaffMinMS,
		ChaffMaxInterval: *chaffMaxMS,
	}

	if err := run(local, upstream, remoteAddr, profile); err != nil {
		log.Fatalf("cloak-client-proxy: %v", err)
	}
}

func mustResolveLocal(addr string) *net.UDPAddr {
	a, err := net.ResolveUDPAddr("udp", addr)
	if err != nil {
		log.Fatalf("cloak-client-proxy: resolve listen %q: %v", addr, err)
	}
	return a
}

// run pumps sing-box's local, plain UDP traffic (on `local`) through a
// cloak.Conn wrapping `upstream` to the real remote cloak-relay, and back.
// sing-box only ever talks to one peer (itself, from a single local source
// address+port that can change if it reconnects) — unlike cloak-relay, which
// must demultiplex many external clients, this only needs to remember the
// single most recent local sender to know where to deliver unwrapped
// replies.
func run(local, upstream *net.UDPConn, remote *net.UDPAddr, profile cloak.Profile) error {
	wrapped := cloak.NewConn(upstream, remote, profile)
	defer wrapped.Close()

	var singBoxAddr atomic.Value // stores net.Addr
	errCh := make(chan error, 2)

	// sing-box -> wrap -> remote
	go func() {
		buf := make([]byte, 65535)
		for {
			n, addr, err := local.ReadFromUDP(buf)
			if err != nil {
				errCh <- fmt.Errorf("read local: %w", err)
				return
			}
			singBoxAddr.Store(net.Addr(addr))
			if _, err := wrapped.WriteTo(buf[:n], remote); err != nil {
				log.Printf("cloak-client-proxy: forward to remote: %v", err)
			}
		}
	}()

	// remote -> unwrap -> sing-box
	go func() {
		buf := make([]byte, 65535)
		for {
			n, _, err := wrapped.ReadFrom(buf)
			if err != nil {
				errCh <- fmt.Errorf("read remote: %w", err)
				return
			}
			addr, _ := singBoxAddr.Load().(net.Addr)
			if addr == nil {
				// Nothing has connected locally yet (e.g. a stray chaff
				// reply beat sing-box's first packet) — nowhere to deliver
				// this to, drop it.
				continue
			}
			if _, err := local.WriteTo(buf[:n], addr); err != nil {
				log.Printf("cloak-client-proxy: forward to sing-box: %v", err)
			}
		}
	}()

	return <-errCh
}
