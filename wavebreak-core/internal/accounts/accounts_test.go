package accounts

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"
)

// memoryRepo is an in-memory implementation of every port, so the use
// cases are tested without a database.
type memoryRepo struct {
	users     map[string]UserRecord
	plans     map[string]PlanRecord
	subs      []SubscriptionRecord
	grants    map[string][]GrantRecord // by subscription
	usage     map[string]UsageTotals
	devices   map[string][]DeviceRecord
	nodeID    string
	tokens    map[string]*resetToken // by hash
	audit     []AuditEntry
	createErr error
	seq       int
}

type resetToken struct {
	userID    string
	expiresAt time.Time
	usedAt    *time.Time
}

func newMemoryRepo() *memoryRepo {
	return &memoryRepo{
		users:   map[string]UserRecord{},
		plans:   map[string]PlanRecord{},
		grants:  map[string][]GrantRecord{},
		usage:   map[string]UsageTotals{},
		devices: map[string][]DeviceRecord{},
		tokens:  map[string]*resetToken{},
		nodeID:  "node-1",
	}
}

func (m *memoryRepo) id(prefix string) string {
	m.seq++
	return prefix + "-" + string(rune('a'+m.seq))
}

func (m *memoryRepo) UserByID(_ context.Context, id string) (UserRecord, error) {
	u, ok := m.users[id]
	if !ok {
		return UserRecord{}, ErrNotFound
	}
	return u, nil
}

func (m *memoryRepo) PlanByID(_ context.Context, id string) (PlanRecord, error) {
	p, ok := m.plans[id]
	if !ok {
		return PlanRecord{}, ErrNotFound
	}
	return p, nil
}

func isLive(status string) bool {
	switch status {
	case "pending", "trialing", "active", "past_due", "suspended":
		return true
	}
	return false
}

func (m *memoryRepo) LiveSubscription(_ context.Context, userID string) (SubscriptionRecord, error) {
	for i := len(m.subs) - 1; i >= 0; i-- {
		if m.subs[i].UserID == userID && isLive(m.subs[i].Status) {
			return m.subs[i], nil
		}
	}
	return SubscriptionRecord{}, ErrNotFound
}

func (m *memoryRepo) Create(ctx context.Context, userID, planID, source, createdBy string) (SubscriptionRecord, error) {
	if m.createErr != nil {
		return SubscriptionRecord{}, m.createErr
	}
	if _, err := m.LiveSubscription(ctx, userID); err == nil {
		return SubscriptionRecord{}, ErrLiveSubscriptionExists
	}
	p := m.plans[planID]
	now := time.Now().UTC()
	sub := SubscriptionRecord{ID: m.id("sub"), UserID: userID, PlanID: planID, Status: "active", Source: source,
		StartedAt: &now, CurrentPeriodEnd: now.Add(30 * 24 * time.Hour), TrafficLimitBytes: p.TrafficLimitBytes,
		DeviceLimit: p.DeviceLimit, CreatedAt: now}
	m.subs = append(m.subs, sub)
	return sub, nil
}

func (m *memoryRepo) SetPrimaryGrant(_ context.Context, subID, grantID string) error {
	for i := range m.subs {
		if m.subs[i].ID == subID {
			g := grantID
			m.subs[i].PrimaryGrantID = &g
		}
	}
	return nil
}

func (m *memoryRepo) Grants(_ context.Context, subID string) ([]GrantRecord, error) {
	return append([]GrantRecord(nil), m.grants[subID]...), nil
}

func (m *memoryRepo) Usage(_ context.Context, subID string) (UsageTotals, error) {
	return m.usage[subID], nil
}

func (m *memoryRepo) DefaultNodeID(context.Context) (string, error) {
	if m.nodeID == "" {
		return "", ErrNotFound
	}
	return m.nodeID, nil
}

func (m *memoryRepo) CreateSubscriptionGrant(ctx context.Context, userID, nodeID, protocol string, expiresAt time.Time) (GrantRecord, error) {
	sub, err := m.LiveSubscription(ctx, userID)
	if err != nil {
		return GrantRecord{}, err
	}
	g := GrantRecord{ID: m.id("grant"), NodeID: nodeID, NodeCode: "TR-PILOT-01", Protocol: protocol, Status: "active", ExpiresAt: expiresAt, CreatedAt: time.Now()}
	m.grants[sub.ID] = append(m.grants[sub.ID], g)
	return g, nil
}

func (m *memoryRepo) UserDevices(_ context.Context, userID string) ([]DeviceRecord, error) {
	return m.devices[userID], nil
}

func (m *memoryRepo) CreateResetToken(_ context.Context, userID, hash, _, _ string, expiresAt time.Time) error {
	m.tokens[hash] = &resetToken{userID: userID, expiresAt: expiresAt}
	return nil
}

func (m *memoryRepo) ConsumeResetToken(_ context.Context, hash, _, _ string, now time.Time) (string, error) {
	t, ok := m.tokens[hash]
	if !ok || t.usedAt != nil || !now.Before(t.expiresAt) {
		return "", ErrNotFound
	}
	t.usedAt = &now
	return t.userID, nil
}

func (m *memoryRepo) Record(_ context.Context, e AuditEntry) error {
	m.audit = append(m.audit, e)
	return nil
}

type fakeTokens struct{ n int }

func (f *fakeTokens) New() (string, string, error) {
	f.n++
	token := "tok" + string(rune('0'+f.n))
	return token, "h:" + token, nil
}
func (f *fakeTokens) Hash(token string) string { return "h:" + token }

type recordingNotifier struct{ urls []string }

func (r *recordingNotifier) SendPasswordReset(_ context.Context, _, url string, _ time.Time) (string, error) {
	r.urls = append(r.urls, url)
	return "not_configured", nil
}

type plainHasher struct{}

func (plainHasher) Hash(p string) (string, string, error) { return "hashed:" + p, "test", nil }

func int64p(v int64) *int64 { return &v }

type fixture struct {
	repo     *memoryRepo
	details  *UserDetailsService
	assign   *SubscriptionAssignmentService
	reset    *PasswordResetService
	notifier *recordingNotifier
	actor    Actor
}

func newFixture() fixture {
	repo := newMemoryRepo()
	repo.users["u1"] = UserRecord{ID: "u1", Email: "user@example.com", Role: "user", Status: "active"}
	repo.users["u-noemail"] = UserRecord{ID: "u-noemail", Role: "user", Status: "active"}
	repo.plans["p-starter"] = PlanRecord{ID: "p-starter", Code: "starter-monthly", Name: "Starter", PriceMinor: 900, Currency: "USD", Interval: "month", TrafficLimitBytes: int64p(100 << 30), DeviceLimit: 3, IsActive: true}
	repo.plans["p-old"] = PlanRecord{ID: "p-old", Code: "old", Name: "Old", IsActive: false}
	urls := NewSubscriptionURLBuilder("https://api.example.test/v1/sub/")
	details := NewUserDetailsService(repo, repo, repo, repo, urls)
	notifier := &recordingNotifier{}
	return fixture{
		repo:     repo,
		details:  details,
		assign:   NewSubscriptionAssignmentService(repo, repo, repo, repo, repo, details, "vless"),
		reset:    NewPasswordResetService(repo, repo, &fakeTokens{}, notifier, plainHasher{}, repo, "https://site.test/reset", time.Hour),
		notifier: notifier,
		actor:    Actor{UserID: "admin-1", Role: "admin", RequestID: "req-1"},
	}
}

func codeOf(err error) string {
	var de *DomainError
	if errors.As(err, &de) {
		return de.Code
	}
	return ""
}

func TestUserDetailsWithoutSubscription(t *testing.T) {
	f := newFixture()
	d, err := f.details.Get(context.Background(), "u1")
	if err != nil {
		t.Fatal(err)
	}
	if d.User.ID != "u1" || d.Subscription != nil || d.Traffic != nil {
		t.Fatalf("unexpected details: %+v", d)
	}
	if d.Access.SubscriptionURL != "" || d.Devices.Limit != nil || d.Devices.Registered != 0 {
		t.Fatalf("no subscription must mean no URL/limit: %+v", d)
	}
}

func TestUserDetailsUnknownUser(t *testing.T) {
	f := newFixture()
	if _, err := f.details.Get(context.Background(), "nope"); codeOf(err) != CodeUserNotFound {
		t.Fatalf("want USER_NOT_FOUND, got %v", err)
	}
}

func TestIssueSubscriptionCreatesSubscriptionGrantURLAndAudit(t *testing.T) {
	f := newFixture()
	d, err := f.assign.Issue(context.Background(), f.actor, "u1", "p-starter")
	if err != nil {
		t.Fatal(err)
	}
	if d.Subscription == nil || d.Subscription.Status != "active" || d.Subscription.Plan == nil || d.Subscription.Plan.Code != "starter-monthly" {
		t.Fatalf("subscription not active with plan: %+v", d.Subscription)
	}
	if d.Access.CredentialID == "" || d.Access.ActiveGrants != 1 {
		t.Fatalf("credential not issued: %+v", d.Access)
	}
	if want := "https://api.example.test/v1/sub/" + d.Access.CredentialID; d.Access.SubscriptionURL != want {
		t.Fatalf("subscription URL = %q, want %q", d.Access.SubscriptionURL, want)
	}
	if d.Traffic == nil || d.Traffic.BytesTotal != 0 || *d.Traffic.LimitBytes != 100<<30 || *d.Traffic.UsedPercent != 0 {
		t.Fatalf("traffic should be 0 / plan limit: %+v", d.Traffic)
	}
	if d.Devices.Limit == nil || *d.Devices.Limit != 3 {
		t.Fatalf("device limit should come from the plan: %+v", d.Devices)
	}
	if len(f.repo.audit) != 2 || f.repo.audit[0].Action != AuditSubscriptionIssued || f.repo.audit[1].Action != AuditAccessCreated {
		t.Fatalf("audit = %+v", f.repo.audit)
	}
	for _, e := range f.repo.audit {
		if e.TargetUserID != "u1" || e.Actor.UserID != "admin-1" || e.Actor.RequestID != "req-1" {
			t.Fatalf("audit entry missing actor/target/request: %+v", e)
		}
		for _, v := range e.Metadata {
			if s, ok := v.(string); ok && strings.Contains(s, "/v1/sub/") {
				t.Fatal("subscription URL must not be in audit metadata")
			}
		}
	}
}

func TestIssueSubscriptionIsStableCredential(t *testing.T) {
	f := newFixture()
	first, _ := f.assign.Issue(context.Background(), f.actor, "u1", "p-starter")
	// A device grant created later must not change the subscription URL.
	sub, _ := f.repo.LiveSubscription(context.Background(), "u1")
	f.repo.grants[sub.ID] = append(f.repo.grants[sub.ID], GrantRecord{ID: "grant-device", Status: "active", CreatedAt: time.Now().Add(time.Hour)})
	again, _ := f.details.Get(context.Background(), "u1")
	if again.Access.SubscriptionURL != first.Access.SubscriptionURL {
		t.Fatalf("URL changed: %q -> %q", first.Access.SubscriptionURL, again.Access.SubscriptionURL)
	}
}

func TestIssueSubscriptionRejectsDuplicateActive(t *testing.T) {
	f := newFixture()
	if _, err := f.assign.Issue(context.Background(), f.actor, "u1", "p-starter"); err != nil {
		t.Fatal(err)
	}
	if _, err := f.assign.Issue(context.Background(), f.actor, "u1", "p-starter"); codeOf(err) != CodeSubscriptionAlreadyActive {
		t.Fatalf("want SUBSCRIPTION_ALREADY_ACTIVE, got %v", err)
	}
	// Race: the repository's unique index fires even if the pre-check passed.
	f.repo.subs = nil
	f.repo.createErr = ErrLiveSubscriptionExists
	if _, err := f.assign.Issue(context.Background(), f.actor, "u1", "p-starter"); codeOf(err) != CodeSubscriptionAlreadyActive {
		t.Fatalf("race: want SUBSCRIPTION_ALREADY_ACTIVE, got %v", err)
	}
}

func TestIssueSubscriptionValidatesUserPlanAndNode(t *testing.T) {
	f := newFixture()
	cases := map[string]struct {
		user, plan string
		setup      func()
	}{
		CodeUserNotFound:    {"ghost", "p-starter", nil},
		CodePlanNotFound:    {"u1", "ghost", nil},
		CodePlanInactive:    {"u1", "p-old", nil},
		CodeNoNodeAvailable: {"u1", "p-starter", func() { f.repo.nodeID = "" }},
	}
	for want, c := range cases {
		if c.setup != nil {
			c.setup()
		}
		if _, err := f.assign.Issue(context.Background(), f.actor, c.user, c.plan); codeOf(err) != want {
			t.Fatalf("want %s, got %v", want, err)
		}
	}
}

func TestTrafficSummary(t *testing.T) {
	s := NewTrafficSummary(UsageTotals{BytesUp: 1 << 30, BytesDown: 3 << 30}, int64p(10<<30))
	if s.BytesTotal != 4<<30 || *s.RemainingBytes != 6<<30 || *s.UsedPercent != 40 {
		t.Fatalf("summary = %+v", s)
	}
	unlimited := NewTrafficSummary(UsageTotals{BytesDown: 5}, nil)
	if unlimited.LimitBytes != nil || unlimited.RemainingBytes != nil || unlimited.UsedPercent != nil {
		t.Fatalf("unlimited must have nil limit fields: %+v", unlimited)
	}
	over := NewTrafficSummary(UsageTotals{BytesDown: 20}, int64p(10))
	if *over.RemainingBytes != 0 || *over.UsedPercent != 100 {
		t.Fatalf("overuse must clamp: %+v", over)
	}
}

func TestUserDetailsTrafficAndDevices(t *testing.T) {
	f := newFixture()
	d, _ := f.assign.Issue(context.Background(), f.actor, "u1", "p-starter")
	f.repo.usage[d.Subscription.ID] = UsageTotals{BytesUp: 1 << 30, BytesDown: 9 << 30}
	now := time.Now()
	f.repo.devices["u1"] = []DeviceRecord{
		{ID: "d1", Name: "Phone", CreatedAt: now},
		{ID: "d2", Name: "PC", CreatedAt: now},
		{ID: "d3", Name: "Old", CreatedAt: now, RevokedAt: &now},
	}
	got, err := f.details.Get(context.Background(), "u1")
	if err != nil {
		t.Fatal(err)
	}
	if got.Traffic.BytesTotal != 10<<30 || *got.Traffic.UsedPercent != 10 {
		t.Fatalf("traffic = %+v", got.Traffic)
	}
	if got.Devices.Registered != 2 || len(got.Devices.Items) != 3 || got.Devices.Items[2].Status != "revoked" {
		t.Fatalf("devices = %+v", got.Devices)
	}
}

func TestSubscriptionURLBuilder(t *testing.T) {
	b := NewSubscriptionURLBuilder("")
	if got := b.Build("g1"); got != DefaultSubscriptionURLBase+"g1" {
		t.Fatalf("default base: %q", got)
	}
	if got := NewSubscriptionURLBuilder("https://sub.test/x").Build("g1"); got != "https://sub.test/x/g1" {
		t.Fatalf("trailing slash: %q", got)
	}
	if b.Build("") != "" {
		t.Fatal("no credential, no URL")
	}
}

func TestPasswordResetRequestStoresOnlyHashAndAudits(t *testing.T) {
	f := newFixture()
	res, err := f.reset.Request(context.Background(), f.actor, "u1")
	if err != nil {
		t.Fatal(err)
	}
	if res.Status != "reset_link_created" || res.Delivery != "not_configured" || res.Channel != "email" {
		t.Fatalf("result = %+v", res)
	}
	if len(f.repo.tokens) != 1 {
		t.Fatalf("tokens = %d", len(f.repo.tokens))
	}
	for hash := range f.repo.tokens {
		if !strings.HasPrefix(hash, "h:") {
			t.Fatal("repository must receive the hash, not the token")
		}
	}
	if len(f.notifier.urls) != 1 || !strings.HasPrefix(f.notifier.urls[0], "https://site.test/reset?token=") {
		t.Fatalf("notifier url = %v", f.notifier.urls)
	}
	last := f.repo.audit[len(f.repo.audit)-1]
	if last.Action != AuditPasswordResetRequested {
		t.Fatalf("audit = %+v", last)
	}
	for _, v := range last.Metadata {
		if s, ok := v.(string); ok && strings.Contains(s, "tok") {
			t.Fatal("token leaked into audit")
		}
	}
}

func TestPasswordResetWithoutEmail(t *testing.T) {
	f := newFixture()
	if _, err := f.reset.Request(context.Background(), f.actor, "u-noemail"); codeOf(err) != CodePasswordResetChannelUnavailable {
		t.Fatalf("want PASSWORD_RESET_CHANNEL_UNAVAILABLE, got %v", err)
	}
}

func TestPasswordResetTokenIsOneTimeAndExpires(t *testing.T) {
	f := newFixture()
	if _, err := f.reset.Request(context.Background(), f.actor, "u1"); err != nil {
		t.Fatal(err)
	}
	token := strings.TrimPrefix(f.notifier.urls[0], "https://site.test/reset?token=")
	if err := f.reset.Confirm(context.Background(), token, "short"); codeOf(err) != CodeWeakPassword {
		t.Fatalf("want WEAK_PASSWORD, got %v", err)
	}
	if err := f.reset.Confirm(context.Background(), token, "a-strong-password"); err != nil {
		t.Fatalf("first use: %v", err)
	}
	if err := f.reset.Confirm(context.Background(), token, "a-strong-password"); codeOf(err) != CodePasswordResetTokenInvalid {
		t.Fatalf("second use must fail, got %v", err)
	}

	if _, err := f.reset.Request(context.Background(), f.actor, "u1"); err != nil {
		t.Fatal(err)
	}
	expired := strings.TrimPrefix(f.notifier.urls[1], "https://site.test/reset?token=")
	f.reset.now = func() time.Time { return time.Now().Add(2 * time.Hour) }
	if err := f.reset.Confirm(context.Background(), expired, "a-strong-password"); codeOf(err) != CodePasswordResetTokenInvalid {
		t.Fatalf("expired token must fail, got %v", err)
	}
}
