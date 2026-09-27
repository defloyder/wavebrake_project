package runtime

import (
	"context"
	"encoding/json"
	"testing"

	"wavebreak-node/internal/config"
)

const renderState = `{"revision":3,"grants":[{"id":"11111111-1111-1111-1111-111111111111","protocol":"vless","status":"active","label":"WVB-11111111"}]}`

func renderInbounds(t *testing.T, cfg config.XrayConfig) map[string]map[string]any {
	t.Helper()
	out, err := NewXrayAdapter(cfg).Render(context.Background(), json.RawMessage(renderState))
	if err != nil {
		t.Fatal(err)
	}
	var doc struct {
		Inbounds []map[string]any `json:"inbounds"`
	}
	if err := json.Unmarshal(out, &doc); err != nil {
		t.Fatal(err)
	}
	byTag := map[string]map[string]any{}
	for _, ib := range doc.Inbounds {
		byTag[ib["tag"].(string)] = ib
	}
	return byTag
}

func TestRenderXHTTPRealityInbound(t *testing.T) {
	cfg := config.XrayConfig{
		ListenPort: 8443, RealityPrivateKey: "priv", RealityShortID: "ab12", RealityDest: "127.0.0.1:18447", RealityServerName: "r.example.test",
		Flow:                   "xtls-rprx-vision",
		RealityXHTTPListenPort: 8445, RealityXHTTPServerName: "x.example.test", RealityXHTTPDest: "127.0.0.1:18448", RealityXHTTPPath: "/wvb-rx",
	}
	byTag := renderInbounds(t, cfg)
	ib, ok := byTag["vless-xhttp-reality"]
	if !ok {
		t.Fatalf("xhttp-reality inbound missing: %v", byTag)
	}
	stream := ib["streamSettings"].(map[string]any)
	reality := stream["realitySettings"].(map[string]any)
	xhttp := stream["xhttpSettings"].(map[string]any)
	if ib["port"].(float64) != 8445 || stream["network"] != "xhttp" || stream["security"] != "reality" {
		t.Fatalf("inbound: %v", ib)
	}
	if reality["dest"] != "127.0.0.1:18448" || reality["serverNames"].([]any)[0] != "x.example.test" || reality["privateKey"] != "priv" || reality["shortIds"].([]any)[0] != "ab12" {
		t.Fatalf("reality: %v", reality)
	}
	if xhttp["path"] != "/wvb-rx" || xhttp["mode"] != "auto" {
		t.Fatalf("xhttp: %v", xhttp)
	}
	client := ib["settings"].(map[string]any)["clients"].([]any)[0].(map[string]any)
	if client["id"] != "11111111-1111-1111-1111-111111111111" {
		t.Fatalf("client: %v", client)
	}
	if _, hasFlow := client["flow"]; hasFlow {
		t.Fatal("Vision flow must not be set on an XHTTP inbound")
	}
	// The raw REALITY inbound keeps its Vision flow.
	raw := byTag["vless-reality"]["settings"].(map[string]any)["clients"].([]any)[0].(map[string]any)
	if raw["flow"] != "xtls-rprx-vision" {
		t.Fatalf("raw reality client: %v", raw)
	}
	if tags := NewXrayAdapter(cfg).vlessInboundTags(); len(tags) != 2 || tags[1] != "vless-xhttp-reality" {
		t.Fatalf("live user tags: %v", tags)
	}
}

func TestRenderXHTTPRealityDisabledWithoutSNI(t *testing.T) {
	cfg := config.XrayConfig{ListenPort: 8443, RealityPrivateKey: "priv", RealityShortID: "ab12", RealityXHTTPListenPort: 8445, RealityXHTTPDest: "127.0.0.1:18448"}
	if _, ok := renderInbounds(t, cfg)["vless-xhttp-reality"]; ok {
		t.Fatal("inbound must stay off until its SNI is configured")
	}
}
