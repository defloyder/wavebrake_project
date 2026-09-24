package runtime

import (
	"context"
	"testing"

	"wavebreak-node/internal/config"
)

func TestApplyIncremental_NoPreviousStateFallsBack(t *testing.T) {
	a := NewXrayAdapter(config.XrayConfig{ListenPort: 443, StatsAPIPort: 19999})
	ok, err := a.ApplyIncremental(context.Background(), nil, []byte(`{"revision":1,"grants":[]}`))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if ok {
		t.Fatal("expected ok=false with no known previous state")
	}
}

func TestApplyIncremental_NoChangeIsHandledWithoutDialing(t *testing.T) {
	a := NewXrayAdapter(config.XrayConfig{ListenPort: 443, StatsAPIPort: 19999})
	state := []byte(`{"revision":1,"grants":[{"id":"11111111-1111-1111-1111-111111111111","protocol":"vless-reality","status":"active","label":"WVB-11111111"}]}`)
	// Same state on both sides: no grant activation flipped, so this must
	// be handled (ok=true) purely from the diff, with no gRPC dial at all
	// — if it tried to dial, this test would fail/hang since nothing is
	// listening on 19999 here.
	ok, err := a.ApplyIncremental(context.Background(), state, state)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !ok {
		t.Fatal("expected ok=true for an unchanged grant list")
	}
}

func TestApplyIncremental_ProtocolChangeWhileActiveFallsBack(t *testing.T) {
	a := NewXrayAdapter(config.XrayConfig{ListenPort: 443, StatsAPIPort: 19999})
	// Both "vless" and "vless-reality" count as the same VLESS family
	// (isVLESSProtocol), so this grant stays "active" on both sides — the
	// underlying protocol string still changed, which this diff doesn't
	// understand, so it must fall back without trying to dial anything.
	prev := []byte(`{"revision":1,"grants":[{"id":"11111111-1111-1111-1111-111111111111","protocol":"vless","status":"active","label":"WVB-11111111"}]}`)
	next := []byte(`{"revision":2,"grants":[{"id":"11111111-1111-1111-1111-111111111111","protocol":"vless-reality","status":"active","label":"WVB-11111111"}]}`)
	ok, err := a.ApplyIncremental(context.Background(), prev, next)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if ok {
		t.Fatal("expected ok=false when a still-active grant's protocol changes underneath it")
	}
}

func TestApplyIncremental_ActivationFlipAttemptsLiveApply(t *testing.T) {
	// A genuine add (nothing -> active) must go through the gRPC path;
	// with nothing listening on the configured port, that dial fails and
	// the adapter must fall back (ok=false) rather than silently doing
	// nothing to a client that's supposed to gain access.
	a := NewXrayAdapter(config.XrayConfig{ListenPort: 443, StatsAPIPort: 19999})
	prev := []byte(`{"revision":1,"grants":[]}`)
	next := []byte(`{"revision":2,"grants":[{"id":"11111111-1111-1111-1111-111111111111","protocol":"vless-reality","status":"active","label":"WVB-11111111"}]}`)
	ok, err := a.ApplyIncremental(context.Background(), prev, next)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if ok {
		t.Fatal("expected ok=false when HandlerService is unreachable")
	}
}

func TestApplyIncremental_MalformedStateFallsBack(t *testing.T) {
	a := NewXrayAdapter(config.XrayConfig{ListenPort: 443, StatsAPIPort: 19999})
	ok, err := a.ApplyIncremental(context.Background(), []byte(`not json`), []byte(`{}`))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if ok {
		t.Fatal("expected ok=false for malformed previous state")
	}
}
