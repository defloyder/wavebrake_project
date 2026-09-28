package mailer

import (
	"bytes"
	"fmt"
	"html/template"
	"strings"
	"time"
)

// Language picks the email language from an app/browser language tag:
// Russian for "ru", English for everything else.
func Language(tag string) string {
	tag = strings.ToLower(strings.TrimSpace(tag))
	if strings.HasPrefix(tag, "ru") {
		return "ru"
	}
	return "en"
}

const supportAddress = "support@wavebreak.com.tr"

// VerificationCode: the code that confirms the address.
func VerificationCode(lang, to, code string, ttl time.Duration) Message {
	minutes := int(ttl.Minutes())
	if Language(lang) == "ru" {
		return build(to, "Код подтверждения WAVEBREAK: "+code, layout{
			Preheader: "Ваш код: " + code,
			Title:     "Подтвердите почту",
			Lead:      "Введите этот код в приложении WAVEBREAK, чтобы подтвердить адрес " + to + ".",
			Code:      code,
			Note:      fmt.Sprintf("Код действует %d минут. Если вы не регистрировались в WAVEBREAK, просто проигнорируйте это письмо.", minutes),
			Lang:      "ru",
		})
	}
	return build(to, "Your WAVEBREAK code: "+code, layout{
		Preheader: "Your code: " + code,
		Title:     "Confirm your email",
		Lead:      "Enter this code in the WAVEBREAK app to confirm " + to + ".",
		Code:      code,
		Note:      fmt.Sprintf("The code is valid for %d minutes. If you didn't sign up for WAVEBREAK, just ignore this email.", minutes),
		Lang:      "en",
	})
}

// Welcome: sent once the address is confirmed.
func Welcome(lang, to string) Message {
	if Language(lang) == "ru" {
		return build(to, "Добро пожаловать в WAVEBREAK", layout{
			Preheader: "Почта подтверждена — аккаунт готов.",
			Title:     "Добро пожаловать!",
			Lead:      "Почта подтверждена, аккаунт WAVEBREAK готов к работе.",
			Items: []string{
				"Выберите тариф в приложении — подключение займёт минуту.",
				"Hysteria2, Direct-TLS и VLESS — если один канал плохо работает у вашего оператора, выберите другой в списке локаций.",
				"Делитесь подпиской с близкими по QR-коду прямо из приложения.",
			},
			Note: "Вопросы и проблемы — ответьте на это письмо или напишите на " + supportAddress + ".",
			Lang: "ru",
		})
	}
	return build(to, "Welcome to WAVEBREAK", layout{
		Preheader: "Your email is confirmed — the account is ready.",
		Title:     "Welcome!",
		Lead:      "Your email is confirmed and your WAVEBREAK account is ready.",
		Items: []string{
			"Pick a plan in the app — connecting takes a minute.",
			"Hysteria2, Direct-TLS and VLESS — if one channel struggles on your network, pick another in the locations list.",
			"Share your subscription with family by QR code right from the app.",
		},
		Note: "Questions or problems? Reply to this email or write to " + supportAddress + ".",
		Lang: "en",
	})
}

// PasswordReset: the admin-requested reset link.
func PasswordReset(lang, to, resetURL string, expiresAt time.Time) Message {
	until := expiresAt.UTC().Format("02.01.2006 15:04 UTC")
	if Language(lang) == "ru" {
		return build(to, "Сброс пароля WAVEBREAK", layout{
			Preheader: "Ссылка для нового пароля.",
			Title:     "Сброс пароля",
			Lead:      "Чтобы задать новый пароль для " + to + ", нажмите кнопку ниже.",
			Button:    "Задать новый пароль",
			URL:       resetURL,
			Note:      "Ссылка действует до " + until + " и сработает один раз. Если вы не просили сброс, проигнорируйте письмо — пароль не изменится.",
			Lang:      "ru",
		})
	}
	return build(to, "Reset your WAVEBREAK password", layout{
		Preheader: "A link to set a new password.",
		Title:     "Password reset",
		Lead:      "To set a new password for " + to + ", press the button below.",
		Button:    "Set a new password",
		URL:       resetURL,
		Note:      "The link works once, until " + until + ". If you didn't ask for a reset, ignore this email — your password stays the same.",
		Lang:      "en",
	})
}

// SubscriptionActivated: a plan was bought or assigned.
func SubscriptionActivated(lang, to, plan string, until *time.Time) Message {
	validRU, validEN := "", ""
	if until != nil {
		validRU = "Действует до " + until.UTC().Format("02.01.2006") + "."
		validEN = "Valid until " + until.UTC().Format("Jan 2, 2006") + "."
	}
	if Language(lang) == "ru" {
		return build(to, "Подписка WAVEBREAK активирована", layout{
			Preheader: "Тариф «" + plan + "» активен.",
			Title:     "Подписка активна",
			Lead:      strings.TrimSpace("Тариф «" + plan + "» активирован. " + validRU),
			Items: []string{
				"Откройте приложение WAVEBREAK и нажмите «Подключить».",
				"Подписку можно продлить заранее — оставшиеся дни не сгорят.",
			},
			Note: "Спасибо, что с нами! Вопросы — " + supportAddress + ".",
			Lang: "ru",
		})
	}
	return build(to, "Your WAVEBREAK subscription is active", layout{
		Preheader: "The " + plan + " plan is active.",
		Title:     "Subscription active",
		Lead:      strings.TrimSpace("The " + plan + " plan is now active. " + validEN),
		Items: []string{
			"Open the WAVEBREAK app and press Connect.",
			"You can renew early — remaining days aren't lost.",
		},
		Note: "Thanks for being with us! Questions: " + supportAddress + ".",
		Lang: "en",
	})
}

type layout struct {
	Preheader string
	Title     string
	Lead      string
	Code      string
	Button    string
	URL       string
	Items     []string
	Note      string
	Lang      string
}

func build(to, subject string, l layout) Message {
	var h bytes.Buffer
	if err := page.Execute(&h, l); err != nil {
		// The templates are static; a failure here is a programming error.
		panic(err)
	}
	return Message{To: to, Subject: subject, HTML: h.String(), Text: plain(l)}
}

func plain(l layout) string {
	var b strings.Builder
	b.WriteString("WAVEBREAK\n\n")
	b.WriteString(l.Title + "\n\n")
	b.WriteString(l.Lead + "\n\n")
	if l.Code != "" {
		b.WriteString("    " + l.Code + "\n\n")
	}
	if l.URL != "" {
		b.WriteString(l.URL + "\n\n")
	}
	for _, item := range l.Items {
		b.WriteString("- " + item + "\n")
	}
	if len(l.Items) > 0 {
		b.WriteString("\n")
	}
	b.WriteString(l.Note + "\n\n-- \nWAVEBREAK · " + supportAddress + "\n")
	return b.String()
}

// Table layout and inline styles only: that is what Gmail, Mail.ru,
// Yandex and Outlook all render the same way. Colours are the app's
// (midnight / card / wave cyan / ice).
var page = template.Must(template.New("page").Parse(`<!DOCTYPE html>
<html lang="{{.Lang}}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="dark light"><meta name="supported-color-schemes" content="dark light"><title>{{.Title}}</title></head>
<body style="margin:0;padding:0;background:#0B1020;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">{{.Preheader}}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#0B1020;">
<tr><td align="center" style="padding:32px 16px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:520px;">
<tr><td style="padding:0 4px 20px 4px;font-family:Arial,Helvetica,sans-serif;font-size:20px;font-weight:bold;letter-spacing:3px;color:#00D6FF;">WAVEBREAK</td></tr>
<tr><td style="background:#122036;border:1px solid #1B2B30;border-radius:16px;padding:32px 28px;font-family:Arial,Helvetica,sans-serif;color:#E6F2F7;">
<div style="height:4px;width:56px;border-radius:2px;background:#00D6FF;margin-bottom:22px;"></div>
<h1 style="margin:0 0 14px 0;font-size:24px;line-height:30px;font-weight:bold;color:#FFFFFF;">{{.Title}}</h1>
<p style="margin:0 0 22px 0;font-size:15px;line-height:23px;color:#C9D6DC;">{{.Lead}}</p>
{{if .Code}}<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 22px 0;"><tr>
<td style="background:#0B1020;border:1px solid #00B4C8;border-radius:12px;padding:16px 26px;font-family:'Courier New',Courier,monospace;font-size:34px;font-weight:bold;letter-spacing:10px;color:#00D6FF;">{{.Code}}</td>
</tr></table>{{end}}
{{if .URL}}<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 22px 0;"><tr>
<td style="background:#00D6FF;border-radius:12px;"><a href="{{.URL}}" style="display:inline-block;padding:14px 26px;font-size:15px;font-weight:bold;color:#0B1020;text-decoration:none;">{{.Button}}</a></td>
</tr></table>{{end}}
{{if .Items}}<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 22px 0;">
{{range .Items}}<tr><td valign="top" style="padding:0 10px 10px 0;font-size:15px;line-height:22px;color:#00D6FF;">&#9679;</td><td style="padding:0 0 10px 0;font-size:15px;line-height:22px;color:#C9D6DC;">{{.}}</td></tr>{{end}}
</table>{{end}}
<p style="margin:0;font-size:13px;line-height:20px;color:#93A4AA;">{{.Note}}</p>
</td></tr>
<tr><td style="padding:18px 4px 0 4px;font-family:Arial,Helvetica,sans-serif;font-size:12px;line-height:18px;color:#5E6F76;">WAVEBREAK VPN · <a href="mailto:support@wavebreak.com.tr" style="color:#5E6F76;">support@wavebreak.com.tr</a></td></tr>
</table>
</td></tr></table>
</body></html>`))
