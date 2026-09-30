// Package cloak disguises the statistical shape of a Hysteria2/QUIC UDP
// flow — packet sizes and inter-packet timing — rather than its wire
// signature. Salamander/gecko obfuscate the bytes so DPI can't recognize
// the protocol; that didn't survive contact with the network we tested
// against on 2026-09-30 (real handshake, then "timeout: no recent network
// activity" the moment actual proxied data started flowing, identical with
// obfuscation on or off). That symptom matches behavioral/traffic-shape
// classification, not signature matching, so the countermeasure has to
// change the shape: constant-ish packet sizes and inter-arrival timing
// instead of the bursty "handshake, then a spike of proxy data, then
// silence" pattern a bare tunnel produces.
//
// Every datagram on the wire is one of:
//
//	[1 byte type][2 byte big-endian real length][real payload][random padding to targetSize]
//
// targetSize is picked per-packet from [MinSize, MaxSize]; if the real
// payload plus the 3-byte header already exceeds it, the packet is sent at
// its natural size instead (never truncate real data). Chaff packets carry
// no real payload — type byte set, the rest is random bytes, and the
// receiver drops them without surfacing anything to the caller.
package cloak

import (
	"crypto/rand"
	"encoding/binary"
	"errors"
	mathrand "math/rand"
)

const (
	typeData  byte = 0x17 // arbitrary, not a QUIC/TLS record type, so a
	typeChaff byte = 0x2c // packet that leaks past de-obfuscation elsewhere
	// doesn't get mistaken for anything meaningful.

	headerSize = 3 // 1 type byte + 2 length bytes
)

// ErrShortPacket is returned by Unwrap when a datagram is too small to
// contain even the header — never a valid cloak packet.
var ErrShortPacket = errors.New("cloak: packet shorter than header")

// ErrBadLength is returned when the embedded length claims more data than
// the packet actually carries — either corruption or someone not speaking
// this protocol.
var ErrBadLength = errors.New("cloak: embedded length exceeds packet size")

// Profile controls the padding-size distribution and idle-chaff timing.
// Defaults (see DefaultProfile) target "looks roughly like a live video
// call's RTP stream" — small-ish, frequent, fairly uniform packets — rather
// than trying to mimic one specific application's exact fingerprint, which
// would need continuous upkeep as that application changes. This is a
// starting profile to validate the mechanism end to end; the size/timing
// numbers are the first thing to tune against real capture data once this
// is deployed, not a claim that they're already optimal.
type Profile struct {
	// MinSize/MaxSize bound the total wire size (header + payload +
	// padding) of a data packet. Must satisfy MinSize >= headerSize and
	// MaxSize <= your path MTU minus IP/UDP headers (see the mtuBudget
	// note in relay/main.go — 1350 is the safe default used elsewhere in
	// this project's Xray sockopt tuning).
	MinSize int
	MaxSize int

	// ChaffMinInterval/ChaffMaxInterval bound how long the sender waits
	// after the last packet (real or chaff) before it must send another
	// one. Real traffic resets this timer just like chaff does — the
	// point is never leaving a gap that reveals "nothing was happening,"
	// not padding a session that's already busy.
	ChaffMinInterval int64 // milliseconds
	ChaffMaxInterval int64 // milliseconds
}

// DefaultProfile is deliberately conservative: small enough padding
// overhead to not visibly hurt throughput, frequent enough chaff to erase
// the "burst then silence" shape without adding meaningful bandwidth cost
// at idle (worst case ~1350 bytes every 300ms ≈ 36kbps, negligible against
// even a weak mobile connection).
var DefaultProfile = Profile{
	MinSize:          200,
	MaxSize:          1350,
	ChaffMinInterval: 80,
	ChaffMaxInterval: 300,
}

// Wrap packs a real payload into a cloak data packet sized per profile.
// The returned slice is freshly allocated; callers may reuse buf after
// Wrap returns.
func Wrap(profile Profile, payload []byte) ([]byte, error) {
	target := headerSize + len(payload)
	if span := profile.MaxSize - profile.MinSize; span > 0 {
		target = profile.MinSize + mathrand.Intn(span+1) //nolint:gosec // padding size, not a secret
	} else {
		target = profile.MaxSize
	}
	if target < headerSize+len(payload) {
		target = headerSize + len(payload)
	}

	out := make([]byte, target)
	out[0] = typeData
	binary.BigEndian.PutUint16(out[1:3], uint16(len(payload)))
	copy(out[headerSize:], payload)
	if pad := out[headerSize+len(payload):]; len(pad) > 0 {
		if _, err := rand.Read(pad); err != nil {
			// crypto/rand failing is fatal for the process elsewhere in
			// this codebase's threat model too; degrade to zero-padding
			// rather than dropping the packet, since all-zero padding is
			// still padding for size purposes even if less convincing.
			for i := range pad {
				pad[i] = 0
			}
		}
	}
	return out, nil
}

// WrapChaff builds a dummy packet of a random size in [profile.MinSize,
// profile.MaxSize] with no real payload. The receiver's Unwrap reports it
// via the ok=false, chaff=true return so callers can drop it silently.
func WrapChaff(profile Profile) ([]byte, error) {
	target := profile.MaxSize
	if span := profile.MaxSize - profile.MinSize; span > 0 {
		target = profile.MinSize + mathrand.Intn(span+1) //nolint:gosec
	}
	if target < headerSize {
		target = headerSize
	}
	out := make([]byte, target)
	out[0] = typeChaff
	if _, err := rand.Read(out[1:]); err != nil {
		for i := 1; i < len(out); i++ {
			out[i] = 0
		}
	}
	return out, nil
}

// Unwrap extracts the real payload from a cloak packet. chaff reports
// whether pkt was a dummy packet (payload is always nil in that case);
// callers should just discard those rather than treating them as an error.
// The returned payload aliases pkt — copy it before the caller's receive
// buffer is reused for the next read.
func Unwrap(pkt []byte) (payload []byte, chaff bool, err error) {
	if len(pkt) < headerSize {
		return nil, false, ErrShortPacket
	}
	switch pkt[0] {
	case typeChaff:
		return nil, true, nil
	case typeData:
		n := int(binary.BigEndian.Uint16(pkt[1:3]))
		if headerSize+n > len(pkt) {
			return nil, false, ErrBadLength
		}
		return pkt[headerSize : headerSize+n], false, nil
	default:
		return nil, false, ErrBadLength
	}
}
