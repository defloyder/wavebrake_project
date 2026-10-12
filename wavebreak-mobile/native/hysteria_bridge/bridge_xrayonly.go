//go:build xrayonly

package bridge

import "errors"

// The Android TV build (build_aar.sh xray): Xray-core only — no apernet
// Hysteria2 client and no cloak. Hysteria2 runs on Xray's own client
// there; cloak links (cloak=1), which only the apernet client can wrap,
// are hidden by the app on TV. Same exported surface as bridge.go so the
// Kotlin side builds unchanged.

var errXrayOnly = errors.New("hysteria bridge not included in this build")

// Start always fails in this build: see the file comment.
func Start(link string) (int, error) { return 0, errXrayOnly }

// Stop does nothing in this build.
func Stop() {}

// IsRunning is always false in this build.
func IsRunning() bool { return false }
