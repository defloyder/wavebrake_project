package bridge

import (
	_ "embed"
	"os"
	"path/filepath"
	"sync"
)

// Xray-core's router resolves "geosite:ru"/"geoip:ru" rules (see routing.go)
// by reading geoip.dat/geosite.dat off disk from the directory named by the
// XRAY_LOCATION_ASSET env var — there's no API to hand it the bytes
// in-memory. Embedding the compiled databases straight into this Go binary
// (rather than shipping them as separate Flutter/Android assets and wiring
// up a Kotlin-side extraction step) means gomobile bundles them
// automatically with everything else and there's no separate "did the app
// actually ship these files" failure mode to get wrong — this package
// writes them out to a caller-supplied writable directory once, the first
// time a smart-routing rule set is actually needed.
//go:embed geodata/geoip.dat
var geoipDat []byte

//go:embed geodata/geosite.dat
var geositeDat []byte

var geoAssetsOnce sync.Once

// EnsureGeoAssets writes geoip.dat/geosite.dat into dir (an app-writable
// directory — Kotlin passes its own filesDir) if they're not already there,
// and points Xray-core's router at that directory. Safe to call every time
// a connection is about to start; the actual extraction only happens once
// per process.
func EnsureGeoAssets(dir string) string {
	geoAssetsOnce.Do(func() {
		_ = os.MkdirAll(dir, 0o755)
		_ = writeIfMissing(filepath.Join(dir, "geoip.dat"), geoipDat)
		_ = writeIfMissing(filepath.Join(dir, "geosite.dat"), geositeDat)
	})
	_ = os.Setenv("XRAY_LOCATION_ASSET", dir)
	return dir
}

func writeIfMissing(path string, data []byte) error {
	if info, err := os.Stat(path); err == nil && info.Size() == int64(len(data)) {
		return nil
	}
	return os.WriteFile(path, data, 0o644)
}
