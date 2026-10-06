// WAVEBREAK Lite — a small VPN client for 32-bit Windows, where the full
// Flutter app can't run (Flutter builds Windows apps for x64/ARM64 only).
// Sign in, pick a server, connect: sing-box (x86) with a TUN adapter
// (wintun) carries all traffic, like the full app. The window is a local
// page in the default browser.
package main

import (
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

var version = "1.0.0" // set by build.sh

func main() {
	setupLog()
	serve := len(os.Args) > 2 && os.Args[1] == "--serve"
	if alreadyRunning() {
		openUI()
		return
	}
	if !isAdmin() {
		// The tunnel needs administrator rights (TUN adapter, routes):
		// ask once through UAC, then open the page as the normal user.
		exe, _ := os.Executable()
		// The token is made here and handed over, so the page opens even when
		// UAC runs the elevated copy as another (administrator) account.
		token := randomHex(24)
		if err := shellExecute("runas", exe, "--serve "+token); err != nil {
			messageBox("WAVEBREAK Lite", "Для VPN нужны права администратора. Запустите программу снова и разрешите запуск.")
			return
		}
		for i := 0; i < 120 && !alreadyRunning(); i++ {
			time.Sleep(500 * time.Millisecond)
		}
		openUIWith(token)
		return
	}
	token := randomHex(24)
	if serve {
		token = os.Args[2]
	}
	run(token, !serve)
}

// run serves the page until "Close" is pressed.
func run(token string, openPage bool) {
	exe, _ := os.Executable()
	state := loadState()
	app := &App{
		token:  token,
		core:   newCore(state),
		state:  state,
		tunnel: newTunnel(filepath.Dir(exe)),
		quit:   make(chan struct{}),
	}
	if err := os.WriteFile(tokenFile(), []byte(app.token), 0o600); err != nil {
		logf("token file: %v", err)
	}
	ln, err := net.Listen("tcp", "127.0.0.1:"+uiPort)
	if err != nil {
		messageBox("WAVEBREAK Lite", "Не удалось запустить: порт "+uiPort+" занят.")
		return
	}
	srv := &http.Server{Handler: app.routes(), ReadHeaderTimeout: 10 * time.Second}
	go func() { _ = srv.Serve(ln) }()
	logf("WAVEBREAK Lite %s started", version)
	if app.core.SignedIn() {
		go app.loadServers()
	}
	if openPage {
		openUIWith(token)
	}
	<-app.quit
	_ = srv.Close()
	_ = os.Remove(tokenFile())
	logf("WAVEBREAK Lite closed")
}

func alreadyRunning() bool {
	c := &http.Client{Timeout: 700 * time.Millisecond}
	resp, err := c.Get("http://127.0.0.1:" + uiPort + "/ping")
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	b := make([]byte, 32)
	n, _ := resp.Body.Read(b)
	return strings.HasPrefix(string(b[:n]), "wavebreak-lite")
}

// openUI opens the page in the default browser. Through explorer.exe, so
// even from the elevated process the browser runs as the normal user.
func openUI() {
	token, err := os.ReadFile(tokenFile())
	if err != nil {
		messageBox("WAVEBREAK Lite", "Программа ещё запускается — откройте её снова через пару секунд.")
		return
	}
	openUIWith(strings.TrimSpace(string(token)))
}

func openUIWith(token string) {
	url := "http://127.0.0.1:" + uiPort + "/?t=" + token
	if err := exec.Command("explorer.exe", url).Start(); err != nil {
		_ = shellExecute("open", url, "")
	}
}

var logger *log.Logger

func setupLog() {
	path := filepath.Join(dataDir(), "lite.log")
	if fi, err := os.Stat(path); err == nil && fi.Size() > 1<<20 {
		_ = os.Rename(path, path+".1")
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		logger = log.New(os.Stderr, "", log.LstdFlags)
		return
	}
	logger = log.New(f, "", log.LstdFlags)
}

func logf(format string, args ...any) {
	if logger != nil {
		logger.Output(2, fmt.Sprintf(format, args...))
	}
}
