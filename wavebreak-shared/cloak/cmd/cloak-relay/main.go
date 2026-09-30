// Command cloak-relay runs the cloak.Relay in front of a real Hysteria2
// server. It never touches Hysteria2 itself — deploy it as a small extra
// process that owns the public UDP port, with the real hysteria server
// bound to loopback only.
//
// Usage:
//
//	cloak-relay -listen :55555 -backend 127.0.0.1:44100
//
// The listen port is what goes in the client's link (the address it
// actually dials); -backend is wherever the real "hysteria server -c
// ...yaml" process is bound (its own config's `listen:` should be a
// loopback address+port, not the public one).
package main

import (
	"flag"
	"log"
	"net"

	"wavebreak.app/cloak"
)

func main() {
	listenAddr := flag.String("listen", ":55555", "public UDP address to accept cloak-wrapped client traffic on")
	backendAddr := flag.String("backend", "127.0.0.1:44100", "the real Hysteria2 server's UDP address (loopback)")
	minSize := flag.Int("min-size", cloak.DefaultProfile.MinSize, "minimum wire packet size in bytes")
	maxSize := flag.Int("max-size", cloak.DefaultProfile.MaxSize, "maximum wire packet size in bytes (keep <= path MTU minus IP/UDP headers, 1350 is safe)")
	chaffMin := flag.Int64("chaff-min-ms", cloak.DefaultProfile.ChaffMinInterval, "minimum milliseconds between idle chaff packets")
	chaffMax := flag.Int64("chaff-max-ms", cloak.DefaultProfile.ChaffMaxInterval, "maximum milliseconds between idle chaff packets")
	flag.Parse()

	backend, err := net.ResolveUDPAddr("udp", *backendAddr)
	if err != nil {
		log.Fatalf("cloak-relay: resolve backend %q: %v", *backendAddr, err)
	}

	udpAddr, err := net.ResolveUDPAddr("udp", *listenAddr)
	if err != nil {
		log.Fatalf("cloak-relay: resolve listen address %q: %v", *listenAddr, err)
	}
	public, err := net.ListenUDP("udp", udpAddr)
	if err != nil {
		log.Fatalf("cloak-relay: listen on %q: %v", *listenAddr, err)
	}
	defer public.Close()

	profile := cloak.Profile{
		MinSize:          *minSize,
		MaxSize:          *maxSize,
		ChaffMinInterval: *chaffMin,
		ChaffMaxInterval: *chaffMax,
	}

	log.Printf("cloak-relay: listening on %s, forwarding to backend %s (packet size %d-%d bytes, chaff every %d-%dms)",
		*listenAddr, backend, profile.MinSize, profile.MaxSize, profile.ChaffMinInterval, profile.ChaffMaxInterval)

	relay := cloak.NewRelay(public, backend, profile, log.Default())
	if err := relay.Run(); err != nil {
		log.Fatalf("cloak-relay: %v", err)
	}
}
