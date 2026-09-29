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

func TestRealityServerNameUsesFirstOfList(t *testing.T) {
	t.Setenv("WAVEBREAK_VLESS_REALITY_SERVER_NAME", " www.microsoft.com , r.wavebreak.com.tr")
	cfg, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.VLESS.RealityServerName != "www.microsoft.com" {
		t.Fatalf("got %q", cfg.VLESS.RealityServerName)
	}
}
