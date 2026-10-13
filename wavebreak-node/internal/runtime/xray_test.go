package runtime

import (
	"context"
	"encoding/json"
	"testing"

	"wavebreak-node/internal/config"
)

func renderOutbounds(t *testing.T, cfg config.XrayConfig) []map[string]any {
	t.Helper()
	adapter := NewXrayAdapter(cfg)
	out, err := adapter.Render(context.Background(), json.RawMessage(`{}`))
	if err != nil {
		t.Fatalf("Render: %v", err)
	}
	var rendered struct {
		Outbounds []map[string]any `json:"outbounds"`
	}
	if err := json.Unmarshal(out, &rendered); err != nil {
		t.Fatalf("unmarshal rendered config: %v", err)
	}
	return rendered.Outbounds
}

// TestRender_NoChainEgress_DefaultsToDirectOutbound locks in today's
// behavior for every node that doesn't set the ChainEgress* fields
// (every real node right now) — the whole point of making chained egress
// opt-in is that leaving it unset must produce exactly what already runs
// in production, byte for byte in shape.
func TestRender_NoChainEgress_DefaultsToDirectOutbound(t *testing.T) {
	outbounds := renderOutbounds(t, config.XrayConfig{})
	if len(outbounds) == 0 {
		t.Fatal("expected at least one outbound")
	}
	if tag, _ := outbounds[0]["tag"].(string); tag != "direct" {
		t.Fatalf("expected first/default outbound to be \"direct\", got %v", outbounds[0]["tag"])
	}
	for _, ob := range outbounds {
		if ob["tag"] == "to-chain" {
			t.Fatal("to-chain outbound must not appear when ChainEgress* is unset")
		}
	}
}

// TestRender_ChainEgress_PrependsToChainOutbound covers the new opt-in
// path: a node with ChainEgressIP/Port/HopID set should forward egress
// through another WaveBreak node instead of its own direct/freedom
// outbound — see wavebreak-infrastructure/ru-entry/deploy.sh for the
// hand-built version of this exact pattern this makes first-class.
func TestRender_ChainEgress_PrependsToChainOutbound(t *testing.T) {
	cfg := config.XrayConfig{
		ChainEgressIP:    "45.15.41.3",
		ChainEgressPort:  443,
		ChainEgressSNI:   "hop.wavebreak.com.tr",
		ChainEgressHopID: "6d76c86d-1f23-42d9-b4f6-a3c94822642b",
	}
	outbounds := renderOutbounds(t, cfg)
	if len(outbounds) == 0 {
		t.Fatal("expected at least one outbound")
	}
	first := outbounds[0]
	if tag, _ := first["tag"].(string); tag != "to-chain" {
		t.Fatalf("expected first/default outbound to be \"to-chain\", got %v", first["tag"])
	}
	if proto, _ := first["protocol"].(string); proto != "vless" {
		t.Fatalf("expected to-chain outbound protocol vless, got %v", first["protocol"])
	}
	settings, _ := first["settings"].(map[string]any)
	vnext, _ := settings["vnext"].([]any)
	if len(vnext) != 1 {
		t.Fatalf("expected exactly one vnext entry, got %d", len(vnext))
	}
	entry, _ := vnext[0].(map[string]any)
	if addr, _ := entry["address"].(string); addr != cfg.ChainEgressIP {
		t.Errorf("address = %v, want %v", addr, cfg.ChainEgressIP)
	}
	if port, _ := entry["port"].(float64); int(port) != cfg.ChainEgressPort {
		t.Errorf("port = %v, want %v", port, cfg.ChainEgressPort)
	}
	users, _ := entry["users"].([]any)
	if len(users) != 1 {
		t.Fatalf("expected exactly one user, got %d", len(users))
	}
	user, _ := users[0].(map[string]any)
	if id, _ := user["id"].(string); id != cfg.ChainEgressHopID {
		t.Errorf("hop user id = %v, want %v", id, cfg.ChainEgressHopID)
	}
	stream, _ := first["streamSettings"].(map[string]any)
	tlsSettings, _ := stream["tlsSettings"].(map[string]any)
	if sni, _ := tlsSettings["serverName"].(string); sni != cfg.ChainEgressSNI {
		t.Errorf("tls serverName = %v, want %v", sni, cfg.ChainEgressSNI)
	}

	// direct/blocked must still exist, just demoted — nothing should route
	// to them by default once to-chain is the first outbound, but keeping
	// them present is harmless and matches the plan's "additive" intent.
	var sawDirect, sawBlocked bool
	for _, ob := range outbounds {
		switch ob["tag"] {
		case "direct":
			sawDirect = true
		case "blocked":
			sawBlocked = true
		}
	}
	if !sawDirect || !sawBlocked {
		t.Errorf("expected direct and blocked outbounds to still be present, sawDirect=%v sawBlocked=%v", sawDirect, sawBlocked)
	}
}
