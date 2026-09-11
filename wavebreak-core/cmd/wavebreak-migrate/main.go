package main

import (
	"database/sql"
	"log/slog"
	"os"

	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"

	"wavebreak-core/internal/config"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	cfg, err := config.Load()
	if err != nil {
		log.Error("load config", "error", err)
		os.Exit(1)
	}
	db, err := sql.Open("pgx", cfg.DatabaseURL)
	if err != nil {
		log.Error("open database", "error", err)
		os.Exit(1)
	}
	defer db.Close()
	if err := goose.SetDialect("postgres"); err != nil {
		log.Error("set migration dialect", "error", err)
		os.Exit(1)
	}
	if err := goose.Up(db, "migrations"); err != nil {
		log.Error("run migrations", "error", err)
		os.Exit(1)
	}
	log.Info("migrations applied")
}
