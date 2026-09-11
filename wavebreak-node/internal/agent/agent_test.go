package agent

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"wavebreak-node/internal/config"
)

func TestEnrollHeartbeatAndSync(t *testing.T) {
	var heartbeatSeen bool
	var ackSeen bool
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") == "" {
			t.Fatalf("missing Authorization header for %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/v1/node/enroll":
			_ = json.NewEncoder(w).Encode(enrollResponse{
				Node:         nodeResponse{ID: "node-1", Code: "TR-IST-01", Region: "TR", Status: "online"},
				NodeAPIToken: "node-api-token",
			})
		case "/v1/node/heartbeat":
			heartbeatSeen = true
			_ = json.NewEncoder(w).Encode(nodeResponse{ID: "node-1", Code: "TR-IST-01", Region: "TR", Status: "online"})
		case "/v1/node/state":
			_ = json.NewEncoder(w).Encode(desiredState{NodeID: "node-1", Revision: 1, State: json.RawMessage(`{"protocols":[]}`)})
		case "/v1/node/state/ack":
			ackSeen = true
			_ = json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	a := New(config.Config{
		CoreURL:         server.URL,
		EnrollmentToken: "enrollment-token",
		NodeCode:        "TR-IST-01",
		Region:          "TR",
	}, slog.New(slog.NewTextHandler(os.Stdout, nil)))

	if err := a.Enroll(context.Background()); err != nil {
		t.Fatalf("Enroll returned error: %v", err)
	}
	if err := a.Heartbeat(context.Background()); err != nil {
		t.Fatalf("Heartbeat returned error: %v", err)
	}
	if err := a.Sync(context.Background()); err != nil {
		t.Fatalf("Sync returned error: %v", err)
	}
	if !heartbeatSeen {
		t.Fatal("expected heartbeat endpoint to be called")
	}
	if !ackSeen {
		t.Fatal("expected desired-state ack endpoint to be called")
	}
}
