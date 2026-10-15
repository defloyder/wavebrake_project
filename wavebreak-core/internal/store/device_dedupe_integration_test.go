package store

import (
	"context"
	"errors"
	"testing"
)

func TestCreateDeviceReusesSameNameAndPlatform(t *testing.T) {
	st, _, _ := openPIITestStores(t)
	ctx := context.Background()

	user, err := st.CreateUserWithRole(ctx, "devices@example.com", "hash", "user")
	if err != nil {
		t.Fatalf("create user: %v", err)
	}
	first, err := st.CreateDevice(ctx, user.ID, "Pixel 8", "android")
	if err != nil {
		t.Fatalf("first device: %v", err)
	}
	again, err := st.CreateDevice(ctx, user.ID, "Pixel 8", "android")
	if err != nil {
		t.Fatalf("same device after sign-out must not hit the limit: %v", err)
	}
	if again.ID != first.ID {
		t.Fatalf("same name and platform created a new row: %s vs %s", again.ID, first.ID)
	}
	if _, err := st.CreateDevice(ctx, user.ID, "Pixel 8", "ios"); !errors.Is(err, ErrLimitReached) {
		t.Fatalf("different platform should take a new slot and hit the limit, got %v", err)
	}
}
