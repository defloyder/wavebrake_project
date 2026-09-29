package httpapi

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/pem"
	"errors"
	"fmt"
	"net"
	"net/url"
	"os"
	"strconv"
	"sync"
	"time"

	"wavebreak-core/internal/config"
)

// Hysteria2 with a neutral SNI and a pinned certificate (see
// config.VLESSConfig.HysteriaPinnedSNI). Field reports (Alfa LTE and a home
// Wi-Fi, 2026-09-29): UDP to the node gets through — the QUIC ping answers
// — but the Hysteria handshake never arrives, while other networks
// connect: the QUIC Initial is dropped by its SNI (hy2.wavebreak.com.tr).
// The server doesn't look at the SNI, so the client may send any name and
// verify the server by the certificate's hash instead.

const featureHysteriaPin = "hysteria-pin"

var hysteriaPin struct {
	sync.Mutex
	path    string
	modTime time.Time
	size    int64
	hex     string
}

// certPinSHA256: hex SHA-256 of the first certificate in a PEM file (what
// Xray's pinnedPeerCertSha256 and Hysteria's pinSHA256 compare against).
// Re-read only when the file changes.
func certPinSHA256(path string) (string, error) {
	info, err := os.Stat(path)
	if err != nil {
		return "", err
	}
	hysteriaPin.Lock()
	defer hysteriaPin.Unlock()
	if hysteriaPin.path == path && hysteriaPin.modTime.Equal(info.ModTime()) && hysteriaPin.size == info.Size() {
		return hysteriaPin.hex, nil
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	var block *pem.Block
	for rest := raw; ; {
		block, rest = pem.Decode(rest)
		if block == nil {
			return "", errors.New("no certificate in " + path)
		}
		if block.Type == "CERTIFICATE" {
			break
		}
	}
	sum := sha256.Sum256(block.Bytes)
	hysteriaPin.path, hysteriaPin.modTime, hysteriaPin.size = path, info.ModTime(), info.Size()
	hysteriaPin.hex = hex.EncodeToString(sum[:])
	return hysteriaPin.hex, nil
}

// buildHysteriaPinnedLink: the plain Hysteria2 link with the neutral SNI and
// the certificate pin instead of hy2.wavebreak.com.tr.
func buildHysteriaPinnedLink(vless config.VLESSConfig, grantID, location, pin string) string {
	label := fmt.Sprintf("%s (Hysteria2)", location)
	endpoint := net.JoinHostPort(vless.HysteriaHost, strconv.Itoa(vless.HysteriaPort))
	auth := fmt.Sprintf("%s:%s", grantID, grantID)
	query := url.Values{}
	query.Set("sni", vless.HysteriaPinnedSNI)
	query.Set("alpn", "h3")
	query.Set("pinSHA256", pin)
	return fmt.Sprintf("hysteria2://%s@%s/?%s#%s", auth, endpoint, query.Encode(), url.PathEscape(label))
}
