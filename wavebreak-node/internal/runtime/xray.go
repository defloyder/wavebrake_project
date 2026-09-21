package runtime

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"wavebreak-node/internal/config"
)

type XrayAdapter struct {
	cfg config.XrayConfig
	// hyUsers is populated by Render and read by Apply so the Hysteria2
	// sidecar's user list stays in sync with the same desired-state grants
	// Xray just rendered, without changing the RuntimeAdapter interface.
	// A pointer field so it survives XrayAdapter being passed by value.
	hyUsers *[]hysteriaUser
}

type hysteriaUser struct {
	ID    string
	Email string
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
	return XrayAdapter{cfg: cfg, hyUsers: &[]hysteriaUser{}}
}

func (a XrayAdapter) Validate(_ context.Context, state json.RawMessage) error {
	if a.cfg.ListenPort > 0 {
		if strings.TrimSpace(a.cfg.RealityPrivateKey) == "" {
			return fmt.Errorf("WAVEBREAK_XRAY_REALITY_PRIVATE_KEY is required")
		}
		if strings.TrimSpace(a.cfg.RealityShortID) == "" {
			return fmt.Errorf("WAVEBREAK_XRAY_REALITY_SHORT_ID is required")
		}
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
	trojanClients := make([]map[string]any, 0, len(desired.Grants))
	hyUsers := make([]hysteriaUser, 0, len(desired.Grants))
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
		trojanClients = append(trojanClients, map[string]any{
			"password": grant.ID,
			"email":    email,
		})
		hyUsers = append(hyUsers, hysteriaUser{ID: grant.ID, Email: email})
	}
	if a.hyUsers != nil {
		*a.hyUsers = hyUsers
	}
	inbounds := []map[string]any{}
	if a.cfg.ListenPort > 0 {
		inbounds = append(inbounds, map[string]any{
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
		})
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
					// Sends a WS ping frame this often so the connection
					// keeps looking active to Cloudflare's edge — on the
					// free plan, an idle WebSocket gets silently dropped
					// (seen as Telegram flashing back to "Connecting…"
					// after a quiet stretch), forcing a full CDN-hop
					// reconnect instead of just resuming.
					"heartbeatPeriod": 10,
				},
				// TCP Fast Open shaves a round trip off connection setup —
				// safe here (unlike on the REALITY inbound, where it isn't
				// used) because this listener only ever sees ordinary
				// TLS+WebSocket traffic proxied in by the CDN, not a
				// direct client needing to look indistinguishable.
				"sockopt": map[string]any{
					"tcpFastOpen": true,
				},
			},
			"sniffing": map[string]any{
				"enabled":      true,
				"destOverride": []string{"http", "tls", "quic"},
			},
		})
	}
	if a.cfg.CDNXHTTPListenPort > 0 && strings.TrimSpace(a.cfg.CDNTLSCertPath) != "" && strings.TrimSpace(a.cfg.CDNTLSKeyPath) != "" {
		xhttpPath := strings.TrimSpace(a.cfg.CDNXHTTPPath)
		if xhttpPath == "" {
			xhttpPath = "/wvb-xh"
		}
		inbounds = append(inbounds, map[string]any{
			"tag":      "vless-cdn-xhttp",
			"listen":   "0.0.0.0",
			"port":     a.cfg.CDNXHTTPListenPort,
			"protocol": "vless",
			"settings": map[string]any{
				"clients":    vlessClientsNoFlow,
				"decryption": "none",
			},
			"streamSettings": map[string]any{
				"network":  "xhttp",
				"security": "tls",
				"tlsSettings": map[string]any{
					"certificates": []map[string]any{
						{
							"certificateFile": a.cfg.CDNTLSCertPath,
							"keyFile":         a.cfg.CDNTLSKeyPath,
						},
					},
				},
				"xhttpSettings": map[string]any{
					"path": xhttpPath,
					"mode": "auto",
				},
				"sockopt": map[string]any{
					"tcpFastOpen": true,
				},
			},
			"sniffing": map[string]any{
				"enabled":      true,
				"destOverride": []string{"http", "tls", "quic"},
			},
		})
	}
	// gRPC sibling of the WS CDN transport: rides over one H2 connection to
	// the CDN edge like XHTTP does (avoiding a fresh TCP+TLS handshake per
	// app request), but gRPC has shipped in Xray-core and in client apps
	// for far longer, so it's the safer bet for broad compatibility.
	if a.cfg.CDNGRPCListenPort > 0 && strings.TrimSpace(a.cfg.CDNTLSCertPath) != "" && strings.TrimSpace(a.cfg.CDNTLSKeyPath) != "" {
		grpcService := strings.TrimSpace(a.cfg.CDNGRPCService)
		if grpcService == "" {
			grpcService = "wvb-grpc"
		}
		inbounds = append(inbounds, map[string]any{
			"tag":      "vless-cdn-grpc",
			"listen":   "0.0.0.0",
			"port":     a.cfg.CDNGRPCListenPort,
			"protocol": "vless",
			"settings": map[string]any{
				"clients":    vlessClientsNoFlow,
				"decryption": "none",
			},
			"streamSettings": map[string]any{
				"network":  "grpc",
				"security": "tls",
				"tlsSettings": map[string]any{
					"certificates": []map[string]any{
						{
							"certificateFile": a.cfg.CDNTLSCertPath,
							"keyFile":         a.cfg.CDNTLSKeyPath,
						},
					},
				},
				"grpcSettings": map[string]any{
					"serviceName": grpcService,
				},
				"sockopt": map[string]any{
					"tcpFastOpen": true,
				},
			},
			"sniffing": map[string]any{
				"enabled":      true,
				"destOverride": []string{"http", "tls", "quic"},
			},
		})
	}
	// Direct VLESS+WS+TLS with a real certificate, straight to this VPS's
	// own IP — no CDN, no REALITY fake-handshake. See config.go's
	// DirectTLSListenPort comment for why this might dodge active DPI that
	// direct REALITY doesn't, while giving up nothing on speed since
	// there's no CDN hop at all.
	if a.cfg.DirectTLSListenPort > 0 && strings.TrimSpace(a.cfg.DirectTLSCertPath) != "" && strings.TrimSpace(a.cfg.DirectTLSKeyPath) != "" {
		directPath := strings.TrimSpace(a.cfg.DirectTLSWSPath)
		if directPath == "" {
			directPath = "/wvb-dt"
		}
		inbounds = append(inbounds, map[string]any{
			"tag":      "vless-direct-tls",
			"listen":   "0.0.0.0",
			"port":     a.cfg.DirectTLSListenPort,
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
							"certificateFile": a.cfg.DirectTLSCertPath,
							"keyFile":         a.cfg.DirectTLSKeyPath,
						},
					},
				},
				"wsSettings": map[string]any{
					"path":            directPath,
					"heartbeatPeriod": 10,
				},
				"sockopt": map[string]any{
					"tcpFastOpen": true,
				},
			},
			"sniffing": map[string]any{
				"enabled":      true,
				"destOverride": []string{"http", "tls", "quic"},
			},
		})
	}
	// Trojan is a third, independently-implemented protocol behind the same
	// CDN — a completely different codebase's traffic fingerprint than
	// VLESS, so a DPI heuristic tuned to one doesn't automatically catch
	// both. Same cert, same CDN domain, different port/path.
	if a.cfg.TrojanCDNListenPort > 0 && strings.TrimSpace(a.cfg.CDNTLSCertPath) != "" && strings.TrimSpace(a.cfg.CDNTLSKeyPath) != "" {
		trojanPath := strings.TrimSpace(a.cfg.TrojanCDNWSPath)
		if trojanPath == "" {
			trojanPath = "/wvb-tr"
		}
		inbounds = append(inbounds, map[string]any{
			"tag":      "trojan-cdn-ws",
			"listen":   "0.0.0.0",
			"port":     a.cfg.TrojanCDNListenPort,
			"protocol": "trojan",
			"settings": map[string]any{
				"clients": trojanClients,
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
					"path":            trojanPath,
					"heartbeatPeriod": 10,
				},
				"sockopt": map[string]any{
					"tcpFastOpen": true,
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
	routingRules := []map[string]any{
		{
			"type":        "field",
			"ip":          []string{"10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.0/8", "fc00::/7"},
			"outboundTag": "blocked",
		},
	}
	outbounds := []map[string]any{
		{
			"tag":      "direct",
			"protocol": "freedom",
			"settings": map[string]any{},
			"sockopt": map[string]any{
				"domainStrategy": "UseIPv4",
				"tcpMaxSeg":      1200,
				"tcpFastOpen":    true,
			},
		},
		{"protocol": "blackhole", "tag": "blocked"},
	}
	var api map[string]any
	var stats map[string]any
	// Per-user uplink/downlink counters (enabled below via policy) are
	// tracked inside Xray whether or not anything queries them. Without this
	// inbound+api+stats trio there is no way to read them back out — the
	// admin's traffic chart stayed empty because nothing on the node side
	// ever reported usage to Core, and this is the piece that makes the
	// numbers reachable in the first place. Queried via `xray api
	// statsquery` run inside the container (see QueryUsage) rather than a
	// direct gRPC dial, so the agent doesn't need xray-core as a Go
	// dependency just for one CLI-shaped call.
	if a.cfg.StatsAPIPort > 0 {
		inbounds = append(inbounds, map[string]any{
			"tag":      "api",
			"listen":   "127.0.0.1",
			"port":     a.cfg.StatsAPIPort,
			"protocol": "dokodemo-door",
			"settings": map[string]any{"address": "127.0.0.1"},
		})
		routingRules = append([]map[string]any{{
			"type":        "field",
			"inboundTag":  []string{"api"},
			"outboundTag": "api",
		}}, routingRules...)
		outbounds = append(outbounds, map[string]any{"tag": "api", "protocol": "freedom", "settings": map[string]any{}})
		api = map[string]any{"tag": "api", "services": []string{"StatsService"}}
		stats = map[string]any{}
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
			"rules":          routingRules,
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
		"outbounds": outbounds,
	}
	if api != nil {
		rendered["api"] = api
		rendered["stats"] = stats
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
	if err := a.applyHysteria(ctx); err != nil {
		return fmt.Errorf("apply hysteria2 sidecar: %w", err)
	}
	if strings.TrimSpace(a.cfg.DockerContainer) != "" {
		return a.restartDockerContainer(ctx)
	}
	return nil
}

// applyHysteria writes the Hysteria2 sidecar's config from the same
// desired-state grants Render just used for Xray (see hyUsers) and restarts
// its container. A no-op unless HysteriaListenPort/ConfigPath are set.
func (a XrayAdapter) applyHysteria(ctx context.Context) error {
	if a.cfg.HysteriaListenPort <= 0 || strings.TrimSpace(a.cfg.HysteriaConfigPath) == "" {
		return nil
	}
	if strings.TrimSpace(a.cfg.HysteriaTLSCertPath) == "" || strings.TrimSpace(a.cfg.HysteriaTLSKeyPath) == "" {
		return fmt.Errorf("WAVEBREAK_HYSTERIA_TLS_CERT_PATH and WAVEBREAK_HYSTERIA_TLS_KEY_PATH are required")
	}
	var users []hysteriaUser
	if a.hyUsers != nil {
		users = *a.hyUsers
	}
	// userpass keys the client's auth string as "grantID:grantID" — self
	// consistent and trivially revocable (the grant simply drops out of
	// this map once it's no longer active), no separate secret to track.
	var userpass strings.Builder
	for _, u := range users {
		fmt.Fprintf(&userpass, "    %q: %q\n", u.ID, u.ID)
	}
	masqueradeURL := strings.TrimSpace(a.cfg.HysteriaMasqueradeURL)
	if masqueradeURL == "" {
		masqueradeURL = "https://www.bing.com"
	}
	var trafficStats string
	if a.cfg.HysteriaStatsPort > 0 {
		trafficStats = fmt.Sprintf("trafficStats:\n  listen: 127.0.0.1:%d\n", a.cfg.HysteriaStatsPort)
	}
	yaml := fmt.Sprintf(`listen: :%d
tls:
  cert: %q
  key: %q
quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnReceiveWindow: 20971520
  maxConnReceiveWindow: 20971520
  maxIdleTimeout: 60s
  maxIncomingStreams: 1024
  disablePathMTUDiscovery: true
  disableStatelessReset: false
ignoreClientBandwidth: true
congestion:
  type: bbr
  bbrProfile: conservative
disableUDP: false
udpIdleTimeout: 90s
auth:
  type: userpass
  userpass:
%smasquerade:
  type: proxy
  proxy:
    url: %q
    rewriteHost: true
%s`, a.cfg.HysteriaListenPort, a.cfg.HysteriaTLSCertPath, a.cfg.HysteriaTLSKeyPath, userpass.String(), masqueradeURL, trafficStats)

	if err := os.MkdirAll(filepath.Dir(a.cfg.HysteriaConfigPath), 0o755); err != nil {
		return err
	}
	tmp := a.cfg.HysteriaConfigPath + ".tmp"
	if err := os.WriteFile(tmp, []byte(yaml), 0o644); err != nil {
		return err
	}
	if err := os.Rename(tmp, a.cfg.HysteriaConfigPath); err != nil {
		return err
	}
	if strings.TrimSpace(a.cfg.HysteriaDockerContainer) != "" {
		return a.restartNamedDockerContainer(ctx, a.cfg.HysteriaDockerContainer)
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
	return a.restartNamedDockerContainer(ctx, a.cfg.DockerContainer)
}

func (a XrayAdapter) restartNamedDockerContainer(ctx context.Context, name string) error {
	resp, err := a.dockerRequest(ctx, http.MethodPost, "/containers/"+strings.TrimSpace(name)+"/restart?t=5", nil)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return fmt.Errorf("restart %s container returned status %d", name, resp.StatusCode)
	}
	return nil
}

func (a XrayAdapter) dockerClient() *http.Client {
	transport := &http.Transport{
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, "unix", a.cfg.DockerSocket)
		},
	}
	return &http.Client{Transport: transport, Timeout: 15 * time.Second}
}

func (a XrayAdapter) dockerRequest(ctx context.Context, method, path string, body []byte) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, method, "http://docker"+path, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	return a.dockerClient().Do(req)
}

// dockerExec runs cmd inside the named container via the Docker Engine
// API's exec create+start calls (the same /var/run/docker.sock the agent
// already mounts for restarts) and returns its combined stdout, so the
// agent can shell out to a container-local CLI tool — `xray api
// statsquery` here — without needing that tool's own client library as a
// Go dependency.
func (a XrayAdapter) dockerExec(ctx context.Context, container string, cmd []string) (string, error) {
	createBody, err := json.Marshal(map[string]any{
		"AttachStdout": true,
		"AttachStderr": true,
		"Cmd":          cmd,
	})
	if err != nil {
		return "", err
	}
	createResp, err := a.dockerRequest(ctx, http.MethodPost, "/containers/"+strings.TrimSpace(container)+"/exec", createBody)
	if err != nil {
		return "", err
	}
	defer createResp.Body.Close()
	if createResp.StatusCode < 200 || createResp.StatusCode > 299 {
		return "", fmt.Errorf("create exec in %s returned status %d", container, createResp.StatusCode)
	}
	var created struct {
		ID string `json:"Id"`
	}
	if err := json.NewDecoder(createResp.Body).Decode(&created); err != nil {
		return "", err
	}

	startBody, err := json.Marshal(map[string]any{"Detach": false, "Tty": false})
	if err != nil {
		return "", err
	}
	startResp, err := a.dockerRequest(ctx, http.MethodPost, "/exec/"+created.ID+"/start", startBody)
	if err != nil {
		return "", err
	}
	defer startResp.Body.Close()
	if startResp.StatusCode < 200 || startResp.StatusCode > 299 {
		return "", fmt.Errorf("start exec in %s returned status %d", container, startResp.StatusCode)
	}
	stdout, _, err := demuxDockerStream(startResp.Body)
	if err != nil {
		return "", err
	}

	inspectResp, err := a.dockerRequest(ctx, http.MethodGet, "/exec/"+created.ID+"/json", nil)
	if err != nil {
		return stdout, err
	}
	defer inspectResp.Body.Close()
	var inspected struct {
		ExitCode int `json:"ExitCode"`
	}
	if err := json.NewDecoder(inspectResp.Body).Decode(&inspected); err == nil && inspected.ExitCode != 0 {
		return stdout, fmt.Errorf("exec %v in %s exited %d", cmd, container, inspected.ExitCode)
	}
	return stdout, nil
}

// demuxDockerStream splits a non-Tty docker exec/attach stream into its
// stdout/stderr framing: each frame is an 8-byte header (1 byte stream
// type, 3 reserved, 4-byte big-endian payload length) followed by that
// many bytes of payload.
func demuxDockerStream(r io.Reader) (stdout, stderr string, err error) {
	var outBuf, errBuf bytes.Buffer
	header := make([]byte, 8)
	for {
		if _, err := io.ReadFull(r, header); err != nil {
			if err == io.EOF {
				break
			}
			return outBuf.String(), errBuf.String(), err
		}
		size := binary.BigEndian.Uint32(header[4:8])
		payload := make([]byte, size)
		if _, err := io.ReadFull(r, payload); err != nil {
			return outBuf.String(), errBuf.String(), err
		}
		if header[0] == 2 {
			errBuf.Write(payload)
		} else {
			outBuf.Write(payload)
		}
	}
	return outBuf.String(), errBuf.String(), nil
}

// QueryUsage reads back cumulative per-grant traffic from whichever
// transports are enabled: Xray's counters via `xray api statsquery` run
// inside its container, Hysteria2's via its own traffic-stats HTTP
// endpoint. A grant active on both (the pilot's normal case — one grant,
// several transport links) gets its counters summed across the two.
func (a XrayAdapter) QueryUsage(ctx context.Context) ([]GrantUsage, error) {
	var users []hysteriaUser
	if a.hyUsers != nil {
		users = *a.hyUsers
	}
	if len(users) == 0 {
		return nil, nil
	}
	emailToGrant := make(map[string]string, len(users))
	totals := make(map[string]*GrantUsage, len(users))
	for _, u := range users {
		emailToGrant[u.Email] = u.ID
		totals[u.ID] = &GrantUsage{GrantID: u.ID}
	}

	var firstErr error
	if a.cfg.StatsAPIPort > 0 && strings.TrimSpace(a.cfg.DockerContainer) != "" {
		if err := a.addXrayUsage(ctx, emailToGrant, totals); err != nil {
			firstErr = fmt.Errorf("query xray usage: %w", err)
		}
	}
	if a.cfg.HysteriaListenPort > 0 && a.cfg.HysteriaStatsPort > 0 {
		if err := a.addHysteriaUsage(ctx, totals); err != nil && firstErr == nil {
			firstErr = fmt.Errorf("query hysteria usage: %w", err)
		}
	}

	result := make([]GrantUsage, 0, len(totals))
	for _, usage := range totals {
		result = append(result, *usage)
	}
	return result, firstErr
}

type xrayStatEntry struct {
	Name  string `json:"name"`
	Value int64  `json:"value"`
}

func (a XrayAdapter) addXrayUsage(ctx context.Context, emailToGrant map[string]string, totals map[string]*GrantUsage) error {
	out, err := a.dockerExec(ctx, a.cfg.DockerContainer, []string{
		"xray", "api", "statsquery",
		"--server=127.0.0.1:" + strconv.Itoa(a.cfg.StatsAPIPort),
		"-json", "-pattern", "user>>>",
	})
	if err != nil {
		return err
	}
	var parsed struct {
		Stat []xrayStatEntry `json:"stat"`
	}
	if err := json.Unmarshal([]byte(out), &parsed); err != nil {
		return fmt.Errorf("decode statsquery output: %w", err)
	}
	// Each counter name looks like "user>>>{email}>>>traffic>>>uplink".
	for _, stat := range parsed.Stat {
		parts := strings.Split(stat.Name, ">>>")
		if len(parts) != 4 || parts[0] != "user" || parts[2] != "traffic" {
			continue
		}
		grantID, ok := emailToGrant[parts[1]]
		if !ok {
			continue
		}
		usage := totals[grantID]
		if usage == nil {
			continue
		}
		switch parts[3] {
		case "uplink":
			usage.BytesUp += stat.Value
		case "downlink":
			usage.BytesDown += stat.Value
		}
	}
	return nil
}

func (a XrayAdapter) addHysteriaUsage(ctx context.Context, totals map[string]*GrantUsage) error {
	url := fmt.Sprintf("http://127.0.0.1:%d/traffic", a.cfg.HysteriaStatsPort)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	resp, err := (&http.Client{Timeout: 10 * time.Second}).Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return fmt.Errorf("hysteria traffic-stats returned status %d", resp.StatusCode)
	}
	var parsed map[string]struct {
		Tx int64 `json:"tx"`
		Rx int64 `json:"rx"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&parsed); err != nil {
		return fmt.Errorf("decode traffic-stats: %w", err)
	}
	// Hysteria2's userpass auth string is the grant ID itself (see
	// applyHysteria), so these keys are already grant IDs — no email
	// lookup needed here, unlike the Xray side.
	for grantID, counters := range parsed {
		usage := totals[grantID]
		if usage == nil {
			continue
		}
		usage.BytesUp += counters.Rx
		usage.BytesDown += counters.Tx
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
