package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"
)

// System is the machine the launcher runs on.
type System struct {
	Name  string `json:"name"`  // "Windows 11"
	Arch  string `json:"arch"`  // x64 | x86 | arm64
	Build int    `json:"build"` // Windows build number
}

// Installed is an Inno Setup program found in the uninstall list.
type Installed struct {
	Version   string `json:"version"`
	Dir       string `json:"dir"`
	Uninstall string `json:"-"`
}

// Product is one thing the launcher offers.
type Product struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Tagline string `json:"tagline"`
	// Kind: "app" — installed here; "link" — another device (a page opens).
	Kind string `json:"kind"`
	// The CPUs it runs on; arm64 Windows runs x64 and x86 programs too.
	Arch     []string `json:"arch"`
	MinBuild int      `json:"-"`
	// Update manifests (versionCode/versionName/url/mirrors), tried in order.
	Manifests []string `json:"-"`
	AppID     string   `json:"-"` // Inno Setup AppId
	Exe       string   `json:"-"`
	URL       string   `json:"-"` // for links
	Features  []string `json:"features"`
}

// The catalog. More services join here as they appear.
var catalog = []Product{
	{
		ID:      "wavebreak",
		Name:    "WAVEBREAK",
		Tagline: "Полная версия для 64-битной Windows 10 и 11",
		Kind:    "app",
		Arch:    []string{"x64", "arm64"},
		// Windows 10.
		MinBuild: 10240,
		Manifests: []string{
			"https://wavebreak.com.tr/downloads/version-windows.json",
			"https://dl.wavebreak.com.tr/downloads/version-windows.json",
		},
		AppID:    "{B1E4C1E4-3B8F-4C6F-9C3A-1D2E5A7F9B10}",
		Exe:      "wavebreak.exe",
		Features: []string{"Сфера, метрики, все протоколы", "Свои ссылки и подписки", "Автообновление"},
	},
	{
		ID:       "wavebreak-lite",
		Name:     "WAVEBREAK Lite",
		Tagline:  "Лёгкая версия: 32-битная Windows и слабые ПК",
		Kind:     "app",
		Arch:     []string{"x86", "x64", "arm64"},
		MinBuild: 10240,
		Manifests: []string{
			"https://wavebreak.com.tr/downloads/version-lite.json",
			"https://dl.wavebreak.com.tr/downloads/version-lite.json",
		},
		AppID:    "{6E0B7C4A-2F1D-4B8E-9A55-3C7D2E91F4A0}",
		Exe:      "wavebreak-lite.exe",
		Features: []string{"Подключение в один клик", "Мало памяти и места", "Работает на x86"},
	},
	{
		ID:       "android",
		Name:     "Телефон и ТВ",
		Tagline:  "Android, Android TV, Google TV, Fire TV",
		Kind:     "link",
		URL:      "https://wavebreak.com.tr/ru/download",
		Features: []string{"Тот же аккаунт", "Вход на ТВ по QR с телефона"},
	},
}

// Release is what an update manifest says.
type Release struct {
	VersionCode int      `json:"versionCode"`
	VersionName string   `json:"versionName"`
	URL         string   `json:"url"`
	Mirrors     []string `json:"mirrors"`
}

// Links: the main download and its mirrors, https only.
func (r Release) Links() []string {
	var out []string
	for _, u := range append([]string{r.URL}, r.Mirrors...) {
		if strings.HasPrefix(u, "https://") {
			out = append(out, u)
		}
	}
	return out
}

func (p Product) runsOn(s System) bool {
	if p.Kind != "app" {
		return true
	}
	if s.Build < p.MinBuild {
		return false
	}
	for _, a := range p.Arch {
		if a == s.Arch {
			return true
		}
	}
	return false
}

var httpClient = &http.Client{Timeout: 20 * time.Second}

// fetchRelease reads the first manifest that answers.
func fetchRelease(ctx context.Context, manifests []string) (*Release, error) {
	var last error
	for _, u := range manifests {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet,
			u+"?t="+strconv.FormatInt(time.Now().Unix(), 10), nil)
		if err != nil {
			return nil, err
		}
		req.Header.Set("User-Agent", "WAVEBREAK-Launcher/"+launcherVersion)
		resp, err := httpClient.Do(req)
		if err != nil {
			last = err
			continue
		}
		body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
		resp.Body.Close()
		if resp.StatusCode == http.StatusNotFound {
			last = errNotPublished
			continue
		}
		if err != nil || resp.StatusCode != http.StatusOK {
			last = fmt.Errorf("%s: %d", u, resp.StatusCode)
			continue
		}
		var r Release
		if err := json.Unmarshal(body, &r); err != nil || r.VersionName == "" || len(r.Links()) == 0 {
			last = fmt.Errorf("%s: bad manifest", u)
			continue
		}
		return &r, nil
	}
	return nil, last
}

var errNotPublished = fmt.Errorf("not published yet")

// newer reports whether version a ("1.0.14") is above b; non-numeric
// parts count as 0.
func newer(a, b string) bool {
	pa, pb := strings.Split(a, "."), strings.Split(b, ".")
	for i := 0; i < len(pa) || i < len(pb); i++ {
		var x, y int
		if i < len(pa) {
			x, _ = strconv.Atoi(strings.TrimSpace(pa[i]))
		}
		if i < len(pb) {
			y, _ = strconv.Atoi(strings.TrimSpace(pb[i]))
		}
		if x != y {
			return x > y
		}
	}
	return false
}
