package main

import (
	"encoding/json"
	"strings"
	"testing"
)

// Links shaped like Core's (/v1/me/access); credentials are made up.
const (
	realityLink = "vless://11111111-2222-3333-4444-555555555555@tr.example:443?type=tcp&security=reality&pbk=Z84J2IelR9ch3k8VtlVhhs5ycBUlXA7wHBWcBrjqnAw&sid=abcd&sni=www.example.com&fp=chrome&flow=xtls-rprx-vision#%F0%9F%87%B9%F0%9F%87%B7%20Turkey%2C%20Istanbul%20(VLESS)"
	directLink  = "vless://11111111-2222-3333-4444-555555555555@direct.example:443?type=ws&security=tls&sni=direct.example&path=%2Fws&host=direct.example#%F0%9F%87%B7%F0%9F%87%BA%20Russia%20(Direct-TLS)"
	hy2Link     = "hysteria2://secret@hy2.example:8443?sni=hy2.example&obfs=salamander&obfs-password=pw&mport=20000-30000#%F0%9F%87%B9%F0%9F%87%B7%20Turkey%20(Hysteria2)"
	cloakLink   = "hysteria2://secret@hy2.example:8443?cloak=1#x"
)

func TestRealityOutbound(t *testing.T) {
	l, err := ParseShareLink(realityLink)
	if err != nil {
		t.Fatal(err)
	}
	if l.ProtocolName() != "REALITY" {
		t.Fatalf("protocol %s", l.ProtocolName())
	}
	cc, place := l.Place()
	if cc != "TR" || place != "Turkey, Istanbul" {
		t.Fatalf("place %q %q", cc, place)
	}
	out := l.Outbound()
	if out["type"] != "vless" || out["flow"] != "xtls-rprx-vision" || out["server_port"] != 443 {
		t.Fatalf("outbound %v", out)
	}
	tls := out["tls"].(map[string]any)
	reality := tls["reality"].(map[string]any)
	if reality["public_key"] != "Z84J2IelR9ch3k8VtlVhhs5ycBUlXA7wHBWcBrjqnAw" || reality["short_id"] != "abcd" || tls["server_name"] != "www.example.com" || tls["fragment"] != true {
		t.Fatalf("tls %v", tls)
	}
}

func TestDirectTLSOverWebSocket(t *testing.T) {
	l, err := ParseShareLink(directLink)
	if err != nil {
		t.Fatal(err)
	}
	out := l.Outbound()
	if _, ok := out["flow"]; ok {
		t.Fatal("no Vision flow on ws")
	}
	tr := out["transport"].(map[string]any)
	if tr["type"] != "ws" || tr["path"] != "/ws" {
		t.Fatalf("transport %v", tr)
	}
	if cc, place := l.Place(); cc != "RU" || place != "Russia" {
		t.Fatalf("place %q %q", cc, place)
	}
}

func TestHysteria2WithObfsAndHopping(t *testing.T) {
	l, err := ParseShareLink(hy2Link)
	if err != nil {
		t.Fatal(err)
	}
	out := l.Outbound()
	if out["type"] != "hysteria2" || out["password"] != "secret" {
		t.Fatalf("outbound %v", out)
	}
	if ports := out["server_ports"].([]string); len(ports) != 1 || ports[0] != "20000:30000" {
		t.Fatalf("ports %v", ports)
	}
	if _, frag := out["tls"].(map[string]any)["fragment"]; frag {
		t.Fatal("no TCP fragmenting on QUIC")
	}
}

func TestCloakLinkSkipped(t *testing.T) {
	if _, err := ParseShareLink(cloakLink); err == nil {
		t.Fatal("cloak links need the bridge Lite doesn't ship")
	}
}

func TestConfigIsValidJSONWithTun(t *testing.T) {
	l, _ := ParseShareLink(realityLink)
	b, err := json.Marshal(SingBoxConfig(l))
	if err != nil {
		t.Fatal(err)
	}
	s := string(b)
	for _, want := range []string{`"type":"tun"`, `"auto_route":true`, `"final":"proxy"`, `"tag":"direct"`} {
		if !strings.Contains(s, want) {
			t.Fatalf("config lacks %s", want)
		}
	}
}

func TestShadowsocksBothForms(t *testing.T) {
	for _, raw := range []string{
		"ss://YWVzLTI1Ni1nY206cGFzcw@ss.example:8388#x",
		"ss://YWVzLTI1Ni1nY206cGFzc0Bzcy5leGFtcGxlOjgzODg#x",
	} {
		l, err := ParseShareLink(raw)
		if err != nil {
			t.Fatalf("%s: %v", raw, err)
		}
		if l.Method != "aes-256-gcm" || l.Credential != "pass" || l.Host != "ss.example" || l.Port != 8388 {
			t.Fatalf("%s: %+v", raw, l)
		}
	}
}
