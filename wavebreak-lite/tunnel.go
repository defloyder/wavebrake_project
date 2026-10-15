package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
)

type tunnelState string

const (
	stIdle       tunnelState = "idle"
	stConnecting tunnelState = "connecting"
	stConnected  tunnelState = "connected"
	stError      tunnelState = "error"
)

// Tunnel runs sing-box (x86 build, with wintun.dll next to it) for one
// link and keeps it alive: restarts it when it exits on its own or when
// three probes in a row fail.
type Tunnel struct {
	mu        sync.Mutex
	state     tunnelState
	lastErr   string
	link      *ShareLink
	cmd       *exec.Cmd
	stopped   chan struct{}
	since     time.Time
	pingMs    int
	job       *killOnCloseJob
	exeDir    string
	stderrBuf *bytes.Buffer
}

func newTunnel(exeDir string) *Tunnel {
	job, err := newKillOnCloseJob()
	if err != nil {
		logf("job object: %v", err)
	}
	return &Tunnel{state: stIdle, exeDir: exeDir, job: job}
}

type tunnelStatus struct {
	State  tunnelState `json:"state"`
	Error  string      `json:"error,omitempty"`
	Since  int64       `json:"since,omitempty"`
	PingMs int         `json:"ping_ms,omitempty"`
}

func (t *Tunnel) Status() tunnelStatus {
	t.mu.Lock()
	defer t.mu.Unlock()
	s := tunnelStatus{State: t.state, Error: t.lastErr, PingMs: t.pingMs}
	if t.state == stConnected {
		s.Since = t.since.Unix()
	}
	return s
}

func (t *Tunnel) configPath() string { return filepath.Join(dataDir(), "sing-box.json") }

// Connect (re)starts the tunnel on [link] and returns once traffic gets
// through or it gave up.
func (t *Tunnel) Connect(link *ShareLink) error {
	t.Disconnect()
	t.mu.Lock()
	t.link = link
	t.state = stConnecting
	t.lastErr = ""
	t.mu.Unlock()
	if err := t.start(); err != nil {
		t.fail(err)
		return err
	}
	if ms, ok := waitForTraffic(20 * time.Second); ok {
		t.mu.Lock()
		t.state, t.since, t.pingMs = stConnected, time.Now(), ms
		stopped := t.stopped
		t.mu.Unlock()
		go t.watch(stopped)
		logf("connected via %s %s:%d", link.ProtocolName(), link.Host, link.Port)
		return nil
	}
	err := errors.New("сервер не отвечает через туннель")
	if msg := t.stderrTail(); msg != "" {
		err = fmt.Errorf("%v: %s", err, msg)
	}
	t.Disconnect()
	t.fail(err)
	return err
}

func (t *Tunnel) fail(err error) {
	t.mu.Lock()
	t.state, t.lastErr = stError, err.Error()
	t.mu.Unlock()
	logf("tunnel: %v", err)
}

func (t *Tunnel) start() error {
	exe := filepath.Join(t.exeDir, "sing-box.exe")
	if _, err := os.Stat(exe); err != nil {
		return errors.New("нет sing-box.exe рядом с программой — переустановите WAVEBREAK Lite")
	}
	cfg, _ := json.MarshalIndent(SingBoxConfig(t.link), "", "  ")
	if err := os.WriteFile(t.configPath(), cfg, 0o600); err != nil {
		return err
	}
	cmd := exec.Command(exe, "run", "-c", t.configPath(), "--disable-color")
	cmd.Dir = t.exeDir
	const createNoWindow = 0x08000000
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: createNoWindow}
	buf := &bytes.Buffer{}
	cmd.Stderr = &capped{buf: buf, max: 16 << 10}
	cmd.Stdout = cmd.Stderr
	if err := cmd.Start(); err != nil {
		return err
	}
	if t.job != nil {
		if err := t.job.assign(cmd.Process.Pid); err != nil {
			logf("assign job: %v", err)
		}
	}
	stopped := make(chan struct{})
	t.mu.Lock()
	t.cmd, t.stopped, t.stderrBuf = cmd, stopped, buf
	t.mu.Unlock()
	go func() {
		_ = cmd.Wait()
		close(stopped)
	}()
	return nil
}

// watch keeps a connected tunnel alive.
func (t *Tunnel) watch(stopped chan struct{}) {
	tick := time.NewTicker(30 * time.Second)
	defer tick.Stop()
	failures := 0
	for {
		select {
		case <-stopped:
			t.mu.Lock()
			current := t.stopped == stopped && t.state == stConnected
			link := t.link
			t.mu.Unlock()
			if !current {
				return // disconnected on purpose
			}
			logf("sing-box exited: %s", t.stderrTail())
			go t.reconnect(link)
			return
		case <-tick.C:
			ms, ok := probe()
			t.mu.Lock()
			if t.stopped != stopped {
				t.mu.Unlock()
				return
			}
			if ok {
				t.pingMs = ms
			}
			link := t.link
			t.mu.Unlock()
			if ok {
				failures = 0
				continue
			}
			failures++
			if failures >= 3 {
				logf("3 probes failed — restarting the tunnel")
				go t.reconnect(link)
				return
			}
		}
	}
}

func (t *Tunnel) reconnect(link *ShareLink) {
	for attempt, wait := 1, 2*time.Second; attempt <= 5; attempt, wait = attempt+1, wait*2 {
		if t.Connect(link) == nil {
			return
		}
		time.Sleep(wait)
		t.mu.Lock()
		gaveUp := t.link != link
		t.mu.Unlock()
		if gaveUp {
			return
		}
	}
}

func (t *Tunnel) Disconnect() {
	t.mu.Lock()
	cmd, stopped := t.cmd, t.stopped
	t.cmd, t.stopped = nil, nil
	if t.state != stError {
		t.state = stIdle
	}
	t.pingMs = 0
	t.mu.Unlock()
	if cmd != nil && cmd.Process != nil {
		_ = cmd.Process.Kill()
		select {
		case <-stopped:
		case <-time.After(5 * time.Second):
		}
	}
	_ = os.Remove(t.configPath())
}

// Stop is a user's "disconnect": also forgets the link (no reconnects).
func (t *Tunnel) Stop() {
	t.mu.Lock()
	t.link = nil
	t.mu.Unlock()
	t.Disconnect()
	t.mu.Lock()
	t.state, t.lastErr = stIdle, ""
	t.mu.Unlock()
}

func (t *Tunnel) stderrTail() string {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.stderrBuf == nil {
		return ""
	}
	lines := strings.Split(strings.TrimSpace(t.stderrBuf.String()), "\n")
	if len(lines) > 3 {
		lines = lines[len(lines)-3:]
	}
	return strings.Join(lines, " | ")
}

var probeClient = &http.Client{Timeout: 8 * time.Second}

// probe fetches a 204 page; with the tunnel up it goes through it.
func probe() (int, bool) {
	start := time.Now()
	resp, err := probeClient.Get("https://www.gstatic.com/generate_204")
	if err != nil {
		return 0, false
	}
	resp.Body.Close()
	return int(time.Since(start).Milliseconds()), resp.StatusCode == 204
}

func waitForTraffic(limit time.Duration) (int, bool) {
	deadline := time.Now().Add(limit)
	time.Sleep(1500 * time.Millisecond) // TUN and routes come up first
	for time.Now().Before(deadline) {
		if ms, ok := probe(); ok {
			return ms, true
		}
		time.Sleep(time.Second)
	}
	return 0, false
}

// capped is a writer that keeps only the last max bytes.
type capped struct {
	mu  sync.Mutex
	buf *bytes.Buffer
	max int
}

func (c *capped) Write(p []byte) (int, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.buf.Write(p)
	if over := c.buf.Len() - c.max; over > 0 {
		c.buf.Next(over)
	}
	return len(p), nil
}
