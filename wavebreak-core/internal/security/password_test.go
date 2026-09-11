package security

import (
	"strings"
	"testing"

	"golang.org/x/crypto/bcrypt"
)

func TestHashPasswordUsesArgon2idAndVerifies(t *testing.T) {
	hash, err := HashPassword("correct horse battery staple")
	if err != nil {
		t.Fatalf("HashPassword returned error: %v", err)
	}
	if !strings.HasPrefix(hash, "$argon2id$v=19$") {
		t.Fatalf("expected argon2id hash, got %q", hash)
	}
	ok, err := VerifyPassword("correct horse battery staple", hash)
	if err != nil {
		t.Fatalf("VerifyPassword returned error: %v", err)
	}
	if !ok {
		t.Fatal("expected password to verify")
	}
	ok, err = VerifyPassword("wrong password", hash)
	if err != nil {
		t.Fatalf("VerifyPassword wrong password returned error: %v", err)
	}
	if ok {
		t.Fatal("expected wrong password to fail")
	}
}

func TestVerifyPasswordSupportsLegacyBcrypt(t *testing.T) {
	hash, err := bcrypt.GenerateFromPassword([]byte("legacy-password"), bcrypt.MinCost)
	if err != nil {
		t.Fatalf("bcrypt hash: %v", err)
	}
	ok, err := VerifyPassword("legacy-password", string(hash))
	if err != nil {
		t.Fatalf("VerifyPassword returned error: %v", err)
	}
	if !ok {
		t.Fatal("expected legacy bcrypt password to verify")
	}
}

func TestVerifyPasswordRejectsMalformedHash(t *testing.T) {
	ok, err := VerifyPassword("password", "not-a-real-hash")
	if err == nil {
		t.Fatal("expected malformed hash error")
	}
	if ok {
		t.Fatal("malformed hash must not verify")
	}
}
