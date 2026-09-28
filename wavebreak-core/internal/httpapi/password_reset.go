package httpapi

import (
	"context"
	"errors"
	"html/template"
	"net/http"
	"strings"
	"sync"
	"time"

	"wavebreak-core/internal/accounts"
	"wavebreak-core/internal/mailer"
	"wavebreak-core/internal/store"
)

// Password reset for users themselves ("Forgot password?" in the apps):
// POST /v1/auth/password-reset/request emails a one-time link to
// https://wavebreak.com.tr/reset-password?token=..., a page Core serves
// itself (the site's edge nginx routes that one path here), where the new
// password is set through the existing token flow (accounts.PasswordResetService).

// resetMailer delivers reset links by email, in the user's language.
type resetMailer struct {
	mail  mailer.Sender
	store *store.Store
}

func (m resetMailer) SendPasswordReset(ctx context.Context, email, resetURL string, expiresAt time.Time) (string, error) {
	if m.mail == nil || !m.mail.Enabled() {
		return "not_configured", nil
	}
	lang := "ru"
	if u, err := m.store.GetUserByEmail(ctx, email); err == nil {
		if st, err := m.store.UserEmailState(ctx, u.ID); err == nil {
			lang = st.Language
		}
	}
	if err := m.mail.Send(ctx, mailer.PasswordReset(lang, email, resetURL, expiresAt)); err != nil {
		return "failed", err
	}
	return "sent", nil
}

// resetThrottle: one reset email per address per minute, so the public
// endpoint can't be used to flood someone's mailbox.
type resetThrottle struct {
	mu   sync.Mutex
	last map[string]time.Time
}

func (t *resetThrottle) allow(email string, now time.Time) bool {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.last == nil {
		t.last = map[string]time.Time{}
	}
	for k, v := range t.last { // keep the map small
		if now.Sub(v) > 10*time.Minute {
			delete(t.last, k)
		}
	}
	if prev, ok := t.last[email]; ok && now.Sub(prev) < time.Minute {
		return false
	}
	t.last[email] = now
	return true
}

// POST /v1/auth/password-reset/request {email}. Always 202, whether or not
// the account exists, so it can't be used to find out who has one.
func (s *Server) requestPasswordReset(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Email    string `json:"email"`
		Language string `json:"language"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	if s.mail == nil || !s.mail.Enabled() {
		writeError(w, http.StatusServiceUnavailable, "email_unavailable")
		return
	}
	email := store.NormalizeEmail(req.Email)
	accepted := map[string]any{"status": "sent"}
	if email == "" || !s.resetLimit.allow(email, time.Now()) {
		writeJSON(w, http.StatusAccepted, accepted)
		return
	}
	user, err := s.app.Store.GetUserByEmail(r.Context(), email)
	if err != nil || user.DisabledAt != nil || user.Status != "active" {
		writeJSON(w, http.StatusAccepted, accepted)
		return
	}
	if strings.TrimSpace(req.Language) != "" {
		_ = s.app.Store.SetEmailLanguage(r.Context(), user.ID, mailer.Language(req.Language))
	}
	if _, err := s.accounts.reset.Request(r.Context(), accounts.Actor{UserID: user.ID}, user.ID); err != nil {
		s.warn(r.Context(), "self-service password reset", "error", err)
	}
	writeJSON(w, http.StatusAccepted, accepted)
}

type resetPageData struct {
	Lang, Title, Lead, Token, Error, Done         string
	PasswordLabel, RepeatLabel, Button, Hint, App string
	ShowForm                                      bool
}

func resetPageText(lang string) resetPageData {
	if lang == "ru" {
		return resetPageData{
			Lang: "ru", Title: "Новый пароль", Lead: "Придумайте новый пароль для аккаунта WAVEBREAK.",
			PasswordLabel: "Новый пароль", RepeatLabel: "Повторите пароль", Button: "Сохранить пароль",
			Hint: "Не короче 10 символов.", App: "Откройте приложение WAVEBREAK и войдите с новым паролем.",
		}
	}
	return resetPageData{
		Lang: "en", Title: "New password", Lead: "Choose a new password for your WAVEBREAK account.",
		PasswordLabel: "New password", RepeatLabel: "Repeat the password", Button: "Save password",
		Hint: "At least 10 characters.", App: "Open the WAVEBREAK app and sign in with the new password.",
	}
}

// GET/POST /reset-password — the page the reset email links to.
func (s *Server) resetPasswordPage(w http.ResponseWriter, r *http.Request) {
	// ?lang= (the form keeps it), else the browser's language; Russian when
	// neither says anything — the product's main audience.
	lang := "ru"
	if q := r.URL.Query().Get("lang"); q != "" {
		lang = mailer.Language(q)
	} else if al := r.Header.Get("Accept-Language"); al != "" {
		lang = mailer.Language(al)
	}
	data := resetPageText(lang)
	// The token is in the URL: never cache this page or leak it onwards.
	h := w.Header()
	h.Set("Cache-Control", "no-store")
	h.Set("Referrer-Policy", "no-referrer")
	h.Set("X-Frame-Options", "DENY")
	h.Set("X-Content-Type-Options", "nosniff")
	h.Set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'")
	h.Set("Content-Type", "text/html; charset=utf-8")

	switch r.Method {
	case http.MethodGet:
		data.Token = r.URL.Query().Get("token")
		data.ShowForm = data.Token != ""
		if !data.ShowForm {
			data.Error = invalidLinkText(lang)
		}
	case http.MethodPost:
		r.Body = http.MaxBytesReader(w, r.Body, 16<<10)
		if err := r.ParseForm(); err != nil {
			w.WriteHeader(http.StatusBadRequest)
			data.Error = invalidLinkText(lang)
			break
		}
		data.Token = r.PostForm.Get("token")
		password, repeat := r.PostForm.Get("password"), r.PostForm.Get("password2")
		data.ShowForm = true
		switch {
		case password != repeat:
			data.Error = pick(lang, "Пароли не совпадают.", "The passwords don't match.")
		case len(password) < 10:
			data.Error = pick(lang, "Пароль должен быть не короче 10 символов.", "The password must be at least 10 characters.")
		default:
			err := s.accounts.reset.Confirm(r.Context(), data.Token, password)
			var domainErr *accounts.DomainError
			switch {
			case err == nil:
				data.ShowForm = false
				data.Done = pick(lang, "Пароль изменён.", "Password changed.")
			case errors.As(err, &domainErr) && domainErr.Code == accounts.CodeWeakPassword:
				data.Error = pick(lang, "Пароль должен быть не короче 10 символов.", "The password must be at least 10 characters.")
			case errors.As(err, &domainErr) && domainErr.Code == accounts.CodePasswordResetTokenInvalid:
				data.ShowForm = false
				data.Error = invalidLinkText(lang)
			default:
				data.Error = pick(lang, "Не получилось сохранить пароль. Попробуйте ещё раз.", "Couldn't save the password. Please try again.")
			}
		}
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	_ = resetPage.Execute(w, data)
}

func pick(lang, ru, en string) string {
	if lang == "ru" {
		return ru
	}
	return en
}

func invalidLinkText(lang string) string {
	return pick(lang,
		"Ссылка недействительна или устарела. Запросите новую в приложении: «Забыли пароль?» на экране входа.",
		"This link is invalid or has expired. Request a new one in the app: \"Forgot password?\" on the sign-in screen.")
}

var resetPage = template.Must(template.New("reset").Parse(`<!DOCTYPE html>
<html lang="{{.Lang}}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><title>WAVEBREAK — {{.Title}}</title>
<style>
*{box-sizing:border-box}body{margin:0;min-height:100vh;background:#0B1020;color:#E6F2F7;font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;display:flex;align-items:center;justify-content:center;padding:24px 16px}
.wrap{width:100%;max-width:420px}.brand{color:#00D6FF;font-weight:700;letter-spacing:3px;font-size:20px;margin:0 0 18px 4px}
.card{background:#122036;border:1px solid #1B2B30;border-radius:18px;padding:28px 24px}.bar{height:4px;width:56px;border-radius:2px;background:#00D6FF;margin-bottom:20px}
h1{margin:0 0 10px;font-size:24px;color:#fff}p{margin:0 0 18px;color:#C9D6DC;line-height:1.5;font-size:15px}
label{display:block;font-size:13px;color:#93A4AA;margin:0 0 6px}input{width:100%;padding:14px 14px;border-radius:12px;border:1px solid #1B2B30;background:#0B1020;color:#fff;font-size:16px;margin:0 0 14px}
input:focus{outline:none;border-color:#00B4C8}button{width:100%;padding:15px;border:0;border-radius:14px;background:#00D6FF;color:#0B1020;font-size:16px;font-weight:700;cursor:pointer}
.hint{font-size:12px;color:#93A4AA;margin:-6px 0 18px}.err{background:rgba(229,115,115,.12);border:1px solid rgba(229,115,115,.4);color:#F2B8B8;border-radius:12px;padding:12px 14px;margin:0 0 16px;font-size:14px;line-height:1.45}
.ok{background:rgba(0,214,255,.10);border:1px solid rgba(0,180,200,.45);color:#BFF3FF;border-radius:12px;padding:14px;margin:0 0 12px;font-size:16px;font-weight:600}
.foot{margin:16px 4px 0;font-size:12px;color:#5E6F76}.foot a{color:#5E6F76}
</style></head><body><div class="wrap"><div class="brand">WAVEBREAK</div><div class="card"><div class="bar"></div>
<h1>{{.Title}}</h1>
{{if .Done}}<div class="ok">{{.Done}}</div><p>{{.App}}</p>{{else}}
{{if .Error}}<div class="err">{{.Error}}</div>{{end}}
{{if .ShowForm}}<p>{{.Lead}}</p>
<form method="post" action="/reset-password?lang={{.Lang}}" autocomplete="off">
<input type="hidden" name="token" value="{{.Token}}">
<label for="p1">{{.PasswordLabel}}</label><input id="p1" name="password" type="password" minlength="10" required autocomplete="new-password">
<label for="p2">{{.RepeatLabel}}</label><input id="p2" name="password2" type="password" minlength="10" required autocomplete="new-password">
<div class="hint">{{.Hint}}</div>
<button type="submit">{{.Button}}</button></form>{{end}}{{end}}
</div><div class="foot">WAVEBREAK VPN · <a href="mailto:support@wavebreak.com.tr">support@wavebreak.com.tr</a></div></div></body></html>`))
