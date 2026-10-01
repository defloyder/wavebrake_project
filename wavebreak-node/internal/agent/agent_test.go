package agent

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
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

// TestSync_GrantDropGuard exercises the grant-count drop guard end to end
// against a fake Core that serves a configurable grant count/revision:
//
//   - a fresh node's first-ever sync starting at 0 grants must apply (never
//     refused as if it were a drop),
//   - a same-count transition applies normally,
//   - a drastic drop (>=minGrantsForDropCheck previously, dropping by more
//     than maxGrantDropRatio) gets refused for up to
//     maxConsecutiveDropRefusals polls, leaving the last-known-good state in
//     effect and never acking the refused revision,
//   - once the same drop has been confirmed maxConsecutiveDropRefusals times
//     in a row, Sync accepts it as the new reality rather than refusing
//     forever.
func TestSync_GrantDropGuard(t *testing.T) {
	type stateResp struct {
		revision int
		grants   int
	}
	var current stateResp
	var acked []int

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/v1/node/state":
			grants := make([]map[string]string, current.grants)
			for i := range grants {
				grants[i] = map[string]string{
					"id":       fmt.Sprintf("grant-%d", i),
					"protocol": "vless-reality",
					"status":   "active",
				}
			}
			payload, _ := json.Marshal(map[string]any{"grants": grants})
			_ = json.NewEncoder(w).Encode(desiredState{
				NodeID:   "node-1",
				Revision: current.revision,
				State:    payload,
			})
		case "/v1/node/state/ack":
			var body map[string]int
			_ = json.NewDecoder(r.Body).Decode(&body)
			acked = append(acked, body["revision"])
			_ = json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
		case "/v1/node/state/fail":
			_ = json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	a := New(config.Config{CoreURL: server.URL}, slog.New(slog.NewTextHandler(io.Discard, nil)))
	a.nodeToken = "test-token"
	ctx := context.Background()

	// (c) a freshly-enrolled node's first-ever sync legitimately starts at 0
	// grants and must not be treated as a suspicious drop.
	current = stateResp{revision: 1, grants: 0}
	if err := a.Sync(ctx); err != nil {
		t.Fatalf("first sync (0 grants) returned error: %v", err)
	}
	if a.appliedRevision != 1 || a.appliedGrantCount != 0 {
		t.Fatalf("expected first sync applied at revision=1 grants=0, got revision=%d grants=%d", a.appliedRevision, a.appliedGrantCount)
	}

	// Ramp up to a non-trivial grant count so the drop guard has a real
	// baseline to compare against.
	current = stateResp{revision: 2, grants: 10}
	if err := a.Sync(ctx); err != nil {
		t.Fatalf("sync to 10 grants returned error: %v", err)
	}
	if a.appliedGrantCount != 10 {
		t.Fatalf("expected 10 grants applied, got %d", a.appliedGrantCount)
	}

	// (a) same grant count (10 -> 10) under a new revision: not a drop at
	// all, must apply normally.
	current = stateResp{revision: 3, grants: 10}
	if err := a.Sync(ctx); err != nil {
		t.Fatalf("no-op-count sync returned error: %v", err)
	}
	if a.appliedRevision != 3 || a.appliedGrantCount != 10 {
		t.Fatalf("expected revision=3 grants=10 applied, got revision=%d grants=%d", a.appliedRevision, a.appliedGrantCount)
	}

	// (b) 10 -> 0 is a drastic drop (previous count above the floor, and a
	// 100%% drop past the ratio threshold): must be refused, keeping
	// revision 3 / 10 grants as the live, last-known-good state.
	current = stateResp{revision: 4, grants: 0}
	for i := 0; i < maxConsecutiveDropRefusals; i++ {
		if err := a.Sync(ctx); err != nil {
			t.Fatalf("refused sync #%d returned unexpected error: %v", i+1, err)
		}
		if a.appliedRevision != 3 || a.appliedGrantCount != 10 {
			t.Fatalf("expected refusal #%d to keep revision=3 grants=10, got revision=%d grants=%d", i+1, a.appliedRevision, a.appliedGrantCount)
		}
	}
	for _, rev := range acked {
		if rev == 4 {
			t.Fatal("revision 4 should not have been acked while the drop was being refused")
		}
	}

	// (d) after maxConsecutiveDropRefusals consecutive confirmations of the
	// same drop, Sync must stop refusing and accept the new, lower reality
	// rather than getting stuck refusing forever.
	if err := a.Sync(ctx); err != nil {
		t.Fatalf("final sync (accepting confirmed drop) returned error: %v", err)
	}
	if a.appliedRevision != 4 || a.appliedGrantCount != 0 {
		t.Fatalf("expected the drop to be accepted after %d confirmations: revision=%d grants=%d", maxConsecutiveDropRefusals, a.appliedRevision, a.appliedGrantCount)
	}
}
