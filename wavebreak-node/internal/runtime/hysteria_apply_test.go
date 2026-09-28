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
