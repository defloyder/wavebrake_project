package agent

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"math/rand/v2"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"wavebreak-node/internal/config"
	wbruntime "wavebreak-node/internal/runtime"
)

type Agent struct {
	cfg              config.Config
	log              *slog.Logger
	client           *http.Client
	adapter          wbruntime.RuntimeAdapter
	usageReporter    wbruntime.UsageReporter
	incrementalApply wbruntime.IncrementalApplier
	nodeID           string
	nodeToken        string
	appliedRevision  int
	// appliedState is the raw desired-state payload last successfully
	// applied, kept only in memory. A restart of this process loses it,
	// which is fine and deliberately safe: with no known previous state,
	// ApplyIncremental always declines and Sync falls back to the full
	// Render+Apply(+restart) path for that one sync, then resumes
	// incremental applies from there.
	appliedState json.RawMessage
	// appliedGrantCount is len(grants) from appliedState, tracked alongside
	// it so Sync can sanity-check a new state's grant count against the one
	// actually live, without re-decoding appliedState on every poll.
	appliedGrantCount int
	// suspiciousDropStreak counts consecutive Sync polls in a row that all
	// proposed the same kind of suspicious grant-count drop (see Sync). It
	// resets to 0 the moment a poll doesn't look suspicious or a drop gets
	// accepted.
	suspiciousDropStreak int
}

// Sanity-check constants for the grant-count drop guard in Sync: a plain
// floor/threshold check against the previously-applied grant count, meant to
// catch Core serving a bad/empty/truncated desired state (bug, partial
// outage, bad migration) before it wipes every live client off this node.
const (
	// minGrantsForDropCheck is the previous grant count below which a drop
	// isn't worth second-guessing — a handful of grants disappearing on an
	// already near-empty node is unremarkable, and it must never block a
	// freshly-enrolled node's legitimate first sync starting from zero.
	minGrantsForDropCheck = 5
	// maxGrantDropRatio is the largest fraction of the previous grant count
	// a new state is allowed to keep before Sync treats the drop as
	// suspicious rather than an ordinary batch of expirations/revocations.
	// 0.5 means "lost more than half the grants in one sync".
	maxGrantDropRatio = 0.5
	// maxConsecutiveDropRefusals bounds how many Sync cycles in a row will
	// refuse the same kind of suspicious drop before accepting it as a
	// real, sustained change (e.g. a genuine mass revocation) rather than a
	// one-off/transient bad response. This is a soft valve, not a hard
	// block: it never gets permanently stuck refusing.
	maxConsecutiveDropRefusals = 3
)

// grantCountState is just enough of the desired-state JSON to count grants,
// shared across whatever RuntimeAdapter is active — every adapter's state
// payload carries a top-level "grants" array (see xrayDesiredState).
type grantCountState struct {
	Grants []json.RawMessage `json:"grants"`
}

func countGrants(state json.RawMessage) int {
	if len(state) == 0 {
		return 0
	}
	var s grantCountState
	if err := json.Unmarshal(state, &s); err != nil {
		return 0
	}
	return len(s.Grants)
}

type nodeResponse struct {
	ID     string `json:"id"`
	Code   string `json:"code"`
	Region string `json:"region"`
	Status string `json:"status"`
}

type enrollResponse struct {
	Node         nodeResponse `json:"node"`
	NodeAPIToken string       `json:"node_api_token"`
}

type desiredState struct {
	NodeID   string          `json:"node_id"`
	Revision int             `json:"revision"`
	State    json.RawMessage `json:"state"`
}

func New(cfg config.Config, log *slog.Logger) *Agent {
	var runtimeAdapter wbruntime.RuntimeAdapter = wbruntime.NoopAdapter{}
	if strings.EqualFold(cfg.RuntimeAdapter, "xray") {
		runtimeAdapter = wbruntime.NewXrayAdapter(cfg.Xray)
	}
	agent := &Agent{
		cfg: cfg,
		log: log,
		client: &http.Client{
			Timeout: 10 * time.Second,
		},
		adapter: runtimeAdapter,
	}
	if reporter, ok := runtimeAdapter.(wbruntime.UsageReporter); ok {
		agent.usageReporter = reporter
	}
	if incremental, ok := runtimeAdapter.(wbruntime.IncrementalApplier); ok {
		agent.incrementalApply = incremental
	}
	return agent
}

func (a *Agent) Run(ctx context.Context) error {
	a.nodeToken = a.cfg.NodeAPIToken
	if a.nodeToken == "" {
		if token, err := os.ReadFile(a.tokenPath()); err == nil {
			if trimmed := strings.TrimSpace(string(token)); trimmed != "" {
				a.nodeToken = trimmed
				a.log.InfoContext(ctx, "loaded persisted node API token")
			}
		}
	}
	if a.nodeToken == "" && a.cfg.EnrollmentToken == "" {
		return fmt.Errorf("WAVEBREAK_NODE_API_TOKEN or WAVEBREAK_NODE_ENROLLMENT_TOKEN is required")
	}
	if a.nodeToken == "" {
		if err := a.withBackoff(ctx, a.Enroll); err != nil {
			return err
		}
	}
	if err := a.withBackoff(ctx, a.Heartbeat); err != nil {
		return err
	}
	heartbeatTicker := time.NewTicker(a.cfg.HeartbeatInterval)
	defer heartbeatTicker.Stop()
	syncTicker := time.NewTicker(a.cfg.SyncInterval)
	defer syncTicker.Stop()
	var usageTickerC <-chan time.Time
	if a.usageReporter != nil {
		usageTicker := time.NewTicker(a.cfg.UsageInterval)
		defer usageTicker.Stop()
		usageTickerC = usageTicker.C
	}
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-heartbeatTicker.C:
			if err := a.Heartbeat(ctx); err != nil {
				a.log.WarnContext(ctx, "heartbeat failed", "error", err)
			}
		case <-syncTicker.C:
			if err := a.Sync(ctx); err != nil {
				a.log.WarnContext(ctx, "desired state sync failed", "error", err)
			}
		case <-usageTickerC:
			if err := a.ReportUsage(ctx); err != nil {
				a.log.WarnContext(ctx, "usage report failed", "error", err)
			}
		}
	}
}

func (a *Agent) Enroll(ctx context.Context) error {
	payload := map[string]string{"code": a.cfg.NodeCode}
	var response enrollResponse
	if err := a.postWithToken(ctx, "/v1/node/enroll", a.cfg.EnrollmentToken, payload, &response); err != nil {
		return fmt.Errorf("enroll node: %w", err)
	}
	a.nodeID = response.Node.ID
	a.nodeToken = response.NodeAPIToken
	if err := os.MkdirAll(filepath.Dir(a.tokenPath()), 0o755); err != nil {
		a.log.WarnContext(ctx, "could not create node token directory", "error", err)
	} else if err := os.WriteFile(a.tokenPath(), []byte(a.nodeToken), 0o600); err != nil {
		a.log.WarnContext(ctx, "could not persist node API token", "error", err)
	}
	a.log.InfoContext(ctx, "node enrolled", "node_id", response.Node.ID, "code", response.Node.Code, "region", response.Node.Region)
	return nil
}

// tokenPath returns where the node API token is persisted across restarts,
// so a container recreate doesn't have to re-enroll with a (single-use)
// enrollment token. Defaults to a file alongside the xray runtime config,
// which is already on a persistent volume in the pilot deployment.
func (a *Agent) tokenPath() string {
	if strings.TrimSpace(a.cfg.NodeTokenPath) != "" {
		return a.cfg.NodeTokenPath
	}
	if strings.TrimSpace(a.cfg.Xray.ConfigPath) != "" {
		return filepath.Join(filepath.Dir(a.cfg.Xray.ConfigPath), ".wavebreak-node-token")
	}
	return "/var/lib/wavebreak/node-token"
}

func (a *Agent) Heartbeat(ctx context.Context) error {
	if a.nodeID == "" {
		a.nodeID = a.cfg.NodeCode
	}
	var node nodeResponse
	if err := a.postWithToken(ctx, "/v1/node/heartbeat", a.nodeToken, map[string]string{}, &node); err != nil {
		return err
	}
	a.nodeID = node.ID
	a.log.InfoContext(ctx, "heartbeat acknowledged", "node_id", node.ID, "status", node.Status)
	return nil
}

// ReportUsage reads current cumulative per-grant traffic from the runtime
// and posts each grant's totals to Core, which tracks the last-seen total
// itself and derives the delta (see wavebreak-core's
// RecordNodeUsageReport) — so this always sends raw running totals, never
// something the agent itself has to diff.
func (a *Agent) ReportUsage(ctx context.Context) error {
	if a.usageReporter == nil {
		return nil
	}
	usage, err := a.usageReporter.QueryUsage(ctx)
	if err != nil {
		return err
	}
	now := time.Now().UTC().Format(time.RFC3339Nano)
	var reportErr error
	for _, grant := range usage {
		payload := map[string]any{
			"grant_id":         grant.GrantID,
			"bytes_up_total":   grant.BytesUp,
			"bytes_down_total": grant.BytesDown,
			"timestamp":        now,
		}
		if err := a.postWithToken(ctx, "/v1/node/usage", a.nodeToken, payload, &map[string]any{}); err != nil {
			a.log.WarnContext(ctx, "usage report failed for grant", "grant_id", grant.GrantID, "error", err)
			reportErr = err
		}
	}
	return reportErr
}

func (a *Agent) Sync(ctx context.Context) error {
	var desired desiredState
	if err := a.getWithToken(ctx, "/v1/node/state", a.nodeToken, &desired); err != nil {
		return err
	}
	if desired.Revision <= a.appliedRevision {
		return nil
	}
	if err := a.adapter.Validate(ctx, desired.State); err != nil {
		_ = a.reportFailure(ctx, desired.Revision, err)
		return err
	}

	// Sanity-check the new grant count against what's actually live before
	// applying anything. Guards against Core serving a bad/empty/truncated
	// state (bug, partial outage, bad migration) that would otherwise wipe
	// every connected client off this node in one sync. Skipped entirely on
	// the very first sync since this process started (appliedState == nil)
	// so a freshly-enrolled node can legitimately start from zero.
	newGrantCount := countGrants(desired.State)
	if a.appliedState != nil && a.appliedGrantCount >= minGrantsForDropCheck &&
		float64(newGrantCount) <= float64(a.appliedGrantCount)*maxGrantDropRatio {
		a.suspiciousDropStreak++
		if a.suspiciousDropStreak <= maxConsecutiveDropRefusals {
			a.log.WarnContext(ctx, "refusing desired state: grant count dropped suspiciously, keeping last-known-good config",
				"revision", desired.Revision,
				"previous_grants", a.appliedGrantCount,
				"new_grants", newGrantCount,
				"consecutive_refusals", a.suspiciousDropStreak,
				"max_consecutive_refusals", maxConsecutiveDropRefusals)
			return nil
		}
		a.log.WarnContext(ctx, "accepting grant count drop after repeated confirmation across consecutive syncs",
			"revision", desired.Revision,
			"previous_grants", a.appliedGrantCount,
			"new_grants", newGrantCount,
			"consecutive_refusals", a.suspiciousDropStreak)
	} else {
		a.suspiciousDropStreak = 0
	}

	// Try the live, non-disruptive path first: a plain grant add/remove can
	// be applied without touching anything else already connected. Only
	// available once we actually know the previously-applied state (not
	// the very first sync since this process started) and only trusted
	// when the adapter itself is confident it fully understood the change
	// (ok=true) — anything else falls back to the full path below, which
	// is always correct even if occasionally more disruptive.
	if a.incrementalApply != nil && a.appliedState != nil {
		ok, err := a.incrementalApply.ApplyIncremental(ctx, a.appliedState, desired.State)
		if err != nil {
			_ = a.reportFailure(ctx, desired.Revision, err)
			return err
		}
		if ok {
			if err := a.adapter.Health(ctx); err != nil {
				_ = a.adapter.Rollback(ctx)
				_ = a.reportFailure(ctx, desired.Revision, err)
				return err
			}
			if err := a.postWithToken(ctx, "/v1/node/state/ack", a.nodeToken, map[string]int{"revision": desired.Revision}, &map[string]string{}); err != nil {
				return err
			}
			a.appliedRevision = desired.Revision
			a.appliedState = desired.State
			a.appliedGrantCount = newGrantCount
			a.suspiciousDropStreak = 0
			a.log.InfoContext(ctx, "desired state applied live (no restart)", "revision", desired.Revision)
			return nil
		}
		a.log.InfoContext(ctx, "live apply declined change, falling back to full apply", "revision", desired.Revision)
	}

	rendered, err := a.adapter.Render(ctx, desired.State)
	if err != nil {
		_ = a.reportFailure(ctx, desired.Revision, err)
		return err
	}
	if err := a.adapter.Apply(ctx, rendered); err != nil {
		_ = a.adapter.Rollback(ctx)
		_ = a.reportFailure(ctx, desired.Revision, err)
		return err
	}
	if err := a.adapter.Health(ctx); err != nil {
		_ = a.adapter.Rollback(ctx)
		_ = a.reportFailure(ctx, desired.Revision, err)
		return err
	}
	if err := a.postWithToken(ctx, "/v1/node/state/ack", a.nodeToken, map[string]int{"revision": desired.Revision}, &map[string]string{}); err != nil {
		return err
	}
	a.appliedRevision = desired.Revision
	a.appliedState = desired.State
	a.appliedGrantCount = newGrantCount
	a.suspiciousDropStreak = 0
	a.log.InfoContext(ctx, "desired state applied", "revision", desired.Revision)
	return nil
}

func (a *Agent) reportFailure(ctx context.Context, revision int, cause error) error {
	return a.postWithToken(ctx, "/v1/node/state/fail", a.nodeToken, map[string]any{
		"revision": revision,
		"error":    cause.Error(),
	}, &map[string]string{})
}

func (a *Agent) postWithToken(ctx context.Context, path, token string, payload any, dst any) error {
	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, strings.TrimRight(a.cfg.CoreURL, "/")+path, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	return a.do(req, dst)
}

func (a *Agent) getWithToken(ctx context.Context, path, token string, dst any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, strings.TrimRight(a.cfg.CoreURL, "/")+path, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	return a.do(req, dst)
}

func (a *Agent) do(req *http.Request, dst any) error {
	resp, err := a.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return fmt.Errorf("core returned status %d", resp.StatusCode)
	}
	return json.NewDecoder(resp.Body).Decode(dst)
}

func (a *Agent) withBackoff(ctx context.Context, fn func(context.Context) error) error {
	delay := time.Second
	for {
		err := fn(ctx)
		if err == nil {
			return nil
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(delay + time.Duration(rand.Int64N(int64(delay/2)+1))):
		}
		if delay < 30*time.Second {
			delay *= 2
		}
	}
}
