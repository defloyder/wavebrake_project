package runtime

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"wavebreak-node/internal/config"
)

// warp.json next to the Xray config: UDP (but DNS) leaves through WARP,
// Hysteria sends its UDP there too; without the file nothing changes.
func TestRenderWARP(t *testing.T) {
	dir := t.TempDir()
	cfg := config.XrayConfig{ConfigPath: filepath.Join(dir, "config.json"), ListenPort: 8443,
		RealityPrivateKey: "priv", RealityShortID: "ab12", RealityDest: "127.0.0.1:1", RealityServerName: "r.example.test"}
	render := func() map[string]any {
		out, err := NewXrayAdapter(cfg).Render(context.Background(), json.RawMessage(renderState))
		if err != nil {
			t.Fatal(err)
		}
		var doc map[string]any
		if err := json.Unmarshal(out, &doc); err != nil {
			t.Fatal(err)
		}
		return doc
	}
	if strings.Contains(mustJSON(render()), `"warp"`) {
		t.Fatal("WARP without warp.json")
	}
	if strings.Contains(NewXrayAdapter(cfg).renderHysteriaYAML(hysteriaInstance{listenPort: 443}), "socks5") {
		t.Fatal("Hysteria ACL without warp.json")
	}

	os.WriteFile(filepath.Join(dir, "warp.json"), []byte(`{"secretKey":"k","address":["172.16.0.2/32"],"peerPublicKey":"p","endpoint":"engage.cloudflareclient.com:2408","reserved":[1,2,3]}`), 0o600)
	doc := render()
	var warpOut map[string]any
	for _, o := range doc["outbounds"].([]any) {
		if m := o.(map[string]any); m["tag"] == "warp" {
			warpOut = m
		}
	}
	if warpOut == nil || warpOut["protocol"] != "wireguard" {
		t.Fatalf("no WARP outbound: %v", doc["outbounds"])
	}
	rules := mustJSON(doc["routing"])
	if !strings.Contains(rules, `"outboundTag":"warp"`) || !strings.Contains(rules, `"port":"0-52,54-65535"`) {
		t.Fatalf("no UDP rule to WARP: %s", rules)
	}
	if !strings.Contains(mustJSON(doc["inbounds"]), `"hy-egress"`) {
		t.Fatal("no local SOCKS for Hysteria")
	}
	hy := NewXrayAdapter(cfg).renderHysteriaYAML(hysteriaInstance{listenPort: 443})
	if !strings.Contains(hy, "addr: 127.0.0.1:10808") || !strings.Contains(hy, "warp(all, udp)") {
		t.Fatalf("Hysteria ACL: %s", hy)
	}
}

func mustJSON(v any) string {
	b, _ := json.Marshal(v)
	return string(b)
}
