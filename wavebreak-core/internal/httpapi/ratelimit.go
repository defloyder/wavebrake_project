package httpapi

import (
	"context"
	"net"
	"net/http"
	"time"

	"wavebreak-core/internal/observability"
)

// rateLimiter is the subset of redisstore.Store's API the auth rate limiters
// need. Defined here (rather than depending on *redisstore.Store directly)
// so tests can substitute an in-memory fake instead of a real Redis
// connection. *redisstore.Store satisfies this interface via its Allow
// method.
type rateLimiter interface {
	Allow(ctx context.Context, key string, limit int64, window time.Duration) (bool, error)
}

// ipRateLimitMiddleware rejects a request once the calling IP has made more
// than limit requests to the named route within window. It fails open (lets
// the request through) when no limiter is configured or Redis errors out,
// matching how the rest of this codebase treats Redis as a best-effort
// accelerator rather than a hard dependency (see nodeHeartbeat in
// server.go). It must be placed after middleware.RealIP in the chain so
// r.RemoteAddr reflects X-Forwarded-For/X-Real-IP rather than the proxy's
// own address.
func ipRateLimitMiddleware(limiter rateLimiter, name string, limit int, window time.Duration) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if limiter == nil || limit <= 0 {
				next.ServeHTTP(w, r)
				return
			}
			key := "ratelimit:" + name + ":ip:" + clientIP(r)
			allowed, err := limiter.Allow(r.Context(), key, int64(limit), window)
			if err != nil {
				observability.RedisErrors.Inc()
				next.ServeHTTP(w, r)
				return
			}
			if !allowed {
				writeError(w, http.StatusTooManyRequests, "too many requests, please try again later")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// checkEmailRateLimit enforces a per-account attempt cap for routes (login)
// where the IP limit alone doesn't stop credential stuffing spread across
// many IPs against a single account. Returns true (allow) if no limiter is
// configured, the limit is disabled, email is empty, or Redis errors out —
// same fail-open behavior as ipRateLimitMiddleware.
func checkEmailRateLimit(ctx context.Context, limiter rateLimiter, name, email string, limit int, window time.Duration) bool {
	if limiter == nil || limit <= 0 || email == "" {
		return true
	}
	key := "ratelimit:" + name + ":email:" + email
	allowed, err := limiter.Allow(ctx, key, int64(limit), window)
	if err != nil {
		observability.RedisErrors.Inc()
		return true
	}
	return allowed
}

func clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
