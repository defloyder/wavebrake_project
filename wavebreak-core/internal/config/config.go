package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
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
}

func Load() (Config, error) {
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
		VLESS: VLESSConfig{
			PublicHost:         env("WAVEBREAK_VLESS_PUBLIC_HOST", ""),
			PublicPort:         vlessPort,
			RealityPublicKey:   env("WAVEBREAK_VLESS_REALITY_PUBLIC_KEY", ""),
			RealityShortID:     env("WAVEBREAK_VLESS_REALITY_SHORT_ID", ""),
			RealityServerName:  env("WAVEBREAK_VLESS_REALITY_SERVER_NAME", "www.microsoft.com"),
			Fingerprint:        env("WAVEBREAK_VLESS_FINGERPRINT", "chrome"),
			Flow:               env("WAVEBREAK_VLESS_FLOW", "xtls-rprx-vision"),
			ShadowsocksPort:    ssPort,
			ShadowsocksMethod:  env("WAVEBREAK_SS_METHOD", "aes-256-gcm"),
			PublishShadowsocks: boolEnv("WAVEBREAK_PUBLISH_SHADOWSOCKS", false),
			CDNHost:            env("WAVEBREAK_VLESS_CDN_HOST", ""),
			CDNPort:            cdnPort,
			CDNWSPath:          env("WAVEBREAK_VLESS_CDN_WS_PATH", "/wvb-ws"),
			CDNXHTTPPort:       cdnXHTTPPort,
			CDNXHTTPPath:       env("WAVEBREAK_VLESS_CDN_XHTTP_PATH", "/wvb-xh"),
			PublishDirect:      boolEnv("WAVEBREAK_VLESS_PUBLISH_DIRECT", true),
			PublishCDNXHTTP:    boolEnv("WAVEBREAK_VLESS_PUBLISH_CDN_XHTTP", true),
			TrojanCDNPort:      trojanCDNPort,
			TrojanCDNWSPath:    env("WAVEBREAK_TROJAN_CDN_WS_PATH", "/wvb-tr"),
		},
	}
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
