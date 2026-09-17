package httpapi

import "testing"

func TestSmartRoutingPolicyDefaultsToProtected(t *testing.T) {
	policy := smartRoutingPolicy()
	if policy["default_action"] != "protected" || policy["fallback_action"] != "protected" {
		t.Fatalf("routing policy must fail back to the protected route: %#v", policy)
	}

	direct, ok := policy["direct"].(map[string]any)
	if !ok {
		t.Fatalf("direct routing rules are missing: %#v", policy)
	}
	if direct["private_networks"] != true {
		t.Fatalf("private networks must remain directly reachable: %#v", direct)
	}
}
