package cloak

import (
	"bytes"
	"testing"
)

func TestWrapUnwrapRoundTrip(t *testing.T) {
	profile := DefaultProfile
	payloads := [][]byte{
		{},
		[]byte("a"),
		bytes.Repeat([]byte{0xAB}, 100),
		bytes.Repeat([]byte{0xCD}, profile.MaxSize), // exceeds MaxSize on its own
	}
	for _, payload := range payloads {
		wrapped, err := Wrap(profile, payload)
		if err != nil {
			t.Fatalf("Wrap(%d bytes): %v", len(payload), err)
		}
		got, chaff, err := Unwrap(wrapped)
		if err != nil {
			t.Fatalf("Unwrap: %v", err)
		}
		if chaff {
			t.Fatalf("Unwrap reported chaff for a real data packet")
		}
		if !bytes.Equal(got, payload) {
			t.Fatalf("round trip mismatch: got %d bytes, want %d bytes", len(got), len(payload))
		}
	}
}

func TestWrapPadsWithinProfileRange(t *testing.T) {
	profile := Profile{MinSize: 200, MaxSize: 1350}
	payload := []byte("small")
	for i := 0; i < 200; i++ {
		wrapped, err := Wrap(profile, payload)
		if err != nil {
			t.Fatalf("Wrap: %v", err)
		}
		if len(wrapped) < profile.MinSize || len(wrapped) > profile.MaxSize {
			t.Fatalf("wrapped size %d outside profile range [%d, %d]", len(wrapped), profile.MinSize, profile.MaxSize)
		}
	}
}

func TestWrapNeverShrinksBelowRealPayload(t *testing.T) {
	profile := Profile{MinSize: 10, MaxSize: 20}
	payload := bytes.Repeat([]byte{0x01}, 500) // far exceeds MaxSize
	wrapped, err := Wrap(profile, payload)
	if err != nil {
		t.Fatalf("Wrap: %v", err)
	}
	if len(wrapped) < headerSize+len(payload) {
		t.Fatalf("wrapped packet (%d bytes) truncated real payload (%d bytes)", len(wrapped), len(payload))
	}
	got, chaff, err := Unwrap(wrapped)
	if err != nil || chaff {
		t.Fatalf("Unwrap failed on oversized payload: got=%v chaff=%v err=%v", got, chaff, err)
	}
	if !bytes.Equal(got, payload) {
		t.Fatalf("oversized payload corrupted in round trip")
	}
}

func TestChaffIsRecognizedAndCarriesNoPayload(t *testing.T) {
	profile := DefaultProfile
	for i := 0; i < 50; i++ {
		pkt, err := WrapChaff(profile)
		if err != nil {
			t.Fatalf("WrapChaff: %v", err)
		}
		if len(pkt) < profile.MinSize || len(pkt) > profile.MaxSize {
			t.Fatalf("chaff size %d outside profile range [%d, %d]", len(pkt), profile.MinSize, profile.MaxSize)
		}
		payload, chaff, err := Unwrap(pkt)
		if err != nil {
			t.Fatalf("Unwrap(chaff): %v", err)
		}
		if !chaff {
			t.Fatalf("chaff packet not recognized as chaff")
		}
		if payload != nil {
			t.Fatalf("chaff packet produced a non-nil payload")
		}
	}
}

func TestUnwrapRejectsGarbage(t *testing.T) {
	cases := [][]byte{
		nil,
		{0x01},              // shorter than header
		{0x01, 0x02},        // shorter than header
		{0x99, 0x00, 0x05},  // unknown type byte, header-only
		{0x17, 0xFF, 0xFF},  // typeData claiming 65535 bytes of payload with none present
	}
	for i, c := range cases {
		if _, _, err := Unwrap(c); err == nil {
			t.Fatalf("case %d: Unwrap(%v) did not return an error", i, c)
		}
	}
}

func TestWrapDoesNotAliasPayload(t *testing.T) {
	// Mutating the caller's payload slice after Wrap must not affect the
	// already-wrapped packet — Wrap copies rather than aliasing.
	payload := []byte("mutate-me")
	wrapped, err := Wrap(DefaultProfile, payload)
	if err != nil {
		t.Fatalf("Wrap: %v", err)
	}
	for i := range payload {
		payload[i] = 0xFF
	}
	got, _, err := Unwrap(wrapped)
	if err != nil {
		t.Fatalf("Unwrap: %v", err)
	}
	if bytes.Equal(got, payload) {
		t.Fatalf("Wrap aliased the caller's payload slice instead of copying it")
	}
	if string(got) != "mutate-me" {
		t.Fatalf("wrapped payload corrupted: got %q", got)
	}
}
