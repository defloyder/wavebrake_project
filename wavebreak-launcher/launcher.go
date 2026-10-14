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

const launcherVersion = "1.1.0"

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

// download fetches link into file. A dropped or stalled connection (no
// byte for 30 s) is retried a few times, resuming where it stopped
// (HTTP Range), instead of failing the whole install (owner, 13.10).
func (l *Launcher) download(ctx context.Context, id, link, file string) error {
	tmp := file + ".part"
	os.Remove(tmp)
	client := &http.Client{
		Transport: &http.Transport{
			Proxy:                 http.ProxyFromEnvironment,
			DialContext:           (&net.Dialer{Timeout: 15 * time.Second}).DialContext,
			TLSHandshakeTimeout:   15 * time.Second,
			ResponseHeaderTimeout: 20 * time.Second,
		},
		// No overall timeout (big files on slow lines): a stall is cut by
		// the watchdog below.
		CheckRedirect: func(r *http.Request, via []*http.Request) error {
			if !allowedURL(r.URL.String()) || len(via) > 5 {
				return fmt.Errorf("redirect outside WAVEBREAK")
			}
			return nil
		},
	}
	var last error
	for attempt := 0; attempt < downloadAttempts; attempt++ {
		if attempt > 0 {
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(time.Duration(attempt) * 2 * time.Second):
			}
		}
		done, total, err := l.downloadOnce(ctx, client, id, link, tmp)
		if err == nil {
			if done < 1<<20 || (total > 0 && done != total) {
				os.Remove(tmp)
				return fmt.Errorf("файл скачался не полностью")
			}
			l.progress(id, done, total, "download")
			os.Remove(file)
			return os.Rename(tmp, file)
		}
		last = err
		if ctx.Err() != nil {
			break
		}
	}
	os.Remove(tmp)
	return last
}

const (
	downloadAttempts = 4
	downloadStall    = 30 * time.Second
)

// downloadOnce continues tmp from its current size; returns the bytes
// on disk and the full size (-1 when the server didn't say).
func (l *Launcher) downloadOnce(ctx context.Context, client *http.Client, id, link, tmp string) (int64, int64, error) {
	var have int64
	if st, err := os.Stat(tmp); err == nil {
		have = st.Size()
	}
	attemptCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	stall := time.AfterFunc(downloadStall, cancel)
	defer stall.Stop()

	req, err := http.NewRequestWithContext(attemptCtx, http.MethodGet, link, nil)
	if err != nil {
		return have, -1, err
	}
	req.Header.Set("User-Agent", "WAVEBREAK-Launcher/"+launcherVersion)
	if have > 0 {
		req.Header.Set("Range", fmt.Sprintf("bytes=%d-", have))
	}
	resp, err := client.Do(req)
	if err != nil {
		return have, -1, err
	}
	defer resp.Body.Close()
	flags := os.O_CREATE | os.O_WRONLY
	var total int64 = -1
	switch {
	case have > 0 && resp.StatusCode == http.StatusPartialContent:
		flags |= os.O_APPEND
		if resp.ContentLength >= 0 {
			total = have + resp.ContentLength
		}
	case resp.StatusCode == http.StatusOK:
		// A server that ignores Range sends it all again.
		flags |= os.O_TRUNC
		have = 0
		total = resp.ContentLength
	default:
		return have, -1, fmt.Errorf("%s: %d", path.Base(link), resp.StatusCode)
	}
	out, err := os.OpenFile(tmp, flags, 0o644)
	if err != nil {
		return have, total, err
	}
	defer out.Close()
	done := have
	buf := make([]byte, 256<<10)
	lastReport := time.Time{}
	for {
		n, rerr := resp.Body.Read(buf)
		if n > 0 {
			stall.Reset(downloadStall)
			if _, werr := out.Write(buf[:n]); werr != nil {
				return done, total, werr
			}
			done += int64(n)
			if time.Since(lastReport) > 150*time.Millisecond {
				lastReport = time.Now()
				l.progress(id, done, total, "download")
			}
		}
		if rerr == io.EOF {
			return done, total, nil
		}
		if rerr != nil {
			if attemptCtx.Err() != nil && ctx.Err() == nil {
				return done, total, fmt.Errorf("скачивание зависло, пробую снова")
			}
			return done, total, rerr
		}
	}
}

// Probe is one server in the network check.
type Probe struct {
	Name string `json:"name"`
	// Not shown: the page names the service, not its address (owner,
	// 13.10: no need to show every domain).
	Host string `json:"-"`
	Ms   int    `json:"ms"` // TLS handshake time; -1 = unreachable
}

// NetCheck: how fast WAVEBREAK's servers answer from here (TCP + TLS).
func NetCheck(ctx context.Context) []Probe {
	probes := []Probe{
		{Name: "Сайт", Host: "wavebreak.com.tr"},
		{Name: "Аккаунт", Host: "core.wavebreak.com.tr"},
		{Name: "Аккаунт, запасной путь", Host: "api.wavebreak.com.tr"},
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

// installerResult: what an Inno Setup exit code means for the person
// (https://jrsoftware.org/ishelp/topic_setupexitcodes.htm). nil = done.
func installerResult(code uint32) error {
	switch code {
	case 0:
		return nil
	case 2, 5:
		return fmt.Errorf("установка отменена")
	case 7:
		return fmt.Errorf("установка прервана: не удалось закрыть работающую программу — закройте WAVEBREAK (и VPN в нём) и нажмите ещё раз")
	case 8:
		return fmt.Errorf("установка почти завершена: перезагрузите компьютер")
	default:
		return fmt.Errorf("установщик завершился с ошибкой (код %d) — попробуйте ещё раз", code)
	}
}
