package mailer

import "testing"

func TestRecipientDomainNeverReturnsMailbox(t *testing.T) {
	cases := map[string]string{
		"User.Name@Example.COM":        "example.com",
		"Name <user@mail.ru>":          "mail.ru",
		"no-at-sign":                   "",
		"trailing@":                    "",
	}
	for in, want := range cases {
		if got := recipientDomain(in); got != want {
			t.Fatalf("recipientDomain(%q) = %q, want %q", in, got, want)
		}
	}
}
