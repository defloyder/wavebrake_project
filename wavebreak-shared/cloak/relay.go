package cloak

import (
	"log"
	"net"
	"sync"
	"time"
)

// Relay sits in front of a real Hysteria2 server (or any single UDP
// backend): it terminates the cloak protocol on its public socket and
// forwards plain, unwrapped packets to the backend over a private
// loopback socket — one per external client, so the backend still sees
// each client as a distinct source address:port, exactly as if the cloak
// layer weren't there at all. The backend needs no changes.
//
// This is deliberately a bump in the wire, not a patch to Hysteria2
// itself: Hysteria2's own release cadence and the difficulty of safely
// forking a QUIC implementation make "wrap the existing binary" a much
// smaller blast radius than "carry a fork of apernet/hysteria." If the
// wire format here ever needs to change, only this relay and the client's
// Conn (see conn.go) need to agree — the backend and the rest of Hysteria2
// stay exactly as upstream ships them.
type Relay struct {
	public  net.PacketConn
	backend *net.UDPAddr
	profile Profile

	// PeerIdleTimeout is how long a peer can go without a real packet
	// (from either direction) before its backend socket is torn down.
	// Chaff alone never resets this — an idle QUIC session that's only
	// being kept "alive-looking" on the wire by chaff should still expire
	// server-side once the app above it has genuinely given up, the same
	// way Hysteria2's own udpIdleTimeout would.
	PeerIdleTimeout time.Duration

	mu    sync.Mutex
	peers map[string]*relayPeer

	logger *log.Logger
}

type relayPeer struct {
	externalAddr net.Addr
	backendConn  *net.UDPConn
	lastReal     time.Time
	lastSent     time.Time
	closeCh      chan struct{}
}

// NewRelay constructs a Relay. public is the socket clients connect to
// (already bound); backend is the real Hysteria2 server's address, normally
// on loopback (e.g. 127.0.0.1:44100) since the whole point is that only the
// cloak-wrapped traffic is ever exposed publicly.
func NewRelay(public net.PacketConn, backend *net.UDPAddr, profile Profile, logger *log.Logger) *Relay {
	if logger == nil {
		logger = log.Default()
	}
	return &Relay{
		public:          public,
		backend:         backend,
		profile:         profile,
		PeerIdleTimeout: 3 * time.Minute,
		peers:           make(map[string]*relayPeer),
		logger:          logger,
	}
}

// Run processes packets on the public socket until it errors (typically
// because it was closed). It also runs peer cleanup on a timer; both stop
// when Run returns.
func (r *Relay) Run() error {
	stopCleanup := make(chan struct{})
	go r.cleanupLoop(stopCleanup)
	defer close(stopCleanup)

	buf := make([]byte, 65535)
	for {
		n, addr, err := r.public.ReadFrom(buf)
		if err != nil {
			return err
		}
		payload, chaff, err := Unwrap(buf[:n])
		if err != nil {
			// Not a cloak packet — could be a stray probe. The whole point
			// of this layer is to not react informatively to those.
			continue
		}
		if chaff {
			continue
		}
		peer := r.peerFor(addr)
		peer.lastReal = time.Now()
		if _, err := peer.backendConn.Write(payload); err != nil {
			r.logger.Printf("cloak: relay->backend write failed for %s: %v", addr, err)
		}
	}
}

// peerFor returns the existing peer for addr or creates one, dialing a
// fresh loopback socket to the backend and starting its reply pump and
// chaff goroutines.
func (r *Relay) peerFor(addr net.Addr) *relayPeer {
	key := addr.String()

	r.mu.Lock()
	if p, ok := r.peers[key]; ok {
		r.mu.Unlock()
		return p
	}
	r.mu.Unlock()

	backendConn, err := net.DialUDP("udp", nil, r.backend)
	if err != nil {
		// Extremely unlikely (loopback dial), but if it happens the
		// packet that triggered this is simply dropped — the client's own
		// retry/timeout logic handles a lost datagram the same as it
		// would on a lossy link.
		r.logger.Printf("cloak: could not dial backend for new peer %s: %v", addr, err)
		return &relayPeer{externalAddr: addr, backendConn: nil, closeCh: make(chan struct{})}
	}

	p := &relayPeer{
		externalAddr: addr,
		backendConn:  backendConn,
		lastReal:     time.Now(),
		lastSent:     time.Now(),
		closeCh:      make(chan struct{}),
	}

	r.mu.Lock()
	r.peers[key] = p
	r.mu.Unlock()

	go r.pumpBackendReplies(p)
	go r.chaffPeer(p)
	return p
}

// pumpBackendReplies wraps and forwards every packet the backend sends
// back for this peer, so the reverse direction (server -> client) gets the
// same size/timing treatment as the forward direction.
func (r *Relay) pumpBackendReplies(p *relayPeer) {
	buf := make([]byte, 65535)
	for {
		p.backendConn.SetReadDeadline(time.Now().Add(r.PeerIdleTimeout))
		n, err := p.backendConn.Read(buf)
		if err != nil {
			r.removePeer(p)
			return
		}
		wrapped, err := Wrap(r.profile, buf[:n])
		if err != nil {
			continue
		}
		p.lastSent = time.Now()
		if _, err := r.public.WriteTo(wrapped, p.externalAddr); err != nil {
			r.removePeer(p)
			return
		}
	}
}

// chaffPeer mirrors Conn's chaffLoop (see conn.go) for the relay->client
// direction: without it, only the client->server side would get chaff
// (from the app-side Conn), leaving the reverse direction's silence during
// real-world request/response gaps just as visible as an unwrapped tunnel.
func (r *Relay) chaffPeer(p *relayPeer) {
	for {
		wait := randDuration(r.profile.ChaffMinInterval, r.profile.ChaffMaxInterval)
		select {
		case <-p.closeCh:
			return
		case <-time.After(wait):
		}
		if time.Since(p.lastSent) < time.Duration(r.profile.ChaffMinInterval)*time.Millisecond {
			continue
		}
		pkt, err := WrapChaff(r.profile)
		if err != nil {
			continue
		}
		p.lastSent = time.Now()
		if _, err := r.public.WriteTo(pkt, p.externalAddr); err != nil {
			return
		}
	}
}

func (r *Relay) removePeer(p *relayPeer) {
	r.mu.Lock()
	delete(r.peers, p.externalAddr.String())
	r.mu.Unlock()
	select {
	case <-p.closeCh:
	default:
		close(p.closeCh)
	}
	if p.backendConn != nil {
		p.backendConn.Close()
	}
}

func (r *Relay) cleanupLoop(stop <-chan struct{}) {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-stop:
			return
		case <-ticker.C:
			r.mu.Lock()
			var stale []*relayPeer
			for _, p := range r.peers {
				if time.Since(p.lastReal) > r.PeerIdleTimeout {
					stale = append(stale, p)
				}
			}
			r.mu.Unlock()
			for _, p := range stale {
				r.removePeer(p)
			}
		}
	}
}
