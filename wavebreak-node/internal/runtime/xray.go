package runtime

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"wavebreak-node/internal/config"
)

type XrayAdapter struct {
	cfg config.XrayConfig
}

type xrayDesiredState struct {
	Revision int         `json:"revision"`
	NodeID   string      `json:"node_id"`
	Grants   []xrayGrant `json:"grants"`
}

type xrayGrant struct {
	ID       string `json:"id"`
	Protocol string `json:"protocol"`
	Status   string `json:"status"`
	Label    string `json:"label"`
}

func NewXrayAdapter(cfg config.XrayConfig) XrayAdapter {
	return XrayAdapter{cfg: cfg}
}

func (a XrayAdapter) Validate(_ context.Context, state json.RawMessage) error {
	if strings.TrimSpace(a.cfg.RealityPrivateKey) == "" {
		return fmt.Errorf("WAVEBREAK_XRAY_REALITY_PRIVATE_KEY is required")
	}
	if strings.TrimSpace(a.cfg.RealityShortID) == "" {
		return fmt.Errorf("WAVEBREAK_XRAY_REALITY_SHORT_ID is required")
	}
	var desired xrayDesiredState
	if len(state) == 0 {
		return nil
	}
	if err := json.Unmarshal(state, &desired); err != nil {
		return fmt.Errorf("decode desired state: %w", err)
	}
	for _, grant := range desired.Grants {
		if !isVLESSProtocol(grant.Protocol) {
			continue
		}
		if !isUUIDLike(grant.ID) {
			return fmt.Errorf("grant %q is not a valid VLESS UUID", grant.ID)
		}
	}
	return nil
}

func (a XrayAdapter) Render(_ context.Context, state json.RawMessage) ([]byte, error) {
	var desired xrayDesiredState
	if len(state) != 0 {
		if err := json.Unmarshal(state, &desired); err != nil {
			return nil, err
		}
	}
	vlessClients := make([]map[string]any, 0, len(desired.Grants))
	vlessClientsNoFlow := make([]map[string]any, 0, len(desired.Grants))
	ssClients := make([]map[string]any, 0, len(desired.Grants))
	for _, grant := range desired.Grants {
		if !isVLESSProtocol(grant.Protocol) || grant.Status != "active" {
			continue
		}
		email := strings.TrimSpace(grant.Label)
		if email == "" {
			email = "WVB-" + strings.ToUpper(strings.ReplaceAll(grant.ID, "-", ""))[:8]
		}
		vlessClient := map[string]any{
			"id":    grant.ID,
			"email": email,
		}
		if xrayFlowEnabled(a.cfg.Flow) {
			vlessClient["flow"] = a.cfg.Flow
		}
		vlessClients = append(vlessClients, vlessClient)
		// The WS+TLS/CDN inbound is a separate stream transport, not raw
		// TCP, and XTLS Vision's flow only applies to the latter — Xray
		// rejects it here, so this inbound always gets a flow-less client.
		vlessClientsNoFlow = append(vlessClientsNoFlow, map[string]any{
			"id":    grant.ID,
			"email": email,
		})
		ssClients = append(ssClients, map[string]any{
			"password": grant.ID,
			"method":   a.cfg.ShadowsocksMethod,
			"email":    email,
		})
	}
	inbounds := []map[string]any{
		{
			"tag":      "vless-reality",
			"listen":   "0.0.0.0",
			"port":     a.cfg.ListenPort,
			"protocol": "vless",
			"settings": map[string]any{
				"clients":    vlessClients,
				"decryption": "none",
			},
			"streamSettings": map[string]any{
				"network":  "tcp",
				"security": "reality",
				"realitySettings": map[string]any{
					"show":        false,
					"xver":        0,
					"dest":        a.cfg.RealityDest,
					"serverNames": []string{a.cfg.RealityServerName},
					"privateKey":  a.cfg.RealityPrivateKey,
					"shortIds":    []string{a.cfg.RealityShortID},
				},
				"sockopt": map[string]any{
					"tcpMaxSeg": 1200,
				},
			},
			"sniffing": map[string]any{
				"enabled":      true,
				"destOverride": []string{"http", "tls", "quic"},
			},
		},
	}
	// CDN transport: VLESS over WebSocket+TLS, meant to be proxied through a
	// CDN (Cloudflare orange-cloud) so the outer TLS handshake terminates at
	// the CDN edge with a real, CA-issued certificate for the public domain
	// — indistinguishable from any other site behind that CDN. This is the
	// answer to active/behavioral DPI that fingerprints REALITY's traffic
	// shape rather than just its SNI: nothing about this connection's outer
	// TLS session is unusual at all. Requires cert/key files already placed
	// on the shared config volume (see CDNTLSCertPath/CDNTLSKeyPath).
	if a.cfg.CDNListenPort > 0 && strings.TrimSpace(a.cfg.CDNTLSCertPath) != "" && strings.TrimSpace(a.cfg.CDNTLSKeyPath) != "" {
		wsPath := strings.TrimSpace(a.cfg.CDNWSPath)
		if wsPath == "" {
			wsPath = "/wvb-ws"
		}
		inbounds = append(inbounds, map[string]any{
			"tag":      "vless-cdn-ws",
			"listen":   "0.0.0.0",
			"port":     a.cfg.CDNListenPort,
			"protocol": "vless",
			"settings": map[string]any{
				"clients":    vlessClientsNoFlow,
				"decryption": "none",
			},
			"streamSettings": map[string]any{
				"network":  "ws",
				"security": "tls",
				"tlsSettings": map[string]any{
					"certificates": []map[string]any{
						{
							"certificateFile": a.cfg.CDNTLSCertPath,
							"keyFile":         a.cfg.CDNTLSKeyPath,
						},
					},
				},
				"wsSettings": map[string]any{
					"path": wsPath,
				},
			},
			"sniffing": map[string]any{
				"enabled":      true,
				"destOverride": []string{"http", "tls", "quic"},
			},
		})
	}
	// A second, structurally different protocol (Shadowsocks over plain TCP,
	// no REALITY/TLS fingerprint at all) gives clients a fallback transport
	// when a network specifically targets REALITY/XTLS-Vision traffic
	// patterns, without touching the primary VLESS+REALITY inbound.
	if a.cfg.ShadowsocksPort > 0 {
		inbounds = append(inbounds, map[string]any{
			"tag":      "shadowsocks",
			"listen":   "0.0.0.0",
			"port":     a.cfg.ShadowsocksPort,
			"protocol": "shadowsocks",
			"settings": map[string]any{
				"clients": ssClients,
				"network": "tcp,udp",
			},
			"sniffing": map[string]any{
				"enabled":      true,
				"destOverride": []string{"http", "tls", "quic"},
			},
		})
	}
	rendered := map[string]any{
		"log":      map[string]any{"loglevel": "warning"},
		"inbounds": inbounds,
		"dns": map[string]any{
			"queryStrategy": "UseIPv4",
			"servers": []any{
				"1.1.1.1",
				"8.8.8.8",
				"localhost",
			},
		},
		"routing": map[string]any{
			"domainStrategy": "IPIfNonMatch",
			"rules": []map[string]any{
				{
					"type":        "field",
					"ip":          []string{"10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.0/8", "fc00::/7"},
					"outboundTag": "blocked",
				},
			},
		},
		"policy": map[string]any{
			"levels": map[string]any{
				"0": map[string]any{
					"handshake":         4,
					"connIdle":          300,
					"uplinkOnly":        2,
					"downlinkOnly":      5,
					"statsUserUplink":   true,
					"statsUserDownlink": true,
				},
			},
		},
		"outbounds": []map[string]any{
			{
				"tag":      "direct",
				"protocol": "freedom",
				"settings": map[string]any{},
				"sockopt": map[string]any{
					"domainStrategy": "UseIPv4",
					"tcpMaxSeg":      1200,
				},
			},
			{"protocol": "blackhole", "tag": "blocked"},
		},
	}
	return json.MarshalIndent(rendered, "", "  ")
}

func (a XrayAdapter) Apply(ctx context.Context, rendered []byte) error {
	if err := os.MkdirAll(filepath.Dir(a.cfg.ConfigPath), 0o755); err != nil {
		return err
	}
	tmp := a.cfg.ConfigPath + ".tmp"
	if err := os.WriteFile(tmp, rendered, 0o644); err != nil {
		return err
	}
	if err := os.Rename(tmp, a.cfg.ConfigPath); err != nil {
		return err
	}
	if strings.TrimSpace(a.cfg.DockerContainer) != "" {
		return a.restartDockerContainer(ctx)
	}
	return nil
}

func (a XrayAdapter) Health(context.Context) error {
	if _, err := os.Stat(a.cfg.ConfigPath); err != nil {
		return err
	}
	return nil
}

func (a XrayAdapter) Rollback(context.Context) error {
	return nil
}

func (a XrayAdapter) restartDockerContainer(ctx context.Context) error {
	transport := &http.Transport{
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, "unix", a.cfg.DockerSocket)
		},
	}
	client := &http.Client{Transport: transport, Timeout: 15 * time.Second}
	path := "/containers/" + strings.TrimSpace(a.cfg.DockerContainer) + "/restart?t=5"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "http://docker"+path, bytes.NewReader(nil))
	if err != nil {
		return err
	}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return fmt.Errorf("restart xray container returned status %d", resp.StatusCode)
	}
	return nil
}

func isVLESSProtocol(protocol string) bool {
	switch strings.ToLower(strings.TrimSpace(protocol)) {
	case "vless", "vless-reality":
		return true
	default:
		return false
	}
}

func isUUIDLike(value string) bool {
	if len(value) != 36 {
		return false
	}
	for i, r := range value {
		switch i {
		case 8, 13, 18, 23:
			if r != '-' {
				return false
			}
		default:
			if (r < '0' || r > '9') && (r < 'a' || r > 'f') && (r < 'A' || r > 'F') {
				return false
			}
		}
	}
	return true
}

func xrayFlowEnabled(flow string) bool {
	switch strings.ToLower(strings.TrimSpace(flow)) {
	case "", "none", "off", "false", "0":
		return false
	default:
		return true
	}
}
