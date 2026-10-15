package httpapi

import (
	"net/url"
	"strings"
	"testing"

	"wavebreak-core/internal/config"
)

func fragmentOf(t *testing.T, link string) string {
	t.Helper()
	i := strings.LastIndex(link, "#")
	if i < 0 {
		t.Fatalf("no fragment in %q", link)
	}
	name, err := url.PathUnescape(link[i+1:])
	if err != nil {
		t.Fatal(err)
	}
	return name
}

func TestLinkNameOverrideIsUsedExactly(t *testing.T) {
	vless := config.VLESSConfig{DirectTLSHost: "de.wavebreak.com.tr", DirectTLSPort: 9443, LinkName: "Germany"}
	if got := fragmentOf(t, buildVLESSDirectTLSLink(vless, "grant", "🇩🇪 Germany")); got != "Germany" {
		t.Fatalf("override name = %q, want Germany", got)
	}
	vless.LinkName = ""
	if got := fragmentOf(t, buildVLESSDirectTLSLink(vless, "grant", "🇩🇪 Germany")); got != "🇩🇪 Germany (Direct-TLS)" {
		t.Fatalf("default name = %q", got)
	}
}
