package config

import "testing"

func TestLoadRejectsProductionDefaults(t *testing.T) {
	t.Setenv("WAVEBREAK_ENV", "production")
	t.Setenv("WAVEBREAK_JWT_SECRET", "short")
	_, err := Load()
	if err == nil {
		t.Fatal("expected production default validation error")
	}
}

func TestLoadAllowsDevelopmentDefaults(t *testing.T) {
	t.Setenv("WAVEBREAK_ENV", "development")
	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}
	if cfg.Environment != "development" {
		t.Fatalf("unexpected env: %s", cfg.Environment)
	}
}
