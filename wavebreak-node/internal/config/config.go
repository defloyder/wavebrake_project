package config

import (
	"os"
	"time"
)

type Config struct {
	CoreURL           string
	EnrollmentToken   string
	NodeAPIToken      string
	NodeCode          string
	Region            string
	HeartbeatInterval time.Duration
	SyncInterval      time.Duration
}

func Load() Config {
	return Config{
		CoreURL:           env("WAVEBREAK_CORE_URL", "http://localhost:8080"),
		EnrollmentToken:   env("WAVEBREAK_NODE_ENROLLMENT_TOKEN", ""),
		NodeAPIToken:      env("WAVEBREAK_NODE_API_TOKEN", ""),
		NodeCode:          env("WAVEBREAK_NODE_CODE", "TR-IST-01"),
		Region:            env("WAVEBREAK_NODE_REGION", "TR"),
		HeartbeatInterval: durationEnv("WAVEBREAK_NODE_HEARTBEAT_INTERVAL", 30*time.Second),
		SyncInterval:      durationEnv("WAVEBREAK_NODE_SYNC_INTERVAL", 20*time.Second),
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
