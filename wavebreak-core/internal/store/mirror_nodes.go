package store

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
)

// MirrorNode is a second location serving another node's grants (see
// migration 00006), with its own public connection parameters.
type MirrorNode struct {
	Node         Node
	PublicConfig json.RawMessage
}

// MirrorNodesOf lists the nodes serving sourceNodeID's grants.
func (s *Store) MirrorNodesOf(ctx context.Context, sourceNodeID string) ([]MirrorNode, error) {
	rows, err := s.db.Query(ctx, `
		select id::text, code, region, status, desired_revision, applied_revision,
		       last_sync_error, last_heartbeat_at, public_config
		from nodes
		where shares_grants_of = $1
		order by code`, sourceNodeID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []MirrorNode
	for rows.Next() {
		var m MirrorNode
		if err := rows.Scan(&m.Node.ID, &m.Node.Code, &m.Node.Region, &m.Node.Status,
			&m.Node.DesiredRevision, &m.Node.AppliedRevision, &m.Node.LastSyncError,
			&m.Node.LastHeartbeatAt, &m.PublicConfig); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// LinkMirrorNode makes mirrorCode serve sourceCode's grants with the given
// public connection parameters, and publishes its desired state at once.
func (s *Store) LinkMirrorNode(ctx context.Context, mirrorCode, sourceCode string, publicConfig json.RawMessage) (int, error) {
	if !json.Valid(publicConfig) {
		return 0, errors.New("public config is not valid JSON")
	}
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback(ctx)
	var mirrorID, sourceID string
	if err := tx.QueryRow(ctx, `select id::text from nodes where code = $1`, mirrorCode).Scan(&mirrorID); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return 0, ErrNotFound
		}
		return 0, err
	}
	if err := tx.QueryRow(ctx, `select id::text from nodes where code = $1`, sourceCode).Scan(&sourceID); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return 0, ErrNotFound
		}
		return 0, err
	}
	if mirrorID == sourceID {
		return 0, errors.New("a node can't mirror itself")
	}
	if _, err := tx.Exec(ctx, `
		update nodes set shares_grants_of = $2, public_config = $3, updated_at = $4
		where id = $1`, mirrorID, sourceID, publicConfig, time.Now().UTC()); err != nil {
		return 0, err
	}
	revision, err := writeNodeDesiredStateTx(ctx, tx, mirrorID, sourceID)
	if err != nil {
		return 0, err
	}
	return revision, tx.Commit(ctx)
}

// ListPrimaryNodes: ListNodes without mirror nodes — what the apps list as
// locations (a mirror's own rows come with the account's links).
func (s *Store) ListPrimaryNodes(ctx context.Context) ([]Node, error) {
	all, err := s.ListNodes(ctx)
	if err != nil {
		return nil, err
	}
	rows, err := s.db.Query(ctx, `select id::text from nodes where shares_grants_of is not null`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	mirror := map[string]bool{}
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		mirror[id] = true
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	out := all[:0:0]
	for _, n := range all {
		if !mirror[n.ID] {
			out = append(out, n)
		}
	}
	return out, nil
}
