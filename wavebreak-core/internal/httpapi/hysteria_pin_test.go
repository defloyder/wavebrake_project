package httpapi

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/pem"
	"math/big"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"wavebreak-core/internal/app"
	"wavebreak-core/internal/config"
	"wavebreak-core/internal/store"
)

// selfSignedPEM writes a key + certificate chain file the way certbot's
// fullchain.pem looks (a non-certificate block first, to exercise the scan).
func selfSignedPEM(t *testing.T, dir, cn string) (path string, sum string) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	tpl := &x509.Certificate{SerialNumber: big.NewInt(time.Now().UnixNano()), Subject: pkix.Name{CommonName: cn},
		NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour), DNSNames: []string{cn}}
	der, err := x509.CreateCertificate(rand.Reader, tpl, tpl, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	keyDER, _ := x509.MarshalECPrivateKey(key)
	body := append(pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: keyDER}),
		pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})...)
	path = filepath.Join(dir, "hy-cert.pem")
	if err := os.WriteFile(path, body, 0o600); err != nil {
		t.Fatal(err)
	}
	s := sha256.Sum256(der)
	return path, hex.EncodeToString(s[:])
}

func TestHysteriaPinnedLinkOnlyForPinningApps(t *testing.T) {
	dir := t.TempDir()
	certPath, want := selfSignedPEM(t, dir, "hy2.example.test")
	vless := config.VLESSConfig{
		PublicHost: "45.15.41.3", PublicPort: 443, RealityPublicKey: "pbk", RealityShortID: "ab12", Fingerprint: "chrome",
		HysteriaHost: "45.15.41.3", HysteriaPort: 443, HysteriaSNI: "hy2.example.test",
		HysteriaPinnedSNI: "www.example.com", HysteriaCertFile: certPath,
	}
	s := &Server{app: &app.App{Config: config.Config{VLESS: vless}}}
	cfg := store.AccessGrantConfig{Grant: store.AccessGrant{ID: "11111111-2222-4333-8444-555555555555", Protocol: "vless", Status: "active"}}
	s.applyVLESSRuntimeConfig(&cfg)

	pinned := uriOf(cfg.HysteriaPinned)
	q := mustQuery(t, pinned)
	if q.Get("sni") != "www.example.com" || q.Get("pinSHA256") != want || q.Get("insecure") != "" {
		t.Fatalf("pinned link: %s (want pin %s)", pinned, want)
	}
	for _, l := range cfg.Links {
		if strings.Contains(l, "pinSHA256") {
			t.Fatal("pinned link leaked into the plain list (third-party clients)")
		}
	}

	plain := func(features string) string {
		req := httptest.NewRequest(http.MethodPost, "/v1/me/access", nil)
		if features != "" {
			req.Header.Set("X-Wavebreak-Features", features)
		}
		for _, l := range appLinks(cfg, clientFeatures(req)) {
			if strings.HasPrefix(l, "hysteria2://") {
				return l
			}
		}
		return ""
	}
	if got := plain("hysteria-obfs"); !strings.Contains(got, "sni=hy2.example.test") {
		t.Fatalf("older app got %s", got)
	}
	if got := plain("hysteria-obfs,hysteria-pin"); got != pinned {
		t.Fatalf("pinning app got %s", got)
	}

	// A renewed certificate is picked up without a restart.
	time.Sleep(10 * time.Millisecond)
	_, renewed := selfSignedPEM(t, dir, "hy2.example.test")
	later := time.Now().Add(time.Second)
	_ = os.Chtimes(certPath, later, later)
	cfg2 := store.AccessGrantConfig{Grant: cfg.Grant}
	s.applyVLESSRuntimeConfig(&cfg2)
	if q := mustQuery(t, uriOf(cfg2.HysteriaPinned)); q.Get("pinSHA256") != renewed || renewed == want {
		t.Fatalf("renewed cert not picked up: %s", uriOf(cfg2.HysteriaPinned))
	}

	// Not configured: no pinned variant, nothing breaks.
	s2 := &Server{app: &app.App{Config: config.Config{VLESS: config.VLESSConfig{
		PublicHost: "45.15.41.3", PublicPort: 443, RealityPublicKey: "pbk", RealityShortID: "ab12",
		HysteriaHost: "45.15.41.3", HysteriaPort: 443}}}}
	cfg3 := store.AccessGrantConfig{Grant: cfg.Grant}
	s2.applyVLESSRuntimeConfig(&cfg3)
	if cfg3.HysteriaPinned != nil || cfg3.Hysteria == nil {
		t.Fatalf("unconfigured: %v %v", cfg3.HysteriaPinned, cfg3.Hysteria)
	}
}
