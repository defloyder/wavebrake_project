package runtime

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"wavebreak-node/internal/config"
)

func hysteriaTestAdapter(t *testing.T, users []hysteriaUser) (XrayAdapter, string) {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "hysteria.yaml")
	return XrayAdapter{
		cfg: config.XrayConfig{
			HysteriaListenPort:  443,
			HysteriaConfigPath:  path,
			HysteriaTLSCertPath: "/etc/hy-cert.pem",
			HysteriaTLSKeyPath:  "/etc/hy-key.pem",
			// A container name makes every real write try a restart; the
			// socket doesn't exist, so an attempted restart is an error.
			HysteriaDockerContainer: "hysteria-test",
			DockerSocket:            filepath.Join(dir, "no-docker.sock"),
		},
		hyUsers: &users,
	}, path
}

func TestApplyHysteriaTuning(t *testing.T) {
	a, path := hysteriaTestAdapter(t, []hysteriaUser{{ID: "11111111-2222-4333-8444-555555555555"}})
	_ = a.applyHysteria(context.Background()) // restart fails without Docker; the file is written first
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	yaml := string(raw)
	for _, want := range []string{
		"bbrProfile: standard",
		"disablePathMTUDiscovery: false",
		"initStreamReceiveWindow: 16777216",
		"maxConnReceiveWindow: 41943040",
		"ignoreClientBandwidth: true",
		`"11111111-2222-4333-8444-555555555555": "11111111-2222-4333-8444-555555555555"`,
	} {
		if !strings.Contains(yaml, want) {
			t.Errorf("hysteria.yaml lacks %q:\n%s", want, yaml)
		}
	}
	if strings.Contains(yaml, "conservative") {
		t.Error("conservative BBR profile still rendered")
	}
}

func TestApplyHysteriaObfsInstance(t *testing.T) {
	a, plainPath := hysteriaTestAdapter(t, []hysteriaUser{{ID: "bbbbbbbb-0000-4000-8000-000000000001"}})
	dir := filepath.Dir(plainPath)
	a.cfg.HysteriaStatsPort = 19998
	a.cfg.HysteriaObfsListenPort = 20443
	a.cfg.HysteriaObfsConfigPath = filepath.Join(dir, "hysteria-obfs.yaml")
	a.cfg.HysteriaObfsPassword = "obfs-secret"
	a.cfg.HysteriaObfsStatsPort = 19997
	_ = a.applyHysteria(context.Background())

	plain, _ := os.ReadFile(plainPath)
	obfs, err := os.ReadFile(a.cfg.HysteriaObfsConfigPath)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(plain), "salamander") || !strings.Contains(string(plain), "listen: :443") ||
		!strings.Contains(string(plain), "127.0.0.1:19998") {
		t.Fatalf("plain listener:\n%s", plain)
	}
	for _, want := range []string{
		"listen: :20443",
		"obfs:\n  type: salamander\n  salamander:\n    password: \"obfs-secret\"",
		"127.0.0.1:19997",
		`"bbbbbbbb-0000-4000-8000-000000000001"`,
	} {
		if !strings.Contains(string(obfs), want) {
			t.Errorf("obfs listener lacks %q:\n%s", want, obfs)
		}
	}
	// Without a password there is no second listener.
	a.cfg.HysteriaObfsPassword = ""
	if n := len(a.hysteriaInstances()); n != 1 {
		t.Fatalf("instances without obfs password: %d", n)
	}
}

func TestApplyHysteriaRestartsOnlyOnChange(t *testing.T) {
	users := []hysteriaUser{{ID: "aaaaaaaa-0000-4000-8000-000000000001"}}
	a, _ := hysteriaTestAdapter(t, users)
	if err := a.applyHysteria(context.Background()); err == nil {
		t.Fatal("first apply should have tried (and failed) to restart")
	}
	// Same users, same config: no restart attempted, so no error.
	if err := a.applyHysteria(context.Background()); err != nil {
		t.Fatalf("unchanged config restarted Hysteria: %v", err)
	}
	// A new user changes the file: restart attempted again.
	*a.hyUsers = append(*a.hyUsers, hysteriaUser{ID: "aaaaaaaa-0000-4000-8000-000000000002"})
	if err := a.applyHysteria(context.Background()); err == nil {
		t.Fatal("changed config didn't restart Hysteria")
	}
}
