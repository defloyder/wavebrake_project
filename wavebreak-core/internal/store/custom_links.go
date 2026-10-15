package store

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
)

// LinkVault is a user's sealed custom-link document (migration 00008).
// The store never sees it in the clear.
type LinkVault struct {
	Version    int64
	Nonce      []byte
	Ciphertext []byte
}

// ErrVersionConflict: another device wrote the vault since [expected].
var ErrVersionConflict = errors.New("version conflict")

// LinkVaultOf returns the user's vault; found is false when there is none.
func (s *Store) LinkVaultOf(ctx context.Context, userID string) (LinkVault, bool, error) {
	var v LinkVault
	err := s.db.QueryRow(ctx, `
		select version, nonce, ciphertext from custom_link_vaults where user_id = $1`,
		userID).Scan(&v.Version, &v.Nonce, &v.Ciphertext)
	if errors.Is(err, pgx.ErrNoRows) {
		return LinkVault{}, false, nil
	}
	if err != nil {
		return LinkVault{}, false, err
	}
	return v, true, nil
}

// PutLinkVault stores a new sealed document if the vault is still at
// [expected] (0: there is none yet) and returns the new version. On
// ErrVersionConflict it returns the current vault, for the device to merge
// with and try again.
func (s *Store) PutLinkVault(ctx context.Context, userID string, expected int64, nonce, ciphertext []byte) (int64, LinkVault, error) {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return 0, LinkVault{}, err
	}
	defer tx.Rollback(ctx)

	var cur LinkVault
	err = tx.QueryRow(ctx, `
		select version, nonce, ciphertext from custom_link_vaults
		where user_id = $1 for update`, userID).Scan(&cur.Version, &cur.Nonce, &cur.Ciphertext)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		if expected != 0 {
			return 0, LinkVault{}, ErrVersionConflict
		}
		tag, err := tx.Exec(ctx, `
			insert into custom_link_vaults (user_id, nonce, ciphertext, version)
			values ($1, $2, $3, 1) on conflict (user_id) do nothing`,
			userID, nonce, ciphertext)
		if err != nil {
			return 0, LinkVault{}, err
		}
		if tag.RowsAffected() == 0 {
			// Another device created it a moment ago.
			v, _, err := s.LinkVaultOf(ctx, userID)
			if err != nil {
				return 0, LinkVault{}, err
			}
			return 0, v, ErrVersionConflict
		}
		return 1, LinkVault{}, tx.Commit(ctx)
	case err != nil:
		return 0, LinkVault{}, err
	}
	if cur.Version != expected {
		return 0, cur, ErrVersionConflict
	}
	var next int64
	if err := tx.QueryRow(ctx, `
		update custom_link_vaults
		set nonce = $2, ciphertext = $3, version = version + 1, updated_at = now()
		where user_id = $1 returning version`, userID, nonce, ciphertext).Scan(&next); err != nil {
		return 0, LinkVault{}, err
	}
	return next, LinkVault{}, tx.Commit(ctx)
}
