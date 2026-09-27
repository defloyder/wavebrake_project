package httpapi

import (
	"net/url"
	"strings"
	"testing"

	"wavebreak-core/internal/config"
	"wavebreak-core/internal/relays"
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
