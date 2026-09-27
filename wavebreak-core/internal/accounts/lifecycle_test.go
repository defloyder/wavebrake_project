package accounts

import (
	"context"
	"errors"
	"testing"
	"time"
)

type fakeLifecycleRepo struct {
	status    map[string]string    // subscription id -> status
	periodEnd map[string]time.Time // subscription id -> period end
	exhausted map[string]bool      // traffic reached the limit
	failEnter string
	resets    []string
}

func (f *fakeLifecycleRepo) DueForGrace(_ context.Context, now time.Time) ([]LifecycleCandidate, error) {
	var out []LifecycleCandidate
	for id, st := range f.status {
		if st != "active" {
			continue
		}
		if !f.periodEnd[id].After(now) {
			out = append(out, LifecycleCandidate{SubscriptionID: id, UserID: "u-" + id, Reason: LifecycleReasonPeriodEnded})
		} else if f.exhausted[id] {
			out = append(out, LifecycleCandidate{SubscriptionID: id, UserID: "u-" + id, Reason: LifecycleReasonTrafficExhausted})
		}
	}
	return out, nil
}

func (f *fakeLifecycleRepo) EnterGrace(_ context.Context, id string, now time.Time) error {
	if id == f.failEnter {
		return errors.New("db down")
	}
	if f.status[id] != "active" {
		return ErrNotFound
	}
	f.status[id] = "past_due"
	if f.periodEnd[id].After(now) {
		f.periodEnd[id] = now
	}
	return nil
}

func (f *fakeLifecycleRepo) DueForExpiry(_ context.Context, cutoff time.Time) ([]LifecycleCandidate, error) {
	var out []LifecycleCandidate
	for id, st := range f.status {
		if st == "past_due" && !f.periodEnd[id].After(cutoff) {
			out = append(out, LifecycleCandidate{SubscriptionID: id, UserID: "u-" + id})
		}
	}
	return out, nil
}

func (f *fakeLifecycleRepo) ExpireAndReset(_ context.Context, id string) (ResetOutcome, error) {
	if f.status[id] != "past_due" {
		return ResetOutcome{}, ErrNotFound
	}
	f.status[id] = "expired"
	f.resets = append(f.resets, id)
	return ResetOutcome{RevokedGrants: 1, RevokedDevices: 2, KeptDeviceID: "d-last"}, nil
}

func newLifecycleFixture(now time.Time) (*fakeLifecycleRepo, *memoryRepo, *SubscriptionLifecycleService) {
	repo := &fakeLifecycleRepo{status: map[string]string{}, periodEnd: map[string]time.Time{}, exhausted: map[string]bool{}}
	audit := newMemoryRepo()
	svc := NewSubscriptionLifecycleService(repo, audit, 0)
	svc.now = func() time.Time { return now }
	return repo, audit, svc
}

func TestLifecyclePeriodEndStartsGraceThenResets(t *testing.T) {
	now := time.Date(2026, 10, 1, 12, 0, 0, 0, time.UTC)
	repo, audit, svc := newLifecycleFixture(now)
	repo.status["s1"] = "active"
	repo.periodEnd["s1"] = now.Add(-time.Hour)
	repo.status["s-ok"] = "active"
	repo.periodEnd["s-ok"] = now.Add(24 * time.Hour)

	report, err := svc.Run(context.Background())
	if err != nil || report.PastDue != 1 || report.Expired != 0 {
		t.Fatalf("first run: %+v %v", report, err)
	}
	if repo.status["s1"] != "past_due" || repo.status["s-ok"] != "active" {
		t.Fatalf("statuses: %v", repo.status)
	}
	if len(audit.audit) != 1 || audit.audit[0].Action != AuditSubscriptionPastDue || audit.audit[0].Metadata["reason"] != LifecycleReasonPeriodEnded || audit.audit[0].TargetUserID != "u-s1" {
		t.Fatalf("audit: %+v", audit.audit)
	}

	// Six days later: still in grace.
	svc.now = func() time.Time { return now.Add(6 * 24 * time.Hour) }
	if report, _ := svc.Run(context.Background()); report.Expired != 0 || repo.status["s1"] != "past_due" {
		t.Fatalf("expired too early: %+v %v", report, repo.status)
	}

	// Seven days after the period ended: reset.
	svc.now = func() time.Time { return now.Add(7*24*time.Hour - time.Hour) }
	report, err = svc.Run(context.Background())
	if err != nil || report.Expired != 1 || repo.status["s1"] != "expired" || len(repo.resets) != 1 {
		t.Fatalf("reset run: %+v %v %v", report, err, repo.status)
	}
	last := audit.audit[len(audit.audit)-1]
	if last.Action != AuditSubscriptionExpired || last.Metadata["revoked_devices"] != 2 || last.Metadata["kept_device_id"] != "d-last" {
		t.Fatalf("expiry audit: %+v", last)
	}
}

func TestLifecycleTrafficExhaustedEndsPeriodNow(t *testing.T) {
	now := time.Date(2026, 10, 1, 12, 0, 0, 0, time.UTC)
	repo, audit, svc := newLifecycleFixture(now)
	repo.status["s1"] = "active"
	repo.periodEnd["s1"] = now.Add(20 * 24 * time.Hour)
	repo.exhausted["s1"] = true

	if report, err := svc.Run(context.Background()); err != nil || report.PastDue != 1 {
		t.Fatalf("run: %+v %v", report, err)
	}
	if repo.status["s1"] != "past_due" || !repo.periodEnd["s1"].Equal(now) {
		t.Fatalf("grace must start now: %v %v", repo.status["s1"], repo.periodEnd["s1"])
	}
	if audit.audit[0].Metadata["reason"] != LifecycleReasonTrafficExhausted {
		t.Fatalf("reason: %+v", audit.audit[0])
	}
	if got := svc.GraceEndsAt(repo.periodEnd["s1"]); !got.Equal(now.Add(7 * 24 * time.Hour)) {
		t.Fatalf("grace ends at %v", got)
	}
}

func TestLifecycleLongDowntimeGoesStraightToReset(t *testing.T) {
	now := time.Date(2026, 10, 1, 12, 0, 0, 0, time.UTC)
	repo, _, svc := newLifecycleFixture(now)
	repo.status["s1"] = "active"
	repo.periodEnd["s1"] = now.Add(-10 * 24 * time.Hour)

	report, err := svc.Run(context.Background())
	if err != nil || report.PastDue != 1 || report.Expired != 1 || repo.status["s1"] != "expired" {
		t.Fatalf("run: %+v %v %v", report, err, repo.status)
	}
}

func TestLifecycleOneFailureDoesNotStopOthers(t *testing.T) {
	now := time.Date(2026, 10, 1, 12, 0, 0, 0, time.UTC)
	repo, _, svc := newLifecycleFixture(now)
	for _, id := range []string{"s1", "s2"} {
		repo.status[id] = "active"
		repo.periodEnd[id] = now.Add(-time.Minute)
	}
	repo.failEnter = "s1"

	report, err := svc.Run(context.Background())
	if err == nil || report.PastDue != 1 || repo.status["s2"] != "past_due" {
		t.Fatalf("run: %+v %v %v", report, err, repo.status)
	}
}
