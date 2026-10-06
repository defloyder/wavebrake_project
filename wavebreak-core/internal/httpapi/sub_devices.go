package httpapi

import (
	"encoding/base64"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"

	"wavebreak-core/internal/store"
)

// Device limit for the public subscription link (owner, 06.10): the link
// may be shared, but every app on every device that loads it takes one of
// the subscription's device slots — the same slots WAVEBREAK's own apps
// use. Happ, v2RayTun, Hiddify and other clients send a hardware id
// (x-hwid) with the request; it is registered like an app installation
// (devices.fingerprint "hwid:<id>", see store.RegisterDevice), so the same
// phone reloading the link keeps its slot, and a device past the limit
// gets a notice instead of servers. Removing the device in WAVEBREAK
// frees the slot. Apps that send no id can't be counted: with
// WAVEBREAK_SUB_REQUIRE_HWID (on by default) they get a notice too.
//
// It gates what the link hands out, not the keys themselves: a key copied
// out of an app that was let in still works elsewhere. Per-device keys
// would close that too.

const (
	subNoticeLimitTitle = "⛔ Превышен лимит устройств"
	subNoticeLimitHint  = "Освободите место: WAVEBREAK → Аккаунт → Устройства"
	subNoticeAppTitle   = "⛔ Приложение не передаёт ID устройства"
	subNoticeAppHint    = "Используйте Happ, v2RayTun или WAVEBREAK"
)

type subGate int

const (
	subAllowed subGate = iota
	subOverLimit
	subNoDeviceID
)

func (s *Server) subscriptionDeviceGate(r *http.Request, userID string) subGate {
	hwid := strings.TrimSpace(r.Header.Get("X-Hwid"))
	if hwid == "" {
		if s.app.Config.Accounts.SubRequireHWID {
			return subNoDeviceID
		}
		return subAllowed
	}
	if len(hwid) > 100 {
		hwid = hwid[:100]
	}
	name := subDeviceName(r)
	platform := strings.ToLower(strings.TrimSpace(r.Header.Get("X-Device-Os")))
	if len(platform) > 32 {
		platform = platform[:32]
	}
	_, _, err := s.app.Store.RegisterDevice(r.Context(), userID, name, platform, "hwid:"+hwid)
	if errors.Is(err, store.ErrLimitReached) {
		return subOverLimit
	}
	if err != nil {
		// A database hiccup shouldn't cut everyone off.
		s.warn(r.Context(), "subscription device registration", "error", err)
	}
	return subAllowed
}

// subDeviceName: "Pixel 8 · Happ" from the client's headers.
func subDeviceName(r *http.Request) string {
	model := strings.TrimSpace(r.Header.Get("X-Device-Model"))
	app := strings.TrimSpace(r.UserAgent())
	if i := strings.IndexAny(app, "/ "); i > 0 {
		app = app[:i]
	}
	var parts []string
	for _, p := range []string{model, app} {
		if p != "" {
			parts = append(parts, p)
		}
	}
	name := strings.Join(parts, " · ")
	if name == "" {
		name = "Device"
	}
	if len(name) > 80 {
		name = name[:80]
	}
	return name
}

// writeSubscriptionNotice answers with a "subscription" whose only entries
// are the message (unreachable placeholder servers named with it) and a
// banner for clients that show one (Happ: announce header).
func writeSubscriptionNotice(w http.ResponseWriter, title, hint string) {
	var links []string
	for _, line := range []string{title, hint} {
		links = append(links, fmt.Sprintf(
			"vless://00000000-0000-0000-0000-000000000000@0.0.0.0:1?encryption=none&type=tcp#%s",
			url.PathEscape(line)))
	}
	b64 := func(s string) string { return "base64:" + base64.StdEncoding.EncodeToString([]byte(s)) }
	w.Header().Set("Profile-Title", b64("WaveBreak"))
	w.Header().Set("Profile-Update-Interval", "1")
	w.Header().Set("Announce", b64(title+". "+hint))
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(base64.StdEncoding.EncodeToString([]byte(strings.Join(links, "\n")))))
}
