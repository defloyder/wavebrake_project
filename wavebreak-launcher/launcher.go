package main

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const launcherVersion = "1.0.0"

// Downloads come only from WAVEBREAK's own hosts, whatever a manifest says.
var allowedHosts = map[string]bool{
	"wavebreak.com.tr":    true,
	"dl.wavebreak.com.tr": true,
}

func allowedURL(raw string) bool {
	u, err := url.Parse(raw)
	return err == nil && u.Scheme == "https" && allowedHosts[strings.ToLower(u.Hostname())]
}

// ProductState is one card on the page.
type ProductState struct {
	Product
	Compatible  bool   `json:"compatible"`
	Recommended bool   `json:"recommended"`
	Installed   string `json:"installed"` // version, "" when not installed
	Latest      string `json:"latest"`    // "" when unknown
	// Status: "available" | "installed" | "update" | "soon" | "offline" | "incompatible" | "link"
	Status string `json:"status"`
}

type State struct {
	System   System         `json:"system"`
	Products []ProductState `json:"products"`
	Version  string         `json:"version"`
}

// Launcher holds what the page asks about; the platform bits (registry,
// ShellExecute, the window) sit behind the funcs so the logic is testable.
type Launcher struct {
	system    System
	installed func(appID string) *Installed
	fetch     func(ctx context.Context, manifests []string) (*Release, error)
	progress  func(id string, done, total int64, phase string)

	mu       sync.Mutex
	releases map[string]*Release
	busy     map[string]bool
}

func (l *Launcher) State(ctx context.Context) State {
	st := State{System: l.system, Version: launcherVersion}
	type res struct {
		id  string
		rel *Release
		err error
	}
	ch := make(chan res, len(catalog))
	var n int
	for _, p := range catalog {
		if p.Kind != "app" {
			continue
		}
		n++
		go func(p Product) {
			r, err := l.fetch(ctx, p.Manifests)
			ch <- res{p.ID, r, err}
		}(p)
	}
	errs := map[string]error{}
	for i := 0; i < n; i++ {
		r := <-ch
		l.mu.Lock()
		if r.rel != nil {
			l.releases[r.id] = r.rel
		}
		l.mu.Unlock()
		errs[r.id] = r.err
	}
	recommended := l.recommended()
	for _, p := range catalog {
		ps := ProductState{Product: p, Compatible: p.runsOn(l.system), Recommended: p.ID == recommended}
		if p.Kind == "link" {
			ps.Status = "link"
			st.Products = append(st.Products, ps)
			continue
		}
		if inst := l.installed(p.AppID); inst != nil {
			ps.Installed = inst.Version
		}
		l.mu.Lock()
		rel := l.releases[p.ID]
		l.mu.Unlock()
		if rel != nil {
			ps.Latest = rel.VersionName
		}
		switch {
		case !ps.Compatible:
			ps.Status = "incompatible"
		case ps.Installed != "" && rel != nil && newer(rel.VersionName, ps.Installed):
			ps.Status = "update"
		case ps.Installed != "":
			ps.Status = "installed"
		case rel != nil:
			ps.Status = "available"
		case errors.Is(errs[p.ID], errNotPublished):
			ps.Status = "soon"
		default:
			ps.Status = "offline"
		}
		st.Products = append(st.Products, ps)
	}
	return st
}

// recommended: the full app where it runs, Lite on 32-bit Windows.
func (l *Launcher) recommended() string {
	for _, p := range catalog {
		if p.Kind == "app" && p.runsOn(l.system) {
			return p.ID
		}
	}
	return ""
}

func (l *Launcher) product(id string) (Product, bool) {
	for _, p := range catalog {
		if p.ID == id {
			return p, true
		}
	}
	return Product{}, false
}

// Install downloads the product's setup (mirrors in turn) and starts it.
func (l *Launcher) Install(ctx context.Context, id string, run func(path string) error) error {
	p, ok := l.product(id)
	if !ok || p.Kind != "app" {
		return fmt.Errorf("unknown product")
	}
	if !p.runsOn(l.system) {
		return fmt.Errorf("не подходит для этой системы")
	}
	l.mu.Lock()
	if l.busy[id] {
		l.mu.Unlock()
		return fmt.Errorf("уже скачивается")
	}
	l.busy[id] = true
	rel := l.releases[id]
	l.mu.Unlock()
	defer func() {
		l.mu.Lock()
		delete(l.busy, id)
		l.mu.Unlock()
	}()
	if rel == nil {
		r, err := l.fetch(ctx, p.Manifests)
		if err != nil {
			return fmt.Errorf("сервер обновлений не ответил: %w", err)
		}
		rel = r
	}
	dir := filepath.Join(os.TempDir(), "WAVEBREAK-Launcher")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	var last error
	for _, link := range rel.Links() {
		if !allowedURL(link) {
			continue
		}
		file := filepath.Join(dir, fmt.Sprintf("%s-%s-setup.exe", p.ID, rel.VersionName))
		if err := l.download(ctx, id, link, file); err != nil {
			last = err
			continue
		}
		l.progress(id, 1, 1, "starting")
		return run(file)
	}
	if last == nil {
		last = fmt.Errorf("нет ссылки на скачивание")
	}
	return last
}

func (l *Launcher) download(ctx context.Context, id, link, file string) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, link, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", "WAVEBREAK-Launcher/"+launcherVersion)
	client := &http.Client{
		// No overall timeout (big files on slow lines); a stalled
		// connection is cut by the transport's own timeouts.
		CheckRedirect: func(r *http.Request, via []*http.Request) error {
			if !allowedURL(r.URL.String()) || len(via) > 5 {
				return fmt.Errorf("redirect outside WAVEBREAK")
			}
			return nil
		},
	}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("%s: %d", path.Base(link), resp.StatusCode)
	}
	tmp := file + ".part"
	out, err := os.Create(tmp)
	if err != nil {
		return err
	}
	total := resp.ContentLength
	var done int64
	buf := make([]byte, 256<<10)
	lastReport := time.Time{}
	for {
		n, rerr := resp.Body.Read(buf)
		if n > 0 {
			if _, werr := out.Write(buf[:n]); werr != nil {
				out.Close()
				return werr
			}
			done += int64(n)
			if time.Since(lastReport) > 150*time.Millisecond {
				lastReport = time.Now()
				l.progress(id, done, total, "download")
			}
		}
		if rerr == io.EOF {
			break
		}
		if rerr != nil {
			out.Close()
			os.Remove(tmp)
			return rerr
		}
	}
	out.Close()
	if done < 1<<20 || (total > 0 && done != total) {
		os.Remove(tmp)
		return fmt.Errorf("файл скачался не полностью")
	}
	l.progress(id, done, total, "download")
	os.Remove(file)
	return os.Rename(tmp, file)
}

// Probe is one server in the network check.
type Probe struct {
	Name string `json:"name"`
	Host string `json:"host"`
	Ms   int    `json:"ms"` // TLS handshake time; -1 = unreachable
}

// NetCheck: how fast WAVEBREAK's servers answer from here (TCP + TLS).
func NetCheck(ctx context.Context) []Probe {
	probes := []Probe{
		{Name: "Сайт", Host: "wavebreak.com.tr"},
		{Name: "Аккаунт", Host: "core.wavebreak.com.tr"},
		{Name: "API", Host: "api.wavebreak.com.tr"},
		{Name: "Загрузки", Host: "dl.wavebreak.com.tr"},
	}
	var wg sync.WaitGroup
	for i := range probes {
		wg.Add(1)
		go func(p *Probe) {
			defer wg.Done()
			p.Ms = -1
			start := time.Now()
			d := &net.Dialer{Timeout: 6 * time.Second}
			conn, err := tls.DialWithDialer(d, "tcp", p.Host+":443", &tls.Config{ServerName: p.Host})
			if err != nil {
				return
			}
			conn.Close()
			p.Ms = int(time.Since(start).Milliseconds())
		}(&probes[i])
	}
	wg.Wait()
	return probes
}
