package runtime

import (
	"context"
	"encoding/json"
	"testing"

	"wavebreak-node/internal/config"
)

func renderConfig(t *testing.T, cfg config.XrayConfig) (inbounds, outbounds []map[string]any) {
	t.Helper()
	adapter := NewXrayAdapter(cfg)
	out, err := adapter.Render(context.Background(), json.RawMessage(`{}`))
	if err != nil {
		t.Fatalf("Render: %v", err)
	}
	var rendered struct {
		Inbounds  []map[string]any `json:"inbounds"`
		Outbounds []map[string]any `json:"outbounds"`
	}
	if err := json.Unmarshal(out, &rendered); err != nil {
		t.Fatalf("unmarshal rendered config: %v", err)
	}
	return rendered.Inbounds, rendered.Outbounds
}

func renderOutbounds(t *testing.T, cfg config.XrayConfig) []map[string]any {
	t.Helper()
	_, outbounds := renderConfig(t, cfg)
	return outbounds
}

// realityInbound finds the REALITY-security vless inbound among the
// rendered inbounds and returns its realitySettings.serverNames, or fails
// the test if no such inbound is present.
func realityServerNames(t *testing.T, inbounds []map[string]any) []string {
	t.Helper()
	for _, ib := range inbounds {
		stream, _ := ib["streamSettings"].(map[string]any)
		if stream == nil || stream["security"] != "reality" {
			continue
		}
		reality, _ := stream["realitySettings"].(map[string]any)
		rawNames, _ := reality["serverNames"].([]any)
		names := make([]string, len(rawNames))
		for i, n := range rawNames {
			names[i], _ = n.(string)
		}
		return names
	}
	t.Fatal("no REALITY inbound found in rendered config")
	return nil
}

// baseRealityConfig is the minimum XrayConfig that makes Render produce a
// REALITY inbound at all (ListenPort > 0 gates it, Validate requires the
// key/shortID pair) — callers add RealityServerName(sExtra) on top.
func baseRealityConfig() config.XrayConfig {
	return config.XrayConfig{
		ListenPort:        18443,
		RealityPrivateKey: "test-private-key",
		RealityShortID:    "0123456789abcdef",
		RealityDest:       "ya.ru:443",
	}
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

// TestRender_AcceptProxyProtocol_DefaultsOffMatchesTodaysBehavior locks in
// every existing node's config (the flag unset): no inbound should carry
// acceptProxyProtocol, since a node not sitting behind an nginx
// `proxy_protocol on` stream block would break if Xray suddenly expected
// a PROXY preamble that never arrives.
func TestRender_AcceptProxyProtocol_DefaultsOffMatchesTodaysBehavior(t *testing.T) {
	cfg := baseRealityConfig()
	inbounds, _ := renderConfig(t, cfg)
	for _, ib := range inbounds {
		stream, _ := ib["streamSettings"].(map[string]any)
		if stream == nil {
			continue
		}
		sockopt, _ := stream["sockopt"].(map[string]any)
		if sockopt["acceptProxyProtocol"] != nil {
			t.Fatalf("inbound %v: acceptProxyProtocol must be absent when AcceptProxyProtocol is unset, got %v", ib["tag"], sockopt["acceptProxyProtocol"])
		}
	}
}

// TestRender_AcceptProxyProtocol_EnabledSetsItOnRealityInbound covers the
// new opt-in path this node needs — found live deploying it behind
// wavebreak-infrastructure/ru-entry-style nginx SNI routing with
// `proxy_protocol on`; without this, every connection through that proxy
// fails with an immediate reset.
func TestRender_AcceptProxyProtocol_EnabledSetsItOnRealityInbound(t *testing.T) {
	cfg := baseRealityConfig()
	cfg.AcceptProxyProtocol = true
	inbounds, _ := renderConfig(t, cfg)
	for _, ib := range inbounds {
		stream, _ := ib["streamSettings"].(map[string]any)
		if stream == nil || stream["security"] != "reality" {
			continue
		}
		sockopt, _ := stream["sockopt"].(map[string]any)
		if accept, _ := sockopt["acceptProxyProtocol"].(bool); !accept {
			t.Fatalf("expected acceptProxyProtocol=true on the REALITY inbound, got %v", sockopt["acceptProxyProtocol"])
		}
		return
	}
	t.Fatal("no REALITY inbound found")
}

// TestRender_RealityServerNames_SingularOnlyMatchesTodaysBehavior locks in
// every existing node's config (only WAVEBREAK_XRAY_REALITY_SERVER_NAME
// set, the new _EXTRA var left unset): REALITY must still accept exactly
// one SNI, unchanged.
func TestRender_RealityServerNames_SingularOnlyMatchesTodaysBehavior(t *testing.T) {
	cfg := baseRealityConfig()
	cfg.RealityServerName = "www.microsoft.com"
	inbounds, _ := renderConfig(t, cfg)
	names := realityServerNames(t, inbounds)
	if len(names) != 1 || names[0] != "www.microsoft.com" {
		t.Fatalf("serverNames = %v, want exactly [\"www.microsoft.com\"]", names)
	}
}

// TestRender_RealityServerNames_ExtraAppendsAllValues covers the new
// opt-in multi-SNI path (same masquerade-domain diversification already
// proven in wavebreak-infrastructure/ru-entry/deploy.sh): the primary
// name plus every extra, no duplicates, primary always first.
func TestRender_RealityServerNames_ExtraAppendsAllValues(t *testing.T) {
	cfg := baseRealityConfig()
	cfg.RealityServerName = "ya.ru"
	cfg.RealityServerNamesExtra = []string{"yandex.ru", "mail.ru", "vk.com", "ya.ru"}
	inbounds, _ := renderConfig(t, cfg)
	names := realityServerNames(t, inbounds)
	want := []string{"ya.ru", "yandex.ru", "mail.ru", "vk.com"}
	if len(names) != len(want) {
		t.Fatalf("serverNames = %v, want %v (duplicate primary name must be deduped)", names, want)
	}
	for i, w := range want {
		if names[i] != w {
			t.Errorf("serverNames[%d] = %q, want %q", i, names[i], w)
		}
	}
}

// TestDockerClient_ReusesTransportPerSocket locks in the fix for a real
// memory leak found live (owner, 14.10, ~300MB RSS after a week on a
// ~1GB node): dockerClient must hand back the same *http.Client — and so
// the same *http.Transport, connection pool and keep-alive goroutines —
// for repeated calls against the same DockerSocket, since QueryUsage calls
// it several times every UsageInterval via dockerExec/dockerRequest, and a
// fresh never-reused Transport each time leaks until Go's GC finalizes it.
func TestDockerClient_ReusesTransportPerSocket(t *testing.T) {
	a1 := NewXrayAdapter(config.XrayConfig{DockerSocket: "tcp://127.0.0.1:2375"})
	a2 := NewXrayAdapter(config.XrayConfig{DockerSocket: "tcp://127.0.0.1:2375"})
	c1 := a1.dockerClient()
	c2 := a2.dockerClient()
	if c1 != c2 {
		t.Fatal("dockerClient returned a different *http.Client for the same DockerSocket on a second call — the old Transport (and its connection pool/goroutines) leaks")
	}

	other := NewXrayAdapter(config.XrayConfig{DockerSocket: "tcp://127.0.0.1:9999"})
	c3 := other.dockerClient()
	if c3 == c1 {
		t.Fatal("dockerClient returned the same *http.Client for a different DockerSocket — would dial the wrong target")
	}
}
