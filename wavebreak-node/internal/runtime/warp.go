package runtime

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
)

// Cloudflare WARP as the node's way out for UDP (owner, 14.10). The TR
// host's provider drops UDP replies coming from source ports below 1024
// (other than DNS and NTP): Telegram's call reflectors (UDP 596–599) and
// QUIC (443) never answer, so calls hang on "connecting". Inside a
// WireGuard tunnel to WARP those replies arrive untouched.
//
// The device's keys live next to the Xray config on the node (warp.json,
// root only), never in git. No file: no WARP, the node works as before.
type warpConfig struct {
	SecretKey     string   `json:"secretKey"`
	Address       []string `json:"address"`
	PeerPublicKey string   `json:"peerPublicKey"`
	Endpoint      string   `json:"endpoint"`
	Reserved      []int    `json:"reserved"`
}

// warpSocksPort: a local SOCKS inbound of Xray that Hysteria sends its
// UDP to, so Hysteria2 clients' UDP leaves through WARP too.
const warpSocksPort = 10808

func (a XrayAdapter) warp() *warpConfig {
	raw, err := os.ReadFile(filepath.Join(filepath.Dir(a.cfg.ConfigPath), "warp.json"))
	if err != nil {
		return nil
	}
	var w warpConfig
	if json.Unmarshal(raw, &w) != nil || strings.TrimSpace(w.SecretKey) == "" ||
		strings.TrimSpace(w.PeerPublicKey) == "" || strings.TrimSpace(w.Endpoint) == "" ||
		len(w.Address) == 0 {
		return nil
	}
	return &w
}

func (w *warpConfig) outbound() map[string]any {
	settings := map[string]any{
		"secretKey": w.SecretKey,
		"address":   w.Address,
		"peers": []any{map[string]any{
			"publicKey":  w.PeerPublicKey,
			"endpoint":   w.Endpoint,
			"allowedIPs": []string{"0.0.0.0/0", "::/0"},
		}},
		"mtu":            1280,
		"domainStrategy": "ForceIPv4",
	}
	if len(w.Reserved) > 0 {
		settings["reserved"] = w.Reserved
	}
	return map[string]any{"tag": "warp", "protocol": "wireguard", "settings": settings}
}

// warpRules: every proxied UDP flow except DNS leaves through WARP.
func warpRules() []map[string]any {
	return []map[string]any{{
		"type":        "field",
		"network":     "udp",
		"port":        "0-52,54-65535",
		"outboundTag": "warp",
	}}
}

func warpSocksInbound() map[string]any {
	return map[string]any{
		"tag":      "hy-egress",
		"listen":   "127.0.0.1",
		"port":     warpSocksPort,
		"protocol": "socks",
		"settings": map[string]any{"auth": "noauth", "udp": true, "ip": "127.0.0.1"},
	}
}

// hysteriaWarpYAML: Hysteria's UDP (but DNS) to Xray's local SOCKS, which
// routes it into WARP; TCP stays direct.
func hysteriaWarpYAML() string {
	return `outbounds:
  - name: direct
    type: direct
  - name: warp
    type: socks5
    socks5:
      addr: 127.0.0.1:10808
acl:
  inline:
    - direct(all, udp/53)
    - warp(all, udp)
    - direct(all)
`
}
