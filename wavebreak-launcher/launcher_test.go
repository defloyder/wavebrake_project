package main

import (
	"context"
	"testing"
)

func launcherFor(sys System, inst map[string]string, rels map[string]*Release) *Launcher {
	return &Launcher{
		system: sys,
		installed: func(appID string) *Installed {
			for _, p := range catalog {
				if p.AppID == appID {
					if v, ok := inst[p.ID]; ok {
						return &Installed{Version: v, Dir: `C:\x`}
					}
				}
			}
			return nil
		},
		fetch: func(_ context.Context, manifests []string) (*Release, error) {
			for _, p := range catalog {
				if len(p.Manifests) > 0 && p.Manifests[0] == manifests[0] {
					if r := rels[p.ID]; r != nil {
						return r, nil
					}
					if p.ID == "wavebreak-lite" {
						return nil, errNotPublished
					}
				}
			}
			return nil, context.DeadlineExceeded
		},
		progress: func(string, int64, int64, string) {},
		releases: map[string]*Release{},
		busy:     map[string]bool{},
	}
}

func byID(st State) map[string]ProductState {
	m := map[string]ProductState{}
	for _, p := range st.Products {
		m[p.ID] = p
	}
	return m
}

var rel1014 = &Release{VersionName: "1.0.14", URL: "https://dl.wavebreak.com.tr/downloads/x.exe"}

func TestRecommendsByArchitecture(t *testing.T) {
	x64 := byID(launcherFor(System{Arch: "x64", Build: 22631}, nil, map[string]*Release{"wavebreak": rel1014}).State(context.Background()))
	if !x64["wavebreak"].Recommended || x64["wavebreak-lite"].Recommended {
		t.Fatalf("x64 should recommend the full app: %+v", x64)
	}
	if x64["wavebreak"].Status != "available" || x64["wavebreak"].Latest != "1.0.14" {
		t.Fatalf("full app state: %+v", x64["wavebreak"])
	}
	if x64["wavebreak-lite"].Status != "soon" {
		t.Fatalf("Lite without a manifest should be soon: %+v", x64["wavebreak-lite"])
	}
	x86 := byID(launcherFor(System{Arch: "x86", Build: 19045}, nil, nil).State(context.Background()))
	if x86["wavebreak"].Status != "incompatible" || !x86["wavebreak-lite"].Recommended {
		t.Fatalf("x86 should get Lite: %+v", x86)
	}
	arm := byID(launcherFor(System{Arch: "arm64", Build: 22631}, nil, nil).State(context.Background()))
	if !arm["wavebreak"].Compatible {
		t.Fatal("ARM64 Windows runs the x64 app")
	}
	old := byID(launcherFor(System{Arch: "x64", Build: 7601}, nil, nil).State(context.Background()))
	if old["wavebreak"].Compatible || old["wavebreak-lite"].Compatible {
		t.Fatal("Windows 7 runs neither")
	}
}

func TestInstalledAndUpdate(t *testing.T) {
	st := byID(launcherFor(System{Arch: "x64", Build: 22631},
		map[string]string{"wavebreak": "1.0.13"}, map[string]*Release{"wavebreak": rel1014}).State(context.Background()))
	if st["wavebreak"].Status != "update" || st["wavebreak"].Installed != "1.0.13" {
		t.Fatalf("update: %+v", st["wavebreak"])
	}
	st = byID(launcherFor(System{Arch: "x64", Build: 22631},
		map[string]string{"wavebreak": "1.0.14"}, map[string]*Release{"wavebreak": rel1014}).State(context.Background()))
	if st["wavebreak"].Status != "installed" {
		t.Fatalf("installed: %+v", st["wavebreak"])
	}
	off := byID(launcherFor(System{Arch: "x64", Build: 22631}, nil, nil).State(context.Background()))
	if off["wavebreak"].Status != "offline" {
		t.Fatalf("no manifest reachable: %+v", off["wavebreak"])
	}
	if off["android"].Status != "link" {
		t.Fatalf("phone/TV is a link: %+v", off["android"])
	}
}

func TestNewer(t *testing.T) {
	for _, c := range []struct {
		a, b string
		want bool
	}{
		{"1.0.14", "1.0.13", true}, {"1.0.13", "1.0.14", false}, {"1.0.14", "1.0.14", false},
		{"1.1", "1.0.99", true}, {"2.0.0", "10.0.0", false}, {"1.0.14", "1.0.14.0", false},
	} {
		if got := newer(c.a, c.b); got != c.want {
			t.Errorf("newer(%s,%s)=%v", c.a, c.b, got)
		}
	}
}

func TestDownloadsOnlyFromWavebreak(t *testing.T) {
	for u, want := range map[string]bool{
		"https://dl.wavebreak.com.tr/downloads/a.exe": true,
		"https://wavebreak.com.tr/downloads/a.exe":    true,
		"http://dl.wavebreak.com.tr/downloads/a.exe":  false,
		"https://evil.example/a.exe":                  false,
		"https://wavebreak.com.tr.evil.example/a.exe": false,
		"https://dl.wavebreak.com.tr@evil.example/a":  false,
	} {
		if got := allowedURL(u); got != want {
			t.Errorf("allowedURL(%s)=%v", u, got)
		}
	}
	r := Release{URL: "https://dl.wavebreak.com.tr/a.exe", Mirrors: []string{"http://x/a.exe", "https://wavebreak.com.tr/a.exe"}}
	if got := r.Links(); len(got) != 2 {
		t.Fatalf("https links only: %v", got)
	}
}

func TestInstallerResult(t *testing.T) {
	if installerResult(0) != nil {
		t.Fatal("0 is success")
	}
	for _, code := range []uint32{2, 5, 7, 8, 3} {
		if installerResult(code) == nil {
			t.Fatalf("code %d must be reported", code)
		}
	}
}
