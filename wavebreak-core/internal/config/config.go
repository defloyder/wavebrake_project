package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"wavebreak-core/internal/mailer"
	"wavebreak-core/internal/relays"
)

type Config struct {
	Environment     string
	HTTPAddr        string
	DatabaseURL     string
	RedisAddr       string
	RedisPassword   string
	RedisDB         int
	RabbitMQURL     string
	JWTSecret       string
	AccessTokenTTL  time.Duration
	RefreshTokenTTL time.Duration
	BotServiceToken string
	OTLPEndpoint    string
	VLESS           VLESSConfig
	Accounts        AccountsConfig
	// Mail: transactional email over SMTP (Brevo). Off until host, user,
	// password and sender are all set.
	Mail mailer.Config
}

// AccountsConfig drives admin account management (internal/accounts).
type AccountsConfig struct {
	// SubscriptionURLBase + credential id = the user's subscription URL.
	SubscriptionURLBase string
	// PasswordResetURLBase + "?token=..." = the link sent to the user.
	PasswordResetURLBase string
	PasswordResetTTL     time.Duration
	// AccessProtocol of credentials issued with an admin-assigned subscription.
	// (Also used for the credential the app asks for via POST /v1/me/access.)
	AccessProtocol string
	// SubscriptionGrace: how long a past_due subscription waits for renewal
	// (VPN blocked) before it expires and the account is reset.
	SubscriptionGrace time.Duration
}

type VLESSConfig struct {
	PublicHost         string
	PublicPort         int
	RealityPublicKey   string
	RealityShortID     string
	RealityServerName  string
	Fingerprint        string
	Flow               string
	ShadowsocksPort    int
	ShadowsocksMethod  string
	PublishShadowsocks bool
	// CDN transport: VLESS+WebSocket+TLS fronted by a CDN (Cloudflare), for
	// networks whose DPI actively disrupts the REALITY transport above.
	// CDNHost is the public domain the CDN proxies (not the VPS's own IP).
	CDNHost   string
	CDNPort   int
	CDNWSPath string
	// XHTTP sibling of the WS CDN transport above — multiplexes many app
	// requests over one H2 connection to the CDN edge instead of opening a
	// new one per request, which matters a lot once a network's extra CDN
	// hop adds real per-connection latency.
	CDNXHTTPPort int
	CDNXHTTPPath string
	// Trojan behind the same CDN — different protocol implementation than
	// VLESS, for DPI resistance that doesn't depend on one codebase.
	TrojanCDNPort   int
	TrojanCDNWSPath string
	// gRPC sibling of the WS CDN transport — see wavebreak-node's XrayConfig
	// comment for why this exists alongside XHTTP.
	CDNGRPCPort    int
	CDNGRPCService string
	// Hysteria2: direct (non-CDN) UDP/QUIC transport. Confirmed to survive
	// the pilot's active-DPI blocking where direct REALITY did not, and
	// doesn't suffer the QUIC-in-TCP-tunnel degradation the CDN transports
	// do — but is a separate protocol most VLESS/Trojan clients don't
	// support (e.g. Happ), so it's offered alongside, not instead of, the
	// CDN transports above.
	HysteriaHost     string
	HysteriaPort     int
	HysteriaSNI      string
	HysteriaInsecure bool
	// A second Hysteria2 listener on the same host with salamander
	// obfuscation (and, when HysteriaObfsHopPorts is set, port hopping):
	// some carriers let a QUIC handshake to a foreign server through and
	// then cut the flow; an obfuscated, port-hopping one isn't recognisable
	// as QUIC. Published as an extra link only when port and password are
	// set; the plain listener stays for existing clients.
	HysteriaObfsPort     int
	HysteriaObfsPassword string
	HysteriaObfsHopPorts string
	// Direct VLESS+WS+TLS with a real cert, no CDN — see wavebreak-node's
	// XrayConfig comment for the DPI-evasion hypothesis behind this.
	// DirectTLSHost is the VPS's own domain/IP, not the CDN host.
	DirectTLSHost string
	DirectTLSPort int
	DirectTLSPath string
	// PublishDirect controls whether the direct REALITY link is included in
	// a grant's links/subscription. Default true; set false once a network
	// is confirmed to actively disrupt REALITY, so clients only see (and
	// only auto-select) the CDN transport that actually works for them.
	PublishDirect bool
	// PublishCDNXHTTP controls whether the XHTTP CDN link is published.
	// Default true; set false once XHTTP is confirmed to break long-lived
	// connections (e.g. Telegram's MTProto sessions) even though it handles
	// ordinary HTTPS requests fine — better to publish only the transport
	// that's actually confirmed reliable than a faster-looking broken one.
	PublishCDNXHTTP bool
	// PublishCDNWS / PublishTrojanCDN: same idea as PublishDirect/
	// PublishCDNXHTTP — toggle whether these confirmed-working but slower
	// CDN transports still get published once faster options
	// (Hysteria2/Direct-TLS) are confirmed good enough on their own.
	PublishCDNWS     bool
	PublishTrojanCDN bool
	// VLESS over XHTTP with REALITY on PublicHost:PublicPort, same REALITY
	// keys, its own SNI (the edge routes TLS by SNI). Published when
	// RealityXHTTPServerName is set. See wavebreak-node's XrayConfig.
	RealityXHTTPServerName string
	RealityXHTTPPath       string
	// PublishRealityXHTTPDirect also publishes the XHTTP+REALITY link
	// straight to PublicHost (not only through relays). Default false.
	PublishRealityXHTTPDirect bool
	// Relays: domestic TCP forwarders to PublicHost:PublicPort (see
	// internal/relays), WAVEBREAK_VLESS_RELAYS="Moscow=1.2.3.4[:443],...".
	// Each healthy one gets an XHTTP+REALITY link with its own address.
	Relays []relays.Relay
}

func Load() (Config, error) {
	smtpPort, err := strconv.Atoi(env("WAVEBREAK_SMTP_PORT", "587"))
	if err != nil {
		return Config{}, fmt.Errorf("parse WAVEBREAK_SMTP_PORT: %w", err)
	}
	redisDB, err := strconv.Atoi(env("WAVEBREAK_REDIS_DB", "0"))
	if err != nil {
		return Config{}, fmt.Errorf("parse WAVEBREAK_REDIS_DB: %w", err)
	}
	vlessPort, err := strconv.Atoi(env("WAVEBREAK_VLESS_PORT", "18443"))
	if err != nil {
		return Config{}, fmt.Errorf("parse WAVEBREAK_VLESS_PORT: %w", err)
	}
	ssPort, err := strconv.Atoi(env("WAVEBREAK_SS_PORT", "0"))
	if err != nil {
		return Config{}, fmt.Errorf("parse WAVEBREAK_SS_PORT: %w", err)
	}
	cdnPort, err := strconv.Atoi(env("WAVEBREAK_VLESS_CDN_PORT", "0"))
	if err != nil {
		return Config{}, fmt.Errorf("parse WAVEBREAK_VLESS_CDN_PORT: %w", err)
	}
	cdnXHTTPPort, err := strconv.Atoi(env("WAVEBREAK_VLESS_CDN_XHTTP_PORT", "0"))
	if err != nil {
		return Config{}, fmt.Errorf("parse WAVEBREAK_VLESS_CDN_XHTTP_PORT: %w", err)
	}
	trojanCDNPort, err := strconv.Atoi(env("WAVEBREAK_TROJAN_CDN_PORT", "0"))
	if err != nil {
		return Config{}, fmt.Errorf("parse WAVEBREAK_TROJAN_CDN_PORT: %w", err)
	}
	cdnGRPCPort, err := strconv.Atoi(env("WAVEBREAK_VLESS_CDN_GRPC_PORT", "0"))
	if err != nil {
		return Config{}, fmt.Errorf("parse WAVEBREAK_VLESS_CDN_GRPC_PORT: %w", err)
	}
	hysteriaPort, err := strconv.Atoi(env("WAVEBREAK_HYSTERIA_PORT", "0"))
	if err != nil {
		return Config{}, fmt.Errorf("parse WAVEBREAK_HYSTERIA_PORT: %w", err)
	}
	hysteriaObfsPort, err := strconv.Atoi(env("WAVEBREAK_HYSTERIA_OBFS_PORT", "0"))
	if err != nil {
		return Config{}, fmt.Errorf("parse WAVEBREAK_HYSTERIA_OBFS_PORT: %w", err)
	}
	directTLSPort, err := strconv.Atoi(env("WAVEBREAK_DIRECT_TLS_PORT", "0"))
	if err != nil {
		return Config{}, fmt.Errorf("parse WAVEBREAK_DIRECT_TLS_PORT: %w", err)
	}

	cfg := Config{
		Environment:     env("WAVEBREAK_ENV", "development"),
		HTTPAddr:        env("WAVEBREAK_HTTP_ADDR", ":8080"),
		DatabaseURL:     env("WAVEBREAK_DATABASE_URL", "postgres://wavebreak:wavebreak@localhost:5432/wavebreak?sslmode=disable"),
		RedisAddr:       env("WAVEBREAK_REDIS_ADDR", "localhost:6379"),
		RedisPassword:   env("WAVEBREAK_REDIS_PASSWORD", ""),
		RedisDB:         redisDB,
		RabbitMQURL:     env("WAVEBREAK_RABBITMQ_URL", "amqp://wavebreak:wavebreak@localhost:5672/"),
		JWTSecret:       env("WAVEBREAK_JWT_SECRET", "change-me-in-production"),
		AccessTokenTTL:  mustDuration(env("WAVEBREAK_ACCESS_TOKEN_TTL", "15m")),
		RefreshTokenTTL: mustDuration(env("WAVEBREAK_REFRESH_TOKEN_TTL", "720h")),
		BotServiceToken: env("WAVEBREAK_BOT_SERVICE_TOKEN", ""),
		OTLPEndpoint:    env("WAVEBREAK_OTLP_ENDPOINT", "localhost:4317"),
		Mail: mailer.Config{
			Host:     env("WAVEBREAK_SMTP_HOST", ""),
			Port:     smtpPort,
			Username: env("WAVEBREAK_SMTP_USERNAME", ""),
			Password: env("WAVEBREAK_SMTP_PASSWORD", ""),
			From:     env("WAVEBREAK_SMTP_FROM", ""),
			FromName: env("WAVEBREAK_SMTP_FROM_NAME", "WAVEBREAK"),
			ReplyTo:  env("WAVEBREAK_SMTP_REPLY_TO", "support@wavebreak.com.tr"),
		},
		Accounts: AccountsConfig{
			SubscriptionURLBase:  env("WAVEBREAK_SUBSCRIPTION_URL_BASE", "https://core.wavebreak.com.tr/v1/sub/"),
			PasswordResetURLBase: env("WAVEBREAK_PASSWORD_RESET_URL_BASE", "https://wavebreak.com.tr/reset-password"),
			PasswordResetTTL:     mustDuration(env("WAVEBREAK_PASSWORD_RESET_TTL", "1h")),
			AccessProtocol:       env("WAVEBREAK_ADMIN_ACCESS_PROTOCOL", "vless"),
			SubscriptionGrace:    mustDuration(env("WAVEBREAK_SUBSCRIPTION_GRACE", "168h")),
		},
		VLESS: VLESSConfig{
			PublicHost:                env("WAVEBREAK_VLESS_PUBLIC_HOST", ""),
			PublicPort:                vlessPort,
			RealityPublicKey:          env("WAVEBREAK_VLESS_REALITY_PUBLIC_KEY", ""),
			RealityShortID:            env("WAVEBREAK_VLESS_REALITY_SHORT_ID", ""),
			RealityServerName:         env("WAVEBREAK_VLESS_REALITY_SERVER_NAME", "www.microsoft.com"),
			Fingerprint:               env("WAVEBREAK_VLESS_FINGERPRINT", "chrome"),
			Flow:                      env("WAVEBREAK_VLESS_FLOW", "xtls-rprx-vision"),
			ShadowsocksPort:           ssPort,
			ShadowsocksMethod:         env("WAVEBREAK_SS_METHOD", "aes-256-gcm"),
			PublishShadowsocks:        boolEnv("WAVEBREAK_PUBLISH_SHADOWSOCKS", false),
			CDNHost:                   env("WAVEBREAK_VLESS_CDN_HOST", ""),
			CDNPort:                   cdnPort,
			CDNWSPath:                 env("WAVEBREAK_VLESS_CDN_WS_PATH", "/wvb-ws"),
			CDNXHTTPPort:              cdnXHTTPPort,
			CDNXHTTPPath:              env("WAVEBREAK_VLESS_CDN_XHTTP_PATH", "/wvb-xh"),
			PublishDirect:             boolEnv("WAVEBREAK_VLESS_PUBLISH_DIRECT", true),
			PublishCDNXHTTP:           boolEnv("WAVEBREAK_VLESS_PUBLISH_CDN_XHTTP", true),
			TrojanCDNPort:             trojanCDNPort,
			TrojanCDNWSPath:           env("WAVEBREAK_TROJAN_CDN_WS_PATH", "/wvb-tr"),
			CDNGRPCPort:               cdnGRPCPort,
			CDNGRPCService:            env("WAVEBREAK_VLESS_CDN_GRPC_SERVICE", "wvb-grpc"),
			HysteriaHost:              env("WAVEBREAK_HYSTERIA_HOST", ""),
			HysteriaPort:              hysteriaPort,
			HysteriaSNI:               env("WAVEBREAK_HYSTERIA_SNI", ""),
			HysteriaInsecure:          boolEnv("WAVEBREAK_HYSTERIA_INSECURE", true),
			HysteriaObfsPort:          hysteriaObfsPort,
			HysteriaObfsPassword:      env("WAVEBREAK_HYSTERIA_OBFS_PASSWORD", ""),
			HysteriaObfsHopPorts:      env("WAVEBREAK_HYSTERIA_OBFS_HOP_PORTS", ""),
			DirectTLSHost:             env("WAVEBREAK_DIRECT_TLS_HOST", ""),
			DirectTLSPort:             directTLSPort,
			DirectTLSPath:             env("WAVEBREAK_DIRECT_TLS_PATH", "/wvb-dt"),
			PublishCDNWS:              boolEnv("WAVEBREAK_VLESS_PUBLISH_CDN_WS", true),
			PublishTrojanCDN:          boolEnv("WAVEBREAK_VLESS_PUBLISH_TROJAN_CDN", true),
			RealityXHTTPServerName:    env("WAVEBREAK_VLESS_REALITY_XHTTP_SERVER_NAME", ""),
			RealityXHTTPPath:          env("WAVEBREAK_VLESS_REALITY_XHTTP_PATH", "/wvb-rx"),
			PublishRealityXHTTPDirect: boolEnv("WAVEBREAK_VLESS_PUBLISH_REALITY_XHTTP_DIRECT", false),
		},
	}
	relayList, err := relays.Parse(env("WAVEBREAK_VLESS_RELAYS", ""))
	if err != nil {
		return Config{}, fmt.Errorf("parse WAVEBREAK_VLESS_RELAYS: %w", err)
	}
	cfg.VLESS.Relays = relayList
	if cfg.Environment == "production" {
		if cfg.JWTSecret == "change-me-in-production" || len(cfg.JWTSecret) < 32 {
			return Config{}, fmt.Errorf("WAVEBREAK_JWT_SECRET must be strong and set in production")
		}
		if strings.Contains(cfg.DatabaseURL, "wavebreak:wavebreak") {
			return Config{}, fmt.Errorf("production database credentials must not use local defaults")
		}
		if strings.Contains(cfg.RabbitMQURL, "wavebreak:wavebreak") {
			return Config{}, fmt.Errorf("production rabbitmq credentials must not use local defaults")
		}
		if len(cfg.BotServiceToken) < 32 {
			return Config{}, fmt.Errorf("WAVEBREAK_BOT_SERVICE_TOKEN must be set in production")
		}
	}
	return cfg, nil
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func boolEnv(key string, fallback bool) bool {
	raw := strings.ToLower(strings.TrimSpace(os.Getenv(key)))
	if raw == "" {
		return fallback
	}
	switch raw {
	case "1", "true", "yes", "y", "on":
		return true
	case "0", "false", "no", "n", "off":
		return false
	default:
		return fallback
	}
}

func mustDuration(raw string) time.Duration {
	d, err := time.ParseDuration(raw)
	if err != nil {
		return 15 * time.Minute
	}
	return d
}
