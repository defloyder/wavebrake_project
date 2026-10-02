package config

import "testing"

func TestValidateCoreURL(t *testing.T) {
	cases := []struct {
		name    string
		url     string
		wantErr bool
	}{
		{"https remote", "https://api.wavebreak.com.tr", false},
		{"http loopback ip", "http://127.0.0.1:18080", false},
		{"http localhost", "http://localhost:8080", false},
		{"http ipv6 loopback", "http://[::1]:8080", false},
		{"http remote host", "http://api.wavebreak.com.tr", true},
		{"http remote ip", "http://45.15.41.3:8080", true},
		{"unsupported scheme", "ftp://127.0.0.1", true},
		{"unparseable", "http://[::", true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			err := validateCoreURL(c.url)
			if c.wantErr && err == nil {
				t.Fatalf("validateCoreURL(%q): expected an error, got nil", c.url)
			}
			if !c.wantErr && err != nil {
				t.Fatalf("validateCoreURL(%q): expected no error, got %v", c.url, err)
			}
		})
	}
}
