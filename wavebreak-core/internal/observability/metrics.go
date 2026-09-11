package observability

import (
	"net/http"
	"strconv"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

var (
	HTTPRequests = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "wavebreak_http_requests_total",
		Help: "Total HTTP requests handled by WAVEBREAK Core.",
	}, []string{"method", "route", "status"})

	HTTPRequestDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "wavebreak_http_request_duration_seconds",
		Help:    "HTTP request latency for WAVEBREAK Core.",
		Buckets: prometheus.DefBuckets,
	}, []string{"method", "route", "status"})

	RabbitPublish = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "wavebreak_rabbitmq_publish_total",
		Help: "Published RabbitMQ messages.",
	}, []string{"routing_key"})

	RabbitFailures = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "wavebreak_rabbitmq_failures_total",
		Help: "RabbitMQ publish/consume failures.",
	}, []string{"operation"})

	AuthLogin = promauto.NewCounter(prometheus.CounterOpts{
		Name: "wavebreak_auth_login_total",
		Help: "Successful WAVEBREAK Core logins.",
	})

	AuthLoginFailed = promauto.NewCounter(prometheus.CounterOpts{
		Name: "wavebreak_auth_login_failed_total",
		Help: "Failed WAVEBREAK Core login attempts.",
	})

	NodeSync = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "wavebreak_node_sync_total",
		Help: "Node desired-state sync events.",
	}, []string{"result"})

	NodeSyncFailures = promauto.NewCounter(prometheus.CounterOpts{
		Name: "wavebreak_node_sync_failures_total",
		Help: "Node desired-state sync failures.",
	})

	RedisErrors = promauto.NewCounter(prometheus.CounterOpts{
		Name: "wavebreak_redis_errors_total",
		Help: "Redis errors observed by WAVEBREAK Core.",
	})
)

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(status int) {
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}

func MetricsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(sw, r)
		route := r.URL.Path
		status := strconv.Itoa(sw.status)
		HTTPRequests.WithLabelValues(r.Method, route, status).Inc()
		HTTPRequestDuration.WithLabelValues(r.Method, route, status).Observe(time.Since(start).Seconds())
	})
}
