package main

import (
	"context"
	"fmt"
	"os"
)

// The launcher keeps itself current (owner, 14.10: the launcher is the
// way into every WAVEBREAK program on the PC, so it updates like them):
// a manifest of its own, the same format as the apps'.
var launcherManifests = []string{
	"https://wavebreak.com.tr/downloads/version-launcher.json",
	"https://dl.wavebreak.com.tr/downloads/version-launcher.json",
}

// SelfUpdate is what the page shows about the launcher itself.
type SelfUpdate struct {
	Version   string `json:"version"`   // this launcher
	Available string `json:"available"` // a newer one, "" when none
}

// CheckSelf asks whether a newer launcher is published.
func (l *Launcher) CheckSelf(ctx context.Context) SelfUpdate {
	st := SelfUpdate{Version: launcherVersion}
	rel, err := l.fetch(ctx, launcherManifests)
	if err == nil && rel != nil && newer(rel.VersionName, launcherVersion) {
		st.Available = rel.VersionName
	}
	return st
}

// UpdateSelf downloads the newer launcher next to [exe], swaps it in (a
// running exe can be renamed on Windows, not overwritten) and starts it
// through [restart]; the caller then quits. The old copy is removed on
// the next start ([CleanupSelf]).
func (l *Launcher) UpdateSelf(ctx context.Context, exe string, restart func(path string) error) error {
	rel, err := l.fetch(ctx, launcherManifests)
	if err != nil {
		return fmt.Errorf("сервер обновлений не ответил: %w", err)
	}
	if !newer(rel.VersionName, launcherVersion) {
		return fmt.Errorf("уже последняя версия")
	}
	fresh := exe + ".new"
	var last error
	for _, link := range rel.Links() {
		if !allowedURL(link) {
			continue
		}
		if last = l.download(ctx, "launcher", link, fresh); last == nil {
			break
		}
	}
	if last != nil {
		return last
	}
	old := exe + ".old"
	os.Remove(old)
	if err := os.Rename(exe, old); err != nil {
		os.Remove(fresh)
		return err
	}
	if err := os.Rename(fresh, exe); err != nil {
		os.Rename(old, exe)
		return err
	}
	l.progress("launcher", 1, 1, "starting")
	return restart(exe)
}

// CleanupSelf removes what an update left behind.
func CleanupSelf(exe string) {
	os.Remove(exe + ".old")
	os.Remove(exe + ".new")
}
