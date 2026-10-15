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
	if err := goose.SetDialect("postgres"); err != nil {
		log.Error("set migration dialect", "error", err)
		os.Exit(1)
	}
	for _, target := range []struct{ url, dir string }{
		{cfg.DatabaseURL, "migrations"},
		{cfg.PIIDatabaseURL, "migrations_pii"},
	} {
		if err := migrate(target.url, target.dir); err != nil {
			log.Error("run migrations", "dir", target.dir, "error", err)
			os.Exit(1)
		}
		log.Info("migrations applied", "dir", target.dir)
	}
}

func migrate(url, dir string) error {
	db, err := sql.Open("pgx", url)
	if err != nil {
		return err
	}
	defer db.Close()
	return goose.Up(db, dir)
}
