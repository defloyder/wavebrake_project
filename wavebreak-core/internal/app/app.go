package app

import (
	"context"
	"log/slog"

	"wavebreak-core/internal/config"
	"wavebreak-core/internal/messaging"
	"wavebreak-core/internal/redisstore"
	"wavebreak-core/internal/store"
)

type App struct {
	Config    config.Config
	Log       *slog.Logger
	Store     *store.Store
	Redis     *redisstore.Store
	Publisher *messaging.Publisher
}

func (a *App) Close(ctx context.Context) {
	if a.Publisher != nil {
		if err := a.Publisher.Close(); err != nil {
			a.Log.WarnContext(ctx, "close rabbitmq publisher", "error", err)
		}
	}
	if a.Redis != nil {
		if err := a.Redis.Close(); err != nil {
			a.Log.WarnContext(ctx, "close redis", "error", err)
		}
	}
}
