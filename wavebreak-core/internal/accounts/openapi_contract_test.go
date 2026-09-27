package accounts

import (
	"encoding/json"
	"os"
	"sort"
	"strings"
	"testing"
	"time"
)

// Every JSON field the account-management endpoints actually emit must be
// documented in api/openapi.yaml (under the schemas those endpoints
// reference), so the contract can't silently drift from the responses.
func TestOpenAPIDocumentsAccountResponses(t *testing.T) {
	raw, err := os.ReadFile("../../api/openapi.yaml")
	if err != nil {
		t.Fatal(err)
	}
	spec := string(raw)
	start := strings.Index(spec, "    DomainError:")
	end := strings.Index(spec, "    RegisterRequest:")
	if start < 0 || end < start {
		t.Fatal("account schemas block not found in openapi.yaml")
	}
	schemas := spec[start:end]

	limit, pct, n := int64(1), 1.0, 1
	s, now := "x", time.Now()
	samples := []any{
		UserDetails{
			Subscription: &SubscriptionView{Plan: &PlanView{DurationDays: &n, TrafficLimitBytes: &limit}, StartedAt: &now, TrafficLimitBytes: &limit},
			Access:       AccessView{Grants: []GrantView{{DeviceID: &s}}},
			Traffic:      &TrafficSummary{LimitBytes: &limit, RemainingBytes: &limit, UsedPercent: &pct},
			Devices:      DevicesView{Limit: &n, Items: []DeviceView{{Platform: &s, SubscriptionID: &s, LastSeenAt: &now, RevokedAt: &now}}},
			Connections:  ConnectionsView{Active: &n},
			User:         UserView{Username: "u", LastLoginAt: &now, DisabledAt: &now},
		},
		ResetResult{},
	}
	keys := map[string]bool{}
	for _, sample := range samples {
		body, _ := json.Marshal(sample)
		var v any
		_ = json.Unmarshal(body, &v)
		collectKeys(v, keys)
	}
	var missing []string
	for k := range keys {
		if !strings.Contains(schemas, " "+k+":") {
			missing = append(missing, k)
		}
	}
	sort.Strings(missing)
	if len(missing) > 0 {
		t.Fatalf("openapi.yaml does not document response fields: %v", missing)
	}
	for _, path := range []string{"/v1/admin/users/{userID}/subscriptions:", "/v1/admin/users/{userID}/password-reset:", "/v1/admin/users/{userID}/devices:", "/v1/auth/password-reset/confirm:"} {
		if !strings.Contains(spec, "  "+path) {
			t.Fatalf("openapi.yaml missing path %s", path)
		}
	}
}

func collectKeys(v any, keys map[string]bool) {
	switch t := v.(type) {
	case map[string]any:
		for k, child := range t {
			keys[k] = true
			collectKeys(child, keys)
		}
	case []any:
		for _, child := range t {
			collectKeys(child, keys)
		}
	}
}
