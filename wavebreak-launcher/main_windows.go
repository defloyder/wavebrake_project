//go:build windows

// WAVEBREAK Launcher: one small 32-bit exe for every Windows PC. It sees
// the machine (x64 / x86 / ARM64, Windows version), offers the programs
// that run on it — WAVEBREAK (x64) or WAVEBREAK Lite (x86) — and installs,
// updates, opens and removes them; checks how WAVEBREAK's servers answer
// from here; links the phone and TV apps. Its window is a page (ui.html)
// in Edge WebView2, so it looks like the apps: ocean, waves, glass.
package main

import (
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"unsafe"

	webview "github.com/jchv/go-webview2"
	"golang.org/x/sys/windows"
)

//go:embed ui.html
var page string

func main() {
	sharpOnScaledScreens()
	exe, _ := os.Executable()
	if exe != "" {
		CleanupSelf(exe)
	}
	dataDir := filepath.Join(os.Getenv("LOCALAPPDATA"), "WAVEBREAK Launcher")
	_ = os.MkdirAll(dataDir, 0o755)

	w := webview.NewWithOptions(webview.WebViewOptions{
		DataPath:  dataDir,
		AutoFocus: true,
		WindowOptions: webview.WindowOptions{
			Title:  "WAVEBREAK",
			Width:  1080,
			Height: 700,
			Center: true,
		},
	})
	if w == nil {
		// No WebView2 runtime (rare on Windows 10/11): say so and offer it.
		msg, _ := windows.UTF16PtrFromString(
			"Для окна лаунчера нужен компонент Microsoft Edge WebView2.\n\n" +
				"Открыть страницу загрузки?")
		title, _ := windows.UTF16PtrFromString("WAVEBREAK")
		if r, _ := windows.MessageBox(0, msg, title, windows.MB_YESNO|windows.MB_ICONINFORMATION); r == 6 {
			_ = openWebView2Download()
		}
		return
	}
	defer w.Destroy()
	w.SetSize(720, 560, webview.HintMin)
	neutralFrame(uintptr(w.Window()))

	eval := func(js string) { w.Dispatch(func() { w.Eval(js) }) }
	l := &Launcher{
		system:    detectSystem(),
		installed: installed,
		fetch:     fetchRelease,
		releases:  map[string]*Release{},
		busy:      map[string]bool{},
		progress: func(id string, done, total int64, phase string) {
			eval(fmt.Sprintf("window.wbProgress&&wbProgress(%q,%d,%d,%q)", id, done, total, phase))
		},
	}
	ctx := context.Background()

	must(w.Bind("wbState", func() State { return l.State(ctx) }))
	must(w.Bind("wbNet", func() []Probe { return NetCheck(ctx) }))
	must(w.Bind("wbSelf", func() SelfUpdate { return l.CheckSelf(ctx) }))
	must(w.Bind("wbSelfUpdate", func() {
		go func() {
			err := l.UpdateSelf(ctx, exe, func(path string) error {
				if err := shellExecute("open", path, ""); err != nil {
					return err
				}
				w.Dispatch(w.Terminate)
				return nil
			})
			if err != nil {
				b, _ := json.Marshal(err.Error())
				eval(fmt.Sprintf("window.wbSelfFailed&&wbSelfFailed(%s)", b))
			}
		}()
	}))
	must(w.Bind("wbInstall", func(id string) {
		go func() {
			err := l.Install(ctx, id, runInstaller)
			msg := ""
			if err != nil {
				msg = err.Error()
			}
			b, _ := json.Marshal(msg)
			eval(fmt.Sprintf("window.wbDone&&wbDone(%q,%s)", id, b))
		}()
	}))
	must(w.Bind("wbOpen", func(id string) error {
		p, ok := l.product(id)
		if !ok {
			return fmt.Errorf("unknown product")
		}
		inst := installed(p.AppID)
		if inst == nil || inst.Dir == "" {
			return fmt.Errorf("не установлено")
		}
		return launch(inst.Dir, p.Exe)
	}))
	must(w.Bind("wbRemove", func(id string) error {
		p, ok := l.product(id)
		if !ok {
			return fmt.Errorf("unknown product")
		}
		inst := installed(p.AppID)
		if inst == nil || inst.Uninstall == "" {
			return fmt.Errorf("не установлено")
		}
		return uninstall(inst.Uninstall)
	}))
	must(w.Bind("wbLink", func(id string) error {
		p, ok := l.product(id)
		if !ok || p.URL == "" {
			return fmt.Errorf("no link")
		}
		return openURL(p.URL)
	}))
	must(w.Bind("wbOpenUrl", func(u string) error {
		// The page's own links: the site and Telegram support only.
		if !strings.HasPrefix(u, "https://wavebreak.com.tr") && !strings.HasPrefix(u, "https://t.me/") {
			return fmt.Errorf("link not allowed")
		}
		return openURL(u)
	}))

	w.SetHtml(withAssets(page))
	w.Run()
}

func openWebView2Download() error {
	return shellExecute("open", "https://developer.microsoft.com/microsoft-edge/webview2/", "")
}

func must(err error) {
	if err != nil {
		panic(err)
	}
}

// sharpOnScaledScreens: per-monitor DPI awareness (Windows 10 1703+), else
// system DPI awareness — without it Windows stretches the window as a
// bitmap at 125–150 % scaling and the page looks blurry.
func sharpOnScaledScreens() {
	user32 := windows.NewLazySystemDLL("user32.dll")
	if p := user32.NewProc("SetProcessDpiAwarenessContext"); p.Find() == nil {
		// DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = -4
		if r, _, _ := p.Call(^uintptr(3)); r != 0 {
			return
		}
	}
	if p := user32.NewProc("SetProcessDPIAware"); p.Find() == nil {
		p.Call()
	}
}

// neutralFrame: a fixed dark title bar and border (owner, 13.10: the white
// system caption, tinted by the Windows accent, didn't belong). Windows 11
// takes the exact colours; Windows 10 (1809+) gets its dark caption.
func neutralFrame(hwnd uintptr) {
	if hwnd == 0 {
		return
	}
	dwm := windows.NewLazySystemDLL("dwmapi.dll")
	set := dwm.NewProc("DwmSetWindowAttribute")
	if set.Find() != nil {
		return
	}
	attr := func(id uint32, value uint32) {
		set.Call(hwnd, uintptr(id), uintptr(unsafe.Pointer(&value)), 4)
	}
	const (
		useDarkMode   = 20 // DWMWA_USE_IMMERSIVE_DARK_MODE
		useDarkMode19 = 19 // the same before Windows 10 20H1
		borderColor   = 34 // DWMWA_BORDER_COLOR
		captionColor  = 35 // DWMWA_CAPTION_COLOR
		textColor     = 36 // DWMWA_TEXT_COLOR
	)
	attr(useDarkMode, 1)
	attr(useDarkMode19, 1)
	// COLORREF is 0x00BBGGRR.
	attr(captionColor, 0x000E0B0A) // #0A0B0E
	attr(borderColor, 0x00302A26)  // #262A30
	attr(textColor, 0x00F0F2F5)    // #F5F2F0
}
