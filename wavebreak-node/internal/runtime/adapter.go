package runtime

import (
	"context"
	"encoding/json"
)

type RuntimeAdapter interface {
	Validate(context.Context, json.RawMessage) error
	Render(context.Context, json.RawMessage) ([]byte, error)
	Apply(context.Context, []byte) error
	Health(context.Context) error
	Rollback(context.Context) error
}

// GrantUsage is one grant's cumulative traffic counters as read from the
// runtime (Xray/Hysteria2) since it last restarted. Deliberately raw
// totals, not deltas — Core tracks the last-seen total per grant itself
// and computes the delta, which also lets it detect and absorb a counter
// reset from a runtime restart instead of the agent having to.
type GrantUsage struct {
	GrantID   string
	BytesUp   int64
	BytesDown int64
}

// UsageReporter is implemented by adapters that can read back per-grant
// traffic counters from whatever they're running. Optional — NoopAdapter
// doesn't implement it, and the agent's usage-reporting loop simply stays
// off when the active adapter doesn't support it.
type UsageReporter interface {
	QueryUsage(context.Context) ([]GrantUsage, error)
}

type NoopAdapter struct{}

func (NoopAdapter) Validate(context.Context, json.RawMessage) error { return nil }

func (NoopAdapter) Render(_ context.Context, state json.RawMessage) ([]byte, error) {
	if len(state) == 0 {
		return []byte("{}"), nil
	}
	return state, nil
}

func (NoopAdapter) Apply(context.Context, []byte) error { return nil }

func (NoopAdapter) Health(context.Context) error { return nil }

func (NoopAdapter) Rollback(context.Context) error { return nil }
