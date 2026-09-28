package httpapi

import (
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	"wavebreak-core/internal/config"
	"wavebreak-core/internal/relays"
	"wavebreak-core/internal/store"
)

func TestRelayLinkUsesRelayAddressAndLabel(t *testing.T) {
	vless := config.VLESSConfig{PublicHost: "45.15.41.3", PublicPort: 443, RealityPublicKey: "pbk", RealityShortID: "ab12", Fingerprint: "chrome",
		RealityXHTTPServerName: "x.example.test", RealityXHTTPPath: "/wvb-rx"}
	link := buildVLESSRealityXHTTPRelayLink(vless, "11111111-2222-4333-8444-555555555555", relays.Relay{Name: "Moscow", Host: "5.188.1.2", Port: 443}, "🇹🇷 Turkey, Istanbul")
	u, err := url.Parse(link)
	if err != nil {
		t.Fatal(err)
	}
	q := u.Query()
	if u.Host != "5.188.1.2:443" || q.Get("type") != "xhttp" || q.Get("security") != "reality" || q.Get("sni") != "x.example.test" || q.Get("path") != "/wvb-rx" || q.Get("pbk") != "pbk" {
		t.Fatalf("relay link: %s", link)
	}
	if u.Fragment != "🇷🇺 Russia, Moscow → Istanbul (XHTTP)" {
		t.Fatalf("label: %q", u.Fragment)
	}
	if !strings.HasPrefix(link, "vless://11111111-2222-4333-8444-555555555555@5.188.1.2:443?") {
		t.Fatalf("prefix: %s", link)
	}
}

func TestHysteriaObfsLink(t *testing.T) {
	vless := config.VLESSConfig{HysteriaHost: "45.15.41.3", HysteriaPort: 443, HysteriaSNI: "hy2.example.test",
		HysteriaObfsPort: 20443, HysteriaObfsPassword: "s3cr3t", HysteriaObfsHopPorts: "20000-30000"}
	link := buildHysteriaObfsLink(vless, "11111111-2222-4333-8444-555555555555", "🇹🇷 Turkey, Istanbul")
	u, err := url.Parse(link)
	if err != nil {
		t.Fatal(err)
	}
	q := u.Query()
	if u.Scheme != "hysteria2" || u.Host != "45.15.41.3:20443" || q.Get("obfs") != "salamander" ||
		q.Get("obfs-password") != "s3cr3t" || q.Get("mport") != "20000-30000" || q.Get("sni") != "hy2.example.test" {
		t.Fatalf("obfs link: %s", link)
	}
	if u.Fragment != "🇹🇷 Turkey, Istanbul (Hysteria2 Obfs)" {
		t.Fatalf("label: %q", u.Fragment)
	}
	vless.HysteriaObfsHopPorts = ""
	if q := mustQuery(t, buildHysteriaObfsLink(vless, "g", "L")); q.Has("mport") {
		t.Fatal("mport without hop ports configured")
	}
}

func TestAppLinksOfferObfsOnlyToAppsThatRunIt(t *testing.T) {
	cfg := store.AccessGrantConfig{
		Hysteria:     map[string]any{"uri": "hysteria2://plain"},
		HysteriaObfs: map[string]any{"uri": "hysteria2://obfs"},
	}
	old := appLinks(cfg, clientFeatures(httptest.NewRequest(http.MethodPost, "/v1/me/access", nil)))
	if len(old) != 1 || old[0] != "hysteria2://plain" {
		t.Fatalf("older app got: %v", old)
	}
	req := httptest.NewRequest(http.MethodPost, "/v1/me/access", nil)
	req.Header.Set("X-Wavebreak-Features", "smart-routing, Hysteria-Obfs")
	now := appLinks(cfg, clientFeatures(req))
	if len(now) != 2 || now[1] != "hysteria2://obfs" {
		t.Fatalf("new app got: %v", now)
	}
}

func mustQuery(t *testing.T, link string) url.Values {
	t.Helper()
	u, err := url.Parse(link)
	if err != nil {
		t.Fatal(err)
	}
	return u.Query()
}
