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
