package main

import (
	"context"
	"errors"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"wavebreak-node/internal/agent"
	"wavebreak-node/internal/config"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	cfg, err := config.Load()
	if err != nil {
		log.Error("invalid wavebreak node configuration", "error", err)
		os.Exit(1)
	}
	a := agent.New(cfg, log)
	if err := a.Run(ctx); err != nil && !errors.Is(err, context.Canceled) {
		log.Error("wavebreak node stopped", "error", err)
		os.Exit(1)
	}
}
