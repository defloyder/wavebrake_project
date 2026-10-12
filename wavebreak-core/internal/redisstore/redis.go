
package redisstore

import (
	"context"
	"errors"
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

// activeConnectionsTTL outlives a single node usage-report cycle (60s, see
// wavebreak-node's agent) so one missed report doesn't instantly zero out
// a grant's count, but still expires on its own if a node stops reporting
// (e.g. crashed) rather than leaving a stale high count behind forever.
const activeConnectionsTTL = 3 * time.Minute

// SetGrantActiveConnections stores the most recently reported active-
// connection count for a grant (see nodeUsageReport) — a live snapshot,
// not a cumulative counter, so a plain SET+EXPIRE each report is correct:
// a grant reporting zero this cycle must overwrite a nonzero previous
// value, not accumulate.
func (s *Store) SetGrantActiveConnections(ctx context.Context, grantID string, count int) error {
	key := fmt.Sprintf("wavebreak:grant:%s:active", grantID)
	return s.client.Set(ctx, key, count, activeConnectionsTTL).Err()
}

// GrantActiveConnections returns the last-reported active-connection count
// for a grant, or 0 if nothing has been reported recently (key absent or
// expired) — callers can't distinguish "genuinely zero" from "no node has
// reported this grant lately," which is the correct conservative default
// for anything that might gate on this value.
func (s *Store) GrantActiveConnections(ctx context.Context, grantID string) (int, error) {
	key := fmt.Sprintf("wavebreak:grant:%s:active", grantID)
	count, err := s.client.Get(ctx, key).Int()
	if errors.Is(err, redis.Nil) {
		return 0, nil
	}
	return count, err
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

