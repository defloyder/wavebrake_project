package httpapi

import (
	"strings"
	"testing"

	"wavebreak-core/internal/config"
)

func TestDirectTLSLinkDefaultSuffix(t *testing.T) {
	link := buildVLESSDirectTLSLink(config.VLESSConfig{DirectTLSHost: "h.example", DirectTLSPort: 443}, "g1", "🇷🇺 Russia, Moscow")
	if !strings.Contains(link, "%F0%9F%87%B7%F0%9F%87%BA%20Russia%2C%20Moscow%20%28Direct-TLS%29") {
		t.Fatalf("default suffix changed: %s", link)
	}
}

func TestDirectTLSLinkCustomSuffix(t *testing.T) {
	link := buildVLESSDirectTLSLink(config.VLESSConfig{DirectTLSHost: "h.example", DirectTLSPort: 443, DirectTLSLabel: "YouTube без рекламы"}, "g1", "🇷🇺 Russia, Moscow")
	if !strings.Contains(link, "%28YouTube%20%D0%B1%D0%B5%D0%B7%20%D1%80%D0%B5%D0%BA%D0%BB%D0%B0%D0%BC%D1%8B%29") {
		t.Fatalf("custom suffix not applied: %s", link)
	}
}
