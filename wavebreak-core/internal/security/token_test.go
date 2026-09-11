package security

import "testing"

func TestRandomTokenAndHash(t *testing.T) {
	token, err := RandomToken(32)
	if err != nil {
		t.Fatalf("RandomToken returned error: %v", err)
	}
	if len(token) < 32 {
		t.Fatalf("token too short: %d", len(token))
	}
	if TokenHash(token) != TokenHash(token) {
		t.Fatal("token hash must be stable")
	}
	other, err := RandomToken(32)
	if err != nil {
		t.Fatalf("RandomToken second returned error: %v", err)
	}
	if token == other {
		t.Fatal("tokens should be unique")
	}
	if TokenHash(token) == TokenHash(other) {
		t.Fatal("different tokens should not share a hash")
	}
}

func TestRandomTokenRejectsTinyTokens(t *testing.T) {
	if _, err := RandomToken(8); err == nil {
		t.Fatal("expected tiny token request to fail")
	}
}
