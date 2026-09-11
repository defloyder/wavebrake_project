package redisstore

import (
	"context"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

type Store struct {
	client *redis.Client
}

func New(addr, password string, db int) *Store {
	return &Store{client: redis.NewClient(&redis.Options{Addr: addr, Password: password, DB: db})}
}

func (s *Store) Close() error {
	return s.client.Close()
}

func (s *Store) Ping(ctx context.Context) error {
	return s.client.Ping(ctx).Err()
}

func (s *Store) SaveNodeHeartbeat(ctx context.Context, nodeID string, at time.Time) error {
	key := fmt.Sprintf("wavebreak:node:%s:heartbeat", nodeID)
	return s.client.Set(ctx, key, at.UTC().Format(time.RFC3339Nano), 5*time.Minute).Err()
}
