package config

import (
	"os"
	"strconv"
	"time"
)

type Config struct {
	CoreURL           string
	EnrollmentToken   string
	NodeAPIToken      string
	NodeTokenPath     string
	NodeCode          string
	Region            string
	HeartbeatInterval time.Duration
	SyncInterval      time.Duration
	RuntimeAdapter    string
	Xray              XrayConfig
}

type XrayConfig struct {
	ConfigPath        string
	ListenPort        int
	RealityPrivateKey string
	RealityShortID    string
	RealityDest       string
	RealityServerName string
	Flow              string
	ShadowsocksPort   int
	ShadowsocksMethod string
	DockerSocket      string
	DockerContainer   string
	// CDN transport: a second, structurally ordinary VLESS+WebSocket+TLS
	// inbound meant to sit behind a CDN proxy (e.g. Cloudflare orange-cloud)
	// so a client's outer TLS handshake is indistinguishable from any other
	// site served by that CDN. Disabled unless CDNListenPort is set.
	CDNListenPort  int
	CDNWSPath      string
	CDNTLSCertPath string
	CDNTLSKeyPath  string
	// A second CDN inbound using XHTTP instead of WebSocket: XHTTP can ride
	// over one H2 connection to the CDN edge, so many concurrent app
	// requests (loading a chat full of photos, say) share one handshake
	// instead of each paying it separately the way one-stream-per-WS-
	// connection does. Kept alongside the WS inbound rather than replacing
	// it, since XHTTP client support is newer and less universal.
	CDNXHTTPListenPort int
	CDNXHTTPPath       string
	// Trojan behind the same CDN — a different protocol implementation
	// entirely, for when a network's DPI is specifically tuned to VLESS's
	// fingerprint rather than REALITY/XHTTP/WS traffic shape in general.
	TrojanCDNListenPort int
	TrojanCDNWSPath     string
	// gRPC sibling of the WS CDN transport: also multiplexes many app
	// requests over one H2 connection like XHTTP does, but gRPC has been in
	// Xray-core (and in client apps) far longer, so it's a safer bet for
	// broad client compatibility than XHTTP turned out to be.
	CDNGRPCListenPort int
	CDNGRPCService    string
	// Hysteria2 is a direct (non-CDN) sidecar transport, run by a separate
	// binary (github.com/apernet/hysteria, not Xray-core) restarted through
	// the same docker socket Apply already uses for Xray. It needs its own
	// ECDSA cert (Hysteria's QUIC/TLS1.3 handshake rejects RSA certs — see
	// xray.go) and its own config file/container, since it isn't Xray.
	HysteriaListenPort      int
	HysteriaConfigPath      string
	HysteriaTLSCertPath     string
	HysteriaTLSKeyPath      string
	HysteriaDockerContainer string
	HysteriaMasqueradeURL   string
}

func Load() Config {
	return Config{
		CoreURL:           env("WAVEBREAK_CORE_URL", "http://localhost:8080"),
		EnrollmentToken:   env("WAVEBREAK_NODE_ENROLLMENT_TOKEN", ""),
		NodeAPIToken:      env("WAVEBREAK_NODE_API_TOKEN", ""),
		NodeTokenPath:     env("WAVEBREAK_NODE_TOKEN_PATH", ""),
		NodeCode:          env("WAVEBREAK_NODE_CODE", "TR-IST-01"),
		Region:            env("WAVEBREAK_NODE_REGION", "TR"),
		HeartbeatInterval: durationEnv("WAVEBREAK_NODE_HEARTBEAT_INTERVAL", 30*time.Second),
		SyncInterval:      durationEnv("WAVEBREAK_NODE_SYNC_INTERVAL", 20*time.Second),
		RuntimeAdapter:    env("WAVEBREAK_RUNTIME_ADAPTER", "noop"),
		Xray: XrayConfig{
			ConfigPath:              env("WAVEBREAK_XRAY_CONFIG_PATH", "/etc/wavebreak/xray/config.json"),
			ListenPort:              intEnv("WAVEBREAK_XRAY_LISTEN_PORT", 8443),
			RealityPrivateKey:       env("WAVEBREAK_XRAY_REALITY_PRIVATE_KEY", ""),
			RealityShortID:          env("WAVEBREAK_XRAY_REALITY_SHORT_ID", ""),
			RealityDest:             env("WAVEBREAK_XRAY_REALITY_DEST", "www.microsoft.com:443"),
			RealityServerName:       env("WAVEBREAK_XRAY_REALITY_SERVER_NAME", "www.microsoft.com"),
			Flow:                    env("WAVEBREAK_XRAY_FLOW", "xtls-rprx-vision"),
			ShadowsocksPort:         intEnv("WAVEBREAK_XRAY_SS_PORT", 0),
			ShadowsocksMethod:       env("WAVEBREAK_XRAY_SS_METHOD", "aes-256-gcm"),
			DockerSocket:            env("WAVEBREAK_XRAY_DOCKER_SOCKET", "/var/run/docker.sock"),
			DockerContainer:         env("WAVEBREAK_XRAY_DOCKER_CONTAINER", ""),
			CDNListenPort:           intEnv("WAVEBREAK_XRAY_CDN_LISTEN_PORT", 0),
			CDNWSPath:               env("WAVEBREAK_XRAY_CDN_WS_PATH", "/wvb-ws"),
			CDNTLSCertPath:          env("WAVEBREAK_XRAY_CDN_TLS_CERT_PATH", ""),
			CDNTLSKeyPath:           env("WAVEBREAK_XRAY_CDN_TLS_KEY_PATH", ""),
			CDNXHTTPListenPort:      intEnv("WAVEBREAK_XRAY_CDN_XHTTP_LISTEN_PORT", 0),
			CDNXHTTPPath:            env("WAVEBREAK_XRAY_CDN_XHTTP_PATH", "/wvb-xh"),
			TrojanCDNListenPort:     intEnv("WAVEBREAK_XRAY_TROJAN_CDN_LISTEN_PORT", 0),
			TrojanCDNWSPath:         env("WAVEBREAK_XRAY_TROJAN_CDN_WS_PATH", "/wvb-tr"),
			CDNGRPCListenPort:       intEnv("WAVEBREAK_XRAY_CDN_GRPC_LISTEN_PORT", 0),
			CDNGRPCService:          env("WAVEBREAK_XRAY_CDN_GRPC_SERVICE", "wvb-grpc"),
			HysteriaListenPort:      intEnv("WAVEBREAK_HYSTERIA_LISTEN_PORT", 0),
			HysteriaConfigPath:      env("WAVEBREAK_HYSTERIA_CONFIG_PATH", ""),
			HysteriaTLSCertPath:     env("WAVEBREAK_HYSTERIA_TLS_CERT_PATH", ""),
			HysteriaTLSKeyPath:      env("WAVEBREAK_HYSTERIA_TLS_KEY_PATH", ""),
			HysteriaDockerContainer: env("WAVEBREAK_HYSTERIA_DOCKER_CONTAINER", ""),
			HysteriaMasqueradeURL:   env("WAVEBREAK_HYSTERIA_MASQUERADE_URL", "https://www.bing.com"),
		},
	}
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func durationEnv(key string, fallback time.Duration) time.Duration {
	raw := os.Getenv(key)
	if raw == "" {
		return fallback
	}
	d, err := time.ParseDuration(raw)
	if err != nil {
		return fallback
	}
	return d
}

func intEnv(key string, fallback int) int {
	raw := os.Getenv(key)
	if raw == "" {
		return fallback
	}
	value, err := strconv.Atoi(raw)
	if err != nil {
		return fallback
	}
	return value
}
