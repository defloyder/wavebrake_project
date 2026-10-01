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

// Allow implements a fixed-window counter: it increments key and, on the
// first increment of a window, sets the window's TTL. It returns whether the
// count is still within limit. Used by internal/httpapi's auth rate
// limiting; callers are expected to fail open on error rather than block
// requests because Redis is unreachable.
func (s *Store) Allow(ctx context.Context, key string, limit int64, window time.Duration) (bool, error) {
	count, err := s.client.Incr(ctx, key).Result()
	if err != nil {
		return false, err
	}
	if count == 1 {
		if err := s.client.Expire(ctx, key, window).Err(); err != nil {
			return false, err
		}
	}
	return count <= limit, nil
}
