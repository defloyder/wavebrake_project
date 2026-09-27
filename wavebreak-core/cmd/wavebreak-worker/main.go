package main

import (
	"context"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	"wavebreak-core/internal/accounts"
	"wavebreak-core/internal/config"
	"wavebreak-core/internal/database"
	"wavebreak-core/internal/messaging"
	"wavebreak-core/internal/observability"
	"wavebreak-core/internal/store"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
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
	st := store.New(db)

	// Subscription lifecycle (grace period, expiry reset) runs regardless
	// of RabbitMQ: it only needs the database.
	lifecycle := accounts.NewSubscriptionLifecycleService(st.Accounts(), st.Accounts(), cfg.Accounts.SubscriptionGrace)
	go runLifecycle(ctx, log, lifecycle)

	var publisher *messaging.Publisher
	for publisher == nil && ctx.Err() == nil {
		publisher, err = messaging.Connect(cfg.RabbitMQURL)
		if err != nil {
			log.Warn("rabbitmq unavailable; retrying", "error", err)
			time.Sleep(5 * time.Second)
		}
	}
	if publisher == nil {
		return
	}
	defer publisher.Close()

	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			events, err := st.FetchOutboxBatch(ctx, 50)
			if err != nil {
				log.Error("fetch outbox", "error", err)
				continue
			}
			for _, ev := range events {
				err := publisher.PublishEvent(ctx, messaging.Event{
					ID: ev.ID, Type: ev.Type, AggregateID: ev.AggregateID, Payload: ev.Payload, CreatedAt: ev.CreatedAt,
				})
				if err != nil {
					observability.RabbitFailures.WithLabelValues("publish").Inc()
					_ = st.MarkOutboxFailed(ctx, ev.ID)
					log.Warn("publish outbox event failed", "event_id", ev.ID, "error", err)
					continue
				}
				observability.RabbitPublish.WithLabelValues(ev.Type).Inc()
				if err := st.MarkOutboxPublished(ctx, ev.ID); err != nil {
					log.Warn("mark outbox published failed", "event_id", ev.ID, "error", err)
				}
			}
		}
	}
}

// lifecycleInterval: past_due/expiry transitions happen within a minute.
const lifecycleInterval = time.Minute

func runLifecycle(ctx context.Context, log *slog.Logger, lifecycle *accounts.SubscriptionLifecycleService) {
	ticker := time.NewTicker(lifecycleInterval)
	defer ticker.Stop()
	for {
		report, err := lifecycle.Run(ctx)
		if err != nil {
			log.Error("subscription lifecycle", "error", err, "past_due", report.PastDue, "expired", report.Expired)
		} else if report.PastDue > 0 || report.Expired > 0 {
			log.Info("subscription lifecycle", "past_due", report.PastDue, "expired", report.Expired)
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}
