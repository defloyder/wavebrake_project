package mailer

import (
	"bytes"
	"io"
	"mime"
	"mime/multipart"
	"net/mail"
	"strings"
	"testing"
	"time"
)

func TestComposeIsValidMultipartUTF8(t *testing.T) {
	s := NewSMTP(Config{Host: "smtp.test", Username: "u", Password: "p", From: "no-reply@wavebreak.com.tr", ReplyTo: "support@wavebreak.com.tr"})
	msg := VerificationCode("ru", "user@example.com", "123456", 15*time.Minute)
	raw, err := s.compose(msg, "user@example.com")
	if err != nil {
		t.Fatal(err)
	}
	parsed, err := mail.ReadMessage(bytes.NewReader(raw))
	if err != nil {
		t.Fatal(err)
	}
	subject, err := new(mime.WordDecoder).DecodeHeader(parsed.Header.Get("Subject"))
	if err != nil || subject != "Код подтверждения WAVEBREAK: 123456" {
		t.Fatalf("subject %q (%v)", subject, err)
	}
	if got := parsed.Header.Get("Reply-To"); got != "support@wavebreak.com.tr" {
		t.Fatalf("reply-to %q", got)
	}
	if from := parsed.Header.Get("From"); !strings.Contains(from, "no-reply@wavebreak.com.tr") {
		t.Fatalf("from %q", from)
	}
	if !strings.HasSuffix(parsed.Header.Get("Message-ID"), "@wavebreak.com.tr>") {
		t.Fatalf("message-id %q", parsed.Header.Get("Message-ID"))
	}
	_, params, err := mime.ParseMediaType(parsed.Header.Get("Content-Type"))
	if err != nil {
		t.Fatal(err)
	}
	reader := multipart.NewReader(parsed.Body, params["boundary"])
	var kinds []string
	for {
		part, err := reader.NextPart() // decodes quoted-printable itself
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatal(err)
		}
		body, _ := io.ReadAll(part)
		kinds = append(kinds, part.Header.Get("Content-Type"))
		if !strings.Contains(string(body), "123456") || !strings.Contains(string(body), "Подтвердите почту") {
			t.Fatalf("part %s lacks the code/title:\n%s", part.Header.Get("Content-Type"), body)
		}
	}
	if len(kinds) != 2 || !strings.HasPrefix(kinds[0], "text/plain") || !strings.HasPrefix(kinds[1], "text/html") {
		t.Fatalf("parts %v", kinds)
	}
}

func TestTemplatesEscapeAndLanguages(t *testing.T) {
	msg := Welcome("en-US", `"><script>x</script>@example.com`)
	if strings.Contains(msg.HTML, "<script>") {
		t.Fatal("recipient not escaped in HTML")
	}
	if msg.Subject != "Welcome to WAVEBREAK" {
		t.Fatalf("subject %q", msg.Subject)
	}
	if Language("tr") != "en" || Language("ru-RU") != "ru" || Language("") != "en" {
		t.Fatal("language mapping")
	}
	until := time.Date(2026, 10, 28, 0, 0, 0, 0, time.UTC)
	if m := SubscriptionActivated("ru", "a@b.c", "Plus", &until); !strings.Contains(m.Text, "28.10.2026") {
		t.Fatalf("purchase text: %s", m.Text)
	}
	if m := PasswordReset("en", "a@b.c", "https://wavebreak.com.tr/reset-password?token=t&x=1", until); !strings.Contains(m.HTML, "token=t&amp;x=1") {
		t.Fatal("reset link not in HTML")
	}
}

func TestDisabledUntilConfigured(t *testing.T) {
	if NewSMTP(Config{Host: "smtp.test"}).Enabled() {
		t.Fatal("enabled without credentials")
	}
	var s *SMTP
	if s.Enabled() {
		t.Fatal("nil sender enabled")
	}
}
