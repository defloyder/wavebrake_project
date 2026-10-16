package main

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime/debug"
	"time"

	"golang.org/x/sys/windows"
)

// The launcher's own log, %LOCALAPPDATA%\WAVEBREAK Launcher\launcher.log:
// a launcher that didn't open on someone's PC (15.10) left nothing to say
// why. Each start writes a few lines; a crash writes its error and stack
// and says so in a message box instead of vanishing.
var startLog *os.File

func openStartLog(dataDir string) {
	path := filepath.Join(dataDir, "launcher.log")
	// Kept short: a fresh file once it passes 256 KB.
	if fi, err := os.Stat(path); err == nil && fi.Size() > 256<<10 {
		_ = os.Remove(path)
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err == nil {
		startLog = f
	}
}

func logf(format string, args ...any) {
	if startLog == nil {
		return
	}
	fmt.Fprintf(startLog, "%s %s\n", time.Now().Format("2006-01-02 15:04:05"), fmt.Sprintf(format, args...))
}

// crashed logs a panic and tells the user where the log is.
func crashed(r any) {
	logf("CRASH: %v\n%s", r, debug.Stack())
	where := filepath.Join(os.Getenv("LOCALAPPDATA"), "WAVEBREAK Launcher", "launcher.log")
	msg, _ := windows.UTF16PtrFromString(fmt.Sprintf(
		"Лаунчер не смог запуститься:\n%v\n\nЖурнал: %s", r, where))
	title, _ := windows.UTF16PtrFromString("WAVEBREAK")
	_, _ = windows.MessageBox(0, msg, title, windows.MB_OK|windows.MB_ICONERROR)
	os.Exit(1)
}
