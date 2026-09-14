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
	clients := make([]map[string]any, 0, len(desired.Grants))
	for _, grant := range desired.Grants {
		if !isVLESSProtocol(grant.Protocol) || grant.Status != "active" {
			continue
		}
		email := strings.TrimSpace(grant.Label)
		if email == "" {
			email = "WVB-" + strings.ToUpper(strings.ReplaceAll(grant.ID, "-", ""))[:8]
		}
		clients = append(clients, map[string]any{
			"id":    grant.ID,
			"flow":  a.cfg.Flow,
			"email": email,
		})
	}
	rendered := map[string]any{
		"log": map[string]any{"loglevel": "warning"},
		"inbounds": []map[string]any{
			{
				"listen":   "0.0.0.0",
				"port":     a.cfg.ListenPort,
				"protocol": "vless",
				"settings": map[string]any{
					"clients":    clients,
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
						"tcpFastOpen": true,
						"tcpFragment": true,
						"tcpMaxSeg":   1350,
					},
				},
				"sniffing": map[string]any{
					"enabled":      true,
					"destOverride": []string{"http", "tls", "quic"},
				},
			},
		},
		"outbounds": []map[string]any{
			{
				"protocol": "freedom",
				"settings": map[string]any{},
				"sockopt":  map[string]any{"tcpFastOpen": true},
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
