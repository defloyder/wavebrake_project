package httpapi

import (
	"context"
	"database/sql"
	"os"
	"testing"

	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/pressly/goose/v3"

	"wavebreak-core/internal/database"
)

// openPIIPoolForTest migrates and opens the PII database that integration
// tests need alongside the main one. Set WAVEBREAK_TEST_PII_DATABASE_URL to
// an EMPTY throwaway database.
func openPIIPoolForTest(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("WAVEBREAK_TEST_PII_DATABASE_URL")
	if dsn == "" {
		t.Skip("WAVEBREAK_TEST_PII_DATABASE_URL not set")
	}
	sqlDB, err := sql.Open("pgx", dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer sqlDB.Close()
	if err := goose.SetDialect("postgres"); err != nil {
		t.Fatal(err)
	}
	if err := goose.Up(sqlDB, "../../migrations_pii"); err != nil {
		t.Fatalf("pii migrations: %v", err)
	}
	pool, err := database.Open(context.Background(), dsn)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	return pool
}
