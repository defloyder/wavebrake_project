package accounts

import (
	"strings"
)

// SubscriptionURLBuilder is the single place subscription URLs are formed:
// <base><credential>, where the credential is the subscription's primary
// access grant id (what nodes authenticate). The base comes from config
// (WAVEBREAK_SUBSCRIPTION_URL_BASE) and defaults to the public Core route
// GET /v1/sub/{grantID}.
type SubscriptionURLBuilder struct {
	base string
}

const DefaultSubscriptionURLBase = "https://api.wavebreak.com.tr/v1/sub/"

func NewSubscriptionURLBuilder(base string) SubscriptionURLBuilder {
	base = strings.TrimSpace(base)
	if base == "" {
		base = DefaultSubscriptionURLBase
	}
	if !strings.HasSuffix(base, "/") {
		base += "/"
	}
	return SubscriptionURLBuilder{base: base}
}

func (b SubscriptionURLBuilder) Build(credentialID string) string {
	if credentialID == "" {
		return ""
	}
	return b.base + credentialID
}

// TrafficSummary is the aggregated usage of one subscription. For an
// unlimited plan LimitBytes, RemainingBytes and UsedPercent are nil.
type TrafficSummary struct {
	BytesUp        int64    `json:"bytes_up"`
	BytesDown      int64    `json:"bytes_down"`
	BytesTotal     int64    `json:"bytes_total"`
	LimitBytes     *int64   `json:"limit_bytes"`
	RemainingBytes *int64   `json:"remaining_bytes"`
	UsedPercent    *float64 `json:"used_percent"`
}

func NewTrafficSummary(usage UsageTotals, limit *int64) TrafficSummary {
	total := usage.BytesUp + usage.BytesDown
	summary := TrafficSummary{BytesUp: usage.BytesUp, BytesDown: usage.BytesDown, BytesTotal: total}
	if limit == nil || *limit <= 0 {
		return summary
	}
	l := *limit
	remaining := l - total
	if remaining < 0 {
		remaining = 0
	}
	// One decimal place; capped at 100 even when usage overshoots.
	pct := float64(total) * 100 / float64(l)
	if pct > 100 {
		pct = 100
	}
	pct = float64(int64(pct*10+0.5)) / 10
	summary.LimitBytes = &l
	summary.RemainingBytes = &remaining
	summary.UsedPercent = &pct
	return summary
}
