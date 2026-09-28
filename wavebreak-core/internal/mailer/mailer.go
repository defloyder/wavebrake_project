// Package mailer sends WAVEBREAK's transactional email (verification codes,
// welcome, password reset, purchase) over SMTP with STARTTLS — Brevo's
// relay in production. It is off (Enabled() == false) until host, user,
// password and sender are configured, and callers then keep the old,
// email-less behaviour.
package mailer

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/tls"
	"encoding/hex"
	"errors"
	"fmt"
	"mime"
	"mime/quotedprintable"
	"net"
	"net/mail"
	"net/smtp"
	"strconv"
	"strings"
	"time"
)

// Config is read from WAVEBREAK_SMTP_* (see internal/config).
type Config struct {
	Host     string
	Port     int
	Username string
	Password string
	// From is the sender address (no-reply@...); FromName its display name.
	From     string
	FromName string
	// ReplyTo is where a user's reply goes (the support mailbox).
	ReplyTo string
}

// Message is one email, both an HTML and a plain-text body.
type Message struct {
	To      string
	Subject string
	HTML    string
	Text    string
}

// Sender delivers messages. *SMTP is the real one; tests use their own.
type Sender interface {
	Enabled() bool
	Send(ctx context.Context, msg Message) error
}

// ErrNotConfigured is returned by Send when SMTP isn't configured.
var ErrNotConfigured = errors.New("mailer: SMTP is not configured")

type SMTP struct {
	cfg     Config
	timeout time.Duration
}

func NewSMTP(cfg Config) *SMTP {
	if cfg.Port == 0 {
		cfg.Port = 587
	}
	if cfg.FromName == "" {
		cfg.FromName = "WAVEBREAK"
	}
	return &SMTP{cfg: cfg, timeout: 20 * time.Second}
}

func (s *SMTP) Enabled() bool {
	return s != nil && s.cfg.Host != "" && s.cfg.Username != "" && s.cfg.Password != "" && s.cfg.From != ""
}

func (s *SMTP) Send(ctx context.Context, msg Message) error {
	if !s.Enabled() {
		return ErrNotConfigured
	}
	to, err := mail.ParseAddress(msg.To)
	if err != nil {
		return fmt.Errorf("mailer: bad recipient: %w", err)
	}
	body, err := s.compose(msg, to.Address)
	if err != nil {
		return err
	}

	addr := net.JoinHostPort(s.cfg.Host, strconv.Itoa(s.cfg.Port))
	dialCtx, cancel := context.WithTimeout(ctx, s.timeout)
	defer cancel()
	conn, err := (&net.Dialer{}).DialContext(dialCtx, "tcp", addr)
	if err != nil {
		return fmt.Errorf("mailer: connect: %w", err)
	}
	_ = conn.SetDeadline(time.Now().Add(s.timeout))
	client, err := smtp.NewClient(conn, s.cfg.Host)
	if err != nil {
		conn.Close()
		return fmt.Errorf("mailer: greeting: %w", err)
	}
	defer client.Close()
	if err := client.StartTLS(&tls.Config{ServerName: s.cfg.Host, MinVersion: tls.VersionTLS12}); err != nil {
		return fmt.Errorf("mailer: starttls: %w", err)
	}
	if err := client.Auth(smtp.PlainAuth("", s.cfg.Username, s.cfg.Password, s.cfg.Host)); err != nil {
		return fmt.Errorf("mailer: auth: %w", err)
	}
	if err := client.Mail(s.cfg.From); err != nil {
		return fmt.Errorf("mailer: mail from: %w", err)
	}
	if err := client.Rcpt(to.Address); err != nil {
		return fmt.Errorf("mailer: rcpt: %w", err)
	}
	w, err := client.Data()
	if err != nil {
		return fmt.Errorf("mailer: data: %w", err)
	}
	if _, err := w.Write(body); err != nil {
		return fmt.Errorf("mailer: write: %w", err)
	}
	if err := w.Close(); err != nil {
		return fmt.Errorf("mailer: send: %w", err)
	}
	return client.Quit()
}

// compose builds the MIME message: multipart/alternative, UTF-8,
// quoted-printable parts.
func (s *SMTP) compose(msg Message, to string) ([]byte, error) {
	boundary, err := randomHex(12)
	if err != nil {
		return nil, err
	}
	id, err := randomHex(16)
	if err != nil {
		return nil, err
	}
	domain := "wavebreak.com.tr"
	if at := strings.LastIndex(s.cfg.From, "@"); at >= 0 {
		domain = s.cfg.From[at+1:]
	}
	from := mail.Address{Name: s.cfg.FromName, Address: s.cfg.From}

	var b bytes.Buffer
	header := func(k, v string) { fmt.Fprintf(&b, "%s: %s\r\n", k, v) }
	header("From", from.String())
	header("To", to)
	if s.cfg.ReplyTo != "" {
		header("Reply-To", s.cfg.ReplyTo)
	}
	header("Subject", mime.QEncoding.Encode("utf-8", msg.Subject))
	header("Date", time.Now().UTC().Format(time.RFC1123Z))
	header("Message-ID", "<"+id+"@"+domain+">")
	header("MIME-Version", "1.0")
	header("Content-Type", `multipart/alternative; boundary="`+boundary+`"`)
	b.WriteString("\r\n")

	for _, part := range []struct{ kind, body string }{
		{"text/plain", msg.Text},
		{"text/html", msg.HTML},
	} {
		fmt.Fprintf(&b, "--%s\r\n", boundary)
		fmt.Fprintf(&b, "Content-Type: %s; charset=utf-8\r\n", part.kind)
		b.WriteString("Content-Transfer-Encoding: quoted-printable\r\n\r\n")
		qp := quotedprintable.NewWriter(&b)
		if _, err := qp.Write([]byte(part.body)); err != nil {
			return nil, err
		}
		if err := qp.Close(); err != nil {
			return nil, err
		}
		b.WriteString("\r\n")
	}
	fmt.Fprintf(&b, "--%s--\r\n", boundary)
	return b.Bytes(), nil
}

func randomHex(n int) (string, error) {
	buf := make([]byte, n)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf), nil
}
