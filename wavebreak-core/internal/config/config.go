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
}

func Load() (Config, error) {
	redisDB, err := strconv.Atoi(env("WAVEBREAK_REDIS_DB", "0"))
	if err != nil {
		return Config{}, fmt.Errorf("parse WAVEBREAK_REDIS_DB: %w", err)
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

func mustDuration(raw string) time.Duration {
	d, err := time.ParseDuration(raw)
	if err != nil {
		return 15 * time.Minute
	}
	return d
}
