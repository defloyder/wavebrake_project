package cloak

import (
	"crypto/rand"
	"math/big"
	mathrand "math/rand"
	"net"
	"sync"
	"time"
)

// Conn wraps a net.PacketConn (the same interface Hysteria's ConnFactory
// hook returns — see wavebreak-mobile/native/hysteria_bridge/bridge.go's
// hyConnFactory) and applies the cloak protocol to every packet exchanged
// with remote. It is single-peer: Hysteria's client dials exactly one
// server per connection, so there's exactly one remote address to track,
// unlike the server side (see relay/main.go) which demultiplexes many
// clients on one socket.
//
// A background goroutine sends chaff whenever the connection has been idle
// past a randomized interval, so the wire shows continuous small packets
// instead of "handshake burst, then silence, then a burst of real data."
// It exits when Close is called.
type Conn struct {
	net.PacketConn
	remote  net.Addr
	profile Profile

	mu       sync.Mutex
	lastSend time.Time

	closeOnce sync.Once
	closeCh   chan struct{}
}

// NewConn starts the chaff goroutine and returns a Conn ready to use as a
// drop-in net.PacketConn. remote is the single peer this side of the
// tunnel talks to (the Hysteria server, from the client's perspective).
func NewConn(underlying net.PacketConn, remote net.Addr, profile Profile) *Conn {
	c := &Conn{
		PacketConn: underlying,
		remote:     remote,
		profile:    profile,
		lastSend:   time.Now(),
		closeCh:    make(chan struct{}),
	}
	go c.chaffLoop()
	return c
}

// WriteTo wraps payload per the cloak protocol before handing it to the
// underlying connection. addr is expected to equal c.remote (Hysteria only
// ever writes to the one server it dialed); this isn't enforced since
// nothing in the caller would benefit from the panic, but chaff timing
// assumes a single peer, so mixing addrs here would just make the shape
// wrong, not break correctness.
func (c *Conn) WriteTo(payload []byte, addr net.Addr) (int, error) {
	wrapped, err := Wrap(c.profile, payload)
	if err != nil {
		return 0, err
	}
	c.markSent()
	if _, err := c.PacketConn.WriteTo(wrapped, addr); err != nil {
		return 0, err
	}
	return len(payload), nil
}

// ReadFrom reads one wire packet, discards it transparently if it's chaff
// (by looping — the caller's ReadFrom contract is "block until a real
// packet or an error," and a chaff packet is neither), and returns the
// unwrapped real payload otherwise.
func (c *Conn) ReadFrom(buf []byte) (int, net.Addr, error) {
	raw := make([]byte, 65535)
	for {
		n, addr, err := c.PacketConn.ReadFrom(raw)
		if err != nil {
			return 0, addr, err
		}
		payload, chaff, err := Unwrap(raw[:n])
		if err != nil {
			// Not a cloak packet at all — e.g. an unsolicited probe from
			// something on the network path. Drop it the same way chaff
			// gets dropped rather than surfacing decode errors to
			// Hysteria, which has no use for them.
			continue
		}
		if chaff {
			continue
		}
		return copy(buf, payload), addr, nil
	}
}

// Close stops the chaff goroutine before closing the underlying conn.
func (c *Conn) Close() error {
	c.closeOnce.Do(func() { close(c.closeCh) })
	return c.PacketConn.Close()
}

func (c *Conn) markSent() {
	c.mu.Lock()
	c.lastSend = time.Now()
	c.mu.Unlock()
}

func (c *Conn) chaffLoop() {
	for {
		wait := randDuration(c.profile.ChaffMinInterval, c.profile.ChaffMaxInterval)
		select {
		case <-c.closeCh:
			return
		case <-time.After(wait):
		}

		c.mu.Lock()
		idle := time.Since(c.lastSend)
		c.mu.Unlock()
		minInterval := time.Duration(c.profile.ChaffMinInterval) * time.Millisecond
		if idle < minInterval {
			// Real traffic already sent something inside this window —
			// no gap to fill, so skip sending chaff this tick rather than
			// stacking extra packets on top of an already-busy stream.
			continue
		}

		pkt, err := WrapChaff(c.profile)
		if err != nil {
			continue
		}
		c.markSent()
		if _, err := c.PacketConn.WriteTo(pkt, c.remote); err != nil {
			// Write failures here mean the underlying conn is dead or
			// closing; the next real WriteTo/ReadFrom will surface the
			// same error to Hysteria, so just stop chaffing quietly.
			return
		}
	}
}

// randDuration returns a uniformly random duration in [min, max]
// milliseconds. Falls back to math/rand on crypto/rand failure since chaff
// timing isn't a secret — only unpredictable enough to avoid a fixed period
// a classifier could lock onto.
func randDuration(min, max int64) time.Duration {
	if max <= min {
		return time.Duration(min) * time.Millisecond
	}
	span := max - min
	n, err := rand.Int(rand.Reader, big.NewInt(span+1))
	if err != nil {
		return time.Duration(min+mathrand.Int63n(span+1)) * time.Millisecond //nolint:gosec
	}
	return time.Duration(min+n.Int64()) * time.Millisecond
}
