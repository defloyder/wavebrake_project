package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"wavebreak-core/internal/app"
	"wavebreak-core/internal/config"
	"wavebreak-core/internal/database"
	"wavebreak-core/internal/httpapi"
	"wavebreak-core/internal/messaging"
	"wavebreak-core/internal/redisstore"
	"wavebreak-core/internal/store"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	cfg, err := config.Load()
	if err != nil {
		log.Error("load config", "error", err)
		os.Exit(1)
	}

	db, err := database.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Error("open database", "error", err)
		os.Exit(1)
	}
	defer db.Close()

	redis := redisstore.New(cfg.RedisAddr, cfg.RedisPassword, cfg.RedisDB)
	publisher, err := messaging.Connect(cfg.RabbitMQURL)
	if err != nil {
		log.Warn("rabbitmq unavailable at startup; outbox worker will retry", "error", err)
	}

	a := &app.App{
		Config:    cfg,
		Log:       log,
		Store:     store.New(db),
		Redis:     redis,
		Publisher: publisher,
	}
	defer a.Close(context.Background())

	server := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           httpapi.New(a),
		ReadHeaderTimeout: 5 * time.Second,
	}

	go func() {
		log.Info("wavebreak core api listening", "addr", cfg.HTTPAddr)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error("api server failed", "error", err)
			stop()
		}
	}()

	<-ctx.Done()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := server.Shutdown(shutdownCtx); err != nil {
		log.Error("api shutdown failed", "error", err)
	}
}
