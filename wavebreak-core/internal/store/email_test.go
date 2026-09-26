package store

import (
	"os"
	"strings"
	"testing"
)

func TestNormalizeEmail(t *testing.T) {
	got := NormalizeEmail("  User.Name@Example.COM\t")
	if got != "user.name@example.com" {
		t.Fatalf("NormalizeEmail() = %q", got)
	}
}

func TestEmailMigrationEnforcesNormalizedUniqueness(t *testing.T) {
	body, err := os.ReadFile("../../migrations/00003_normalize_user_email.sql")
	if err != nil {
		t.Fatalf("read migration: %v", err)
	}
	sql := string(body)
	for _, fragment := range []string{
		"having count(*) > 1",
		"email = lower(btrim(email))",
		"create unique index users_email_normalized_unique_idx",
	} {
		if !strings.Contains(sql, fragment) {
			t.Fatalf("email migration missing %q", fragment)
		}
	}
}
