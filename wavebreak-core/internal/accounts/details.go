package accounts

import (
	"context"
	"errors"
	"sort"
	"time"
)

// UserDetails is the normalized admin view of one user
// (GET /v1/admin/users/{userID}).
type UserDetails struct {
	User         UserView          `json:"user"`
	Subscription *SubscriptionView `json:"subscription"`
	Access       AccessView        `json:"access"`
	Traffic      *TrafficSummary   `json:"traffic"`
	Devices      DevicesView       `json:"devices"`
	Connections  ConnectionsView   `json:"connections"`
}

type UserView struct {
	ID          string     `json:"id"`
	Email       string     `json:"email"`
	Username    string     `json:"username,omitempty"`
	Role        string     `json:"role"`
	Status      string     `json:"status"`
	CreatedAt   time.Time  `json:"created_at"`
	LastLoginAt *time.Time `json:"last_login_at"`
	DisabledAt  *time.Time `json:"disabled_at"`
}

type PlanView struct {
	ID                string `json:"id"`
	Code              string `json:"code"`
	Name              string `json:"name"`
	PriceMinor        int64  `json:"price_minor"`
	Currency          string `json:"currency"`
	Interval          string `json:"interval"`
	DurationDays      *int   `json:"duration_days"`
	TrafficLimitBytes *int64 `json:"traffic_limit_bytes"`
	DeviceLimit       int    `json:"device_limit"`
	IsActive          bool   `json:"is_active"`
}

type SubscriptionView struct {
	ID                string     `json:"id"`
	Status            string     `json:"status"`
	Source            string     `json:"source"`
	Plan              *PlanView  `json:"plan"`
	StartedAt         *time.Time `json:"started_at"`
	ExpiresAt         time.Time  `json:"expires_at"`
	TrafficLimitBytes *int64     `json:"traffic_limit_bytes"`
	DeviceLimit       int        `json:"device_limit"`
}

type GrantView struct {
	ID        string    `json:"id"`
	NodeID    string    `json:"node_id"`
	NodeCode  string    `json:"node_code,omitempty"`
	DeviceID  *string   `json:"device_id"`
	Protocol  string    `json:"protocol"`
	Status    string    `json:"status"`
	ExpiresAt time.Time `json:"expires_at"`
	CreatedAt time.Time `json:"created_at"`
}

// AccessView: CredentialID is the access grant id nodes authenticate with
// (VLESS UUID / Hysteria2 user); SubscriptionURL is built from it.
type AccessView struct {
	CredentialID    string      `json:"credential_id,omitempty"`
	SubscriptionURL string      `json:"subscription_url,omitempty"`
	ActiveGrants    int         `json:"active_grants"`
	Grants          []GrantView `json:"grants"`
}

type DeviceView struct {
	ID             string     `json:"id"`
	DevicePublicID string     `json:"device_public_id"`
	Name           string     `json:"name"`
	Platform       *string    `json:"platform"`
	SubscriptionID *string    `json:"subscription_id"`
	Status         string     `json:"status"`
	CreatedAt      time.Time  `json:"created_at"`
	LastSeenAt     *time.Time `json:"last_seen_at"`
	RevokedAt      *time.Time `json:"revoked_at"`
}

// DevicesView: Registered counts non-revoked devices; Limit comes from the
// live subscription (nil without one).
type DevicesView struct {
	Registered int          `json:"registered"`
	Limit      *int         `json:"limit"`
	Items      []DeviceView `json:"items"`
}

// ConnectionsView is reserved for node/runtime telemetry; Active stays nil
// until nodes report live connections.
type ConnectionsView struct {
	Active *int   `json:"active"`
	Source string `json:"source"`
}

// UserDetailsService composes the admin view from the repositories.
type UserDetailsService struct {
	users   UserRepository
	plans   PlanRepository
	subs    SubscriptionRepository
	devices DeviceRepository
	urls    SubscriptionURLBuilder
}

func NewUserDetailsService(users UserRepository, plans PlanRepository, subs SubscriptionRepository, devices DeviceRepository, urls SubscriptionURLBuilder) *UserDetailsService {
	return &UserDetailsService{users: users, plans: plans, subs: subs, devices: devices, urls: urls}
}

func (s *UserDetailsService) Get(ctx context.Context, userID string) (UserDetails, error) {
	user, err := s.users.UserByID(ctx, userID)
	if errors.Is(err, ErrNotFound) {
		return UserDetails{}, errUserNotFound()
	}
	if err != nil {
		return UserDetails{}, wrapInternal(CodeInternal, "Could not load user.", err)
	}
	details := UserDetails{
		User:        userView(user),
		Access:      AccessView{Grants: []GrantView{}},
		Connections: ConnectionsView{Source: "not_reported"},
	}

	sub, err := s.subs.LiveSubscription(ctx, userID)
	switch {
	case errors.Is(err, ErrNotFound):
		// No subscription: traffic is null, devices still listed.
	case err != nil:
		return UserDetails{}, wrapInternal(CodeInternal, "Could not load subscription.", err)
	default:
		if err := s.attachSubscription(ctx, &details, sub); err != nil {
			return UserDetails{}, err
		}
	}

	devices, err := s.devices.UserDevices(ctx, userID)
	if err != nil {
		return UserDetails{}, wrapInternal(CodeInternal, "Could not load devices.", err)
	}
	details.Devices = devicesView(devices, details.Subscription)
	return details, nil
}

func (s *UserDetailsService) attachSubscription(ctx context.Context, details *UserDetails, sub SubscriptionRecord) error {
	view := &SubscriptionView{
		ID:                sub.ID,
		Status:            sub.Status,
		Source:            sub.Source,
		StartedAt:         sub.StartedAt,
		ExpiresAt:         sub.CurrentPeriodEnd,
		TrafficLimitBytes: sub.TrafficLimitBytes,
		DeviceLimit:       sub.DeviceLimit,
	}
	if plan, err := s.plans.PlanByID(ctx, sub.PlanID); err == nil {
		p := planView(plan)
		view.Plan = &p
	} else if !errors.Is(err, ErrNotFound) {
		return wrapInternal(CodeInternal, "Could not load plan.", err)
	}
	details.Subscription = view

	grants, err := s.subs.Grants(ctx, sub.ID)
	if err != nil {
		return wrapInternal(CodeInternal, "Could not load access grants.", err)
	}
	details.Access = accessView(grants, sub.PrimaryGrantID, s.urls)

	usage, err := s.subs.Usage(ctx, sub.ID)
	if err != nil {
		return wrapInternal(CodeInternal, "Could not load traffic.", err)
	}
	traffic := NewTrafficSummary(usage, sub.TrafficLimitBytes)
	details.Traffic = &traffic
	return nil
}

func userView(u UserRecord) UserView {
	return UserView{ID: u.ID, Email: u.Email, Username: u.Username, Role: u.Role, Status: u.Status, CreatedAt: u.CreatedAt, LastLoginAt: u.LastLoginAt, DisabledAt: u.DisabledAt}
}

func planView(p PlanRecord) PlanView {
	return PlanView{ID: p.ID, Code: p.Code, Name: p.Name, PriceMinor: p.PriceMinor, Currency: p.Currency, Interval: p.Interval, DurationDays: p.DurationDays, TrafficLimitBytes: p.TrafficLimitBytes, DeviceLimit: p.DeviceLimit, IsActive: p.IsActive}
}

// accessView picks the subscription credential: the stored primary grant,
// else the newest active grant (legacy subscriptions issued before
// primary_grant_id existed). Reading never mutates state.
func accessView(grants []GrantRecord, primary *string, urls SubscriptionURLBuilder) AccessView {
	view := AccessView{Grants: make([]GrantView, 0, len(grants))}
	sort.SliceStable(grants, func(i, j int) bool { return grants[i].CreatedAt.After(grants[j].CreatedAt) })
	for _, g := range grants {
		view.Grants = append(view.Grants, GrantView{ID: g.ID, NodeID: g.NodeID, NodeCode: g.NodeCode, DeviceID: g.DeviceID, Protocol: g.Protocol, Status: g.Status, ExpiresAt: g.ExpiresAt, CreatedAt: g.CreatedAt})
		if g.Status == "active" {
			view.ActiveGrants++
		}
	}
	credential := currentCredential(grants, primary)
	view.CredentialID = credential
	view.SubscriptionURL = urls.Build(credential)
	return view
}

// currentCredential is the primary grant if it is still active, else the
// newest active grant, else "". grants must be sorted newest first.
func currentCredential(grants []GrantRecord, primary *string) string {
	if primary != nil {
		for _, g := range grants {
			if g.ID == *primary && g.Status == "active" {
				return g.ID
			}
		}
	}
	for _, g := range grants {
		if g.Status == "active" {
			return g.ID
		}
	}
	return ""
}

func devicesView(devices []DeviceRecord, sub *SubscriptionView) DevicesView {
	view := DevicesView{Items: make([]DeviceView, 0, len(devices))}
	for _, d := range devices {
		status := "active"
		if d.RevokedAt != nil {
			status = "revoked"
		} else {
			view.Registered++
		}
		view.Items = append(view.Items, DeviceView{ID: d.ID, DevicePublicID: d.DevicePublicID, Name: d.Name, Platform: d.Platform, SubscriptionID: d.SubscriptionID, Status: status, CreatedAt: d.CreatedAt, LastSeenAt: d.LastSeenAt, RevokedAt: d.RevokedAt})
	}
	if sub != nil {
		limit := sub.DeviceLimit
		view.Limit = &limit
	}
	return view
}
