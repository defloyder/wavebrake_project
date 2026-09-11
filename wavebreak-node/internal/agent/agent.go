package agent

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"math/rand/v2"
	"net/http"
	"strings"
	"time"

	"wavebreak-node/internal/config"
	wbruntime "wavebreak-node/internal/runtime"
)

type Agent struct {
	cfg             config.Config
	log             *slog.Logger
	client          *http.Client
	adapter         wbruntime.RuntimeAdapter
	nodeID          string
	nodeToken       string
	appliedRevision int
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
	return &Agent{
		cfg: cfg,
		log: log,
		client: &http.Client{
			Timeout: 10 * time.Second,
		},
		adapter: wbruntime.NoopAdapter{},
	}
}

func (a *Agent) Run(ctx context.Context) error {
	a.nodeToken = a.cfg.NodeAPIToken
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
	a.log.InfoContext(ctx, "node enrolled", "node_id", response.Node.ID, "code", response.Node.Code, "region", response.Node.Region)
	return nil
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
