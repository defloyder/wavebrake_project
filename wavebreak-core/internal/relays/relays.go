// Package relays keeps the list of domestic relay entry points and which of
// them are reachable right now.
//
// A relay is a plain TCP forwarder in the user's country (e.g. a VPS in
// Moscow) that passes :443 through to the main node, so the phone talks to
// a domestic IP — the only thing that survives mobile carriers' IP/SNI
// whitelists. The TLS session (VLESS+XHTTP+REALITY) stays end to end
// between the app and the main node; the relay sees nothing and holds no
// keys, so losing one costs nothing but an entry point. Relays can be shut
// down by their hoster at any time: Core checks them and stops handing out
// dead ones, and the apps still have the direct transports to fall back to.
package relays

import (
	"context"
	"fmt"
	"net"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Relay is one domestic entry point.
type Relay struct {
	// Name shown to users, e.g. "Moscow".
	Name string
	Host string
	Port int
}

func (r Relay) Address() string { return net.JoinHostPort(r.Host, strconv.Itoa(r.Port)) }

// Parse reads "Name=host[:port],Name2=host2[:port]" (port defaults to 443).
func Parse(spec string) ([]Relay, error) {
	var out []Relay
	for _, item := range strings.Split(spec, ",") {
		item = strings.TrimSpace(item)
		if item == "" {
			continue
		}
		name, addr, ok := strings.Cut(item, "=")
		name, addr = strings.TrimSpace(name), strings.TrimSpace(addr)
		if !ok || name == "" || addr == "" {
			return nil, fmt.Errorf("relay %q: want Name=host[:port]", item)
		}
		host, port := addr, 443
		if h, p, err := net.SplitHostPort(addr); err == nil {
			n, err := strconv.Atoi(p)
			if err != nil || n <= 0 || n > 65535 {
				return nil, fmt.Errorf("relay %q: bad port", item)
			}
			host, port = h, n
		}
		out = append(out, Relay{Name: name, Host: host, Port: port})
	}
	return out, nil
}

// Dialer checks one relay; the default is a TCP connect.
type Dialer func(ctx context.Context, address string) error

func tcpDial(ctx context.Context, address string) error {
	conn, err := (&net.Dialer{}).DialContext(ctx, "tcp", address)
	if err != nil {
		return err
	}
	return conn.Close()
}

// failuresToDrop consecutive failed checks mark a relay down; one success
// brings it back. A single lost probe doesn't pull a working relay.
const failuresToDrop = 2

// Registry tracks relay health. Relays count as up until checked, so a
// fresh Core doesn't hide them while the first check runs.
type Registry struct {
	relays   []Relay
	dial     Dialer
	timeout  time.Duration
	mu       sync.RWMutex
	failures map[string]int
}

func NewRegistry(relays []Relay, dial Dialer, timeout time.Duration) *Registry {
	if dial == nil {
		dial = tcpDial
	}
	if timeout <= 0 {
		timeout = 5 * time.Second
	}
	return &Registry{relays: relays, dial: dial, timeout: timeout, failures: map[string]int{}}
}

// Healthy returns the relays currently considered reachable, in order.
func (r *Registry) Healthy() []Relay {
	if r == nil {
		return nil
	}
	r.mu.RLock()
	defer r.mu.RUnlock()
	out := make([]Relay, 0, len(r.relays))
	for _, relay := range r.relays {
		if r.failures[relay.Address()] < failuresToDrop {
			out = append(out, relay)
		}
	}
	return out
}

// CheckOnce probes every relay concurrently and updates their state.
func (r *Registry) CheckOnce(ctx context.Context) {
	var wg sync.WaitGroup
	results := make([]error, len(r.relays))
	for i, relay := range r.relays {
		wg.Add(1)
		go func(i int, address string) {
			defer wg.Done()
			cctx, cancel := context.WithTimeout(ctx, r.timeout)
			defer cancel()
			results[i] = r.dial(cctx, address)
		}(i, relay.Address())
	}
	wg.Wait()
	r.mu.Lock()
	defer r.mu.Unlock()
	for i, relay := range r.relays {
		if results[i] != nil {
			r.failures[relay.Address()]++
		} else {
			r.failures[relay.Address()] = 0
		}
	}
}

// Run checks every interval until ctx is done.
func (r *Registry) Run(ctx context.Context, interval time.Duration) {
	if len(r.relays) == 0 {
		return
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		r.CheckOnce(ctx)
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}
