package store

import (
	"os"
	"strings"
	"testing"
)

func TestInitialMigrationContainsProductionReadinessColumns(t *testing.T) {
	body, err := os.ReadFile("../../migrations/00001_initial.sql")
	if err != nil {
		t.Fatalf("read migration: %v", err)
	}
	sql := string(body)
	required := []string{
		"role in ('user', 'support', 'admin', 'superadmin')",
		"disabled_at timestamptz",
		"replaced_by_session_id uuid references sessions(id)",
		"api_token_hash text unique",
		"desired_revision integer not null default 0",
		"applied_revision integer not null default 0",
		"failed_at timestamptz",
		"processed_messages",
	}
	for _, fragment := range required {
		if !strings.Contains(sql, fragment) {
			t.Fatalf("migration missing %q", fragment)
		}
	}
}
