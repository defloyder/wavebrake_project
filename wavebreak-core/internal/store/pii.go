package store

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
)

type piiRecord struct {
	Email           string
	Username        string
	PasswordHash    string
	PasswordAlgo    string
	EmailVerifiedAt *time.Time
}

type piiWrite struct {
	Email        string
	Username     string
	PasswordHash string
}

func (s *Store) loadPII(ctx context.Context, userID string) (piiRecord, error) {
	p := piiRecord{PasswordAlgo: "argon2id"}
	err := s.pii.QueryRow(ctx, `
		select coalesce(email, ''), coalesce(username, ''), coalesce(password_hash, ''), password_algo, email_verified_at
		from pii_users where user_id = $1`, userID,
	).Scan(&p.Email, &p.Username, &p.PasswordHash, &p.PasswordAlgo, &p.EmailVerifiedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return p, nil
	}
	return p, err
}

func (s *Store) loadPIIMany(ctx context.Context, userIDs []string) (map[string]piiRecord, error) {
	out := make(map[string]piiRecord, len(userIDs))
	if len(userIDs) == 0 {
		return out, nil
	}
	rows, err := s.pii.Query(ctx, `
		select user_id::text, coalesce(email, ''), coalesce(username, '')
		from pii_users where user_id = any($1::uuid[])`, userIDs)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var id string
		var p piiRecord
		if err := rows.Scan(&id, &p.Email, &p.Username); err != nil {
			return nil, err
		}
		out[id] = p
	}
	return out, rows.Err()
}

func (s *Store) upsertPII(ctx context.Context, userID string, w piiWrite) error {
	_, err := s.pii.Exec(ctx, `
		insert into pii_users (user_id, email, username, password_hash, password_algo)
		values ($1, nullif($2, ''), nullif($3, ''), nullif($4, ''), 'argon2id')
		on conflict (user_id) do update set
		    email = excluded.email,
		    username = excluded.username,
		    password_hash = coalesce(excluded.password_hash, pii_users.password_hash),
		    password_algo = case when excluded.password_hash is not null then 'argon2id' else pii_users.password_algo end,
		    updated_at = now()`,
		userID, w.Email, w.Username, w.PasswordHash,
	)
	return normalizeDatabaseError(err)
}

func (s *Store) fillAdminPII(ctx context.Context, u AdminUser) (AdminUser, error) {
	p, err := s.loadPII(ctx, u.ID)
	if err != nil {
		return AdminUser{}, err
	}
	u.Email, u.Username = p.Email, p.Username
	return u, nil
}

func (s *Store) setPIIPassword(ctx context.Context, userID, passwordHash, passwordAlgo string) error {
	_, err := s.pii.Exec(ctx, `
		update pii_users set password_hash = $2, password_algo = $3, updated_at = now()
		where user_id = $1`, userID, passwordHash, passwordAlgo)
	return normalizeDatabaseError(err)
}

func (s *Store) markPIIEmailVerified(ctx context.Context, userID string) error {
	_, err := s.pii.Exec(ctx, `
		update pii_users set email_verified_at = coalesce(email_verified_at, now()), updated_at = now()
		where user_id = $1`, userID)
	return err
}

func (s *Store) deletePII(ctx context.Context, userID string) error {
	_, err := s.pii.Exec(ctx, `delete from pii_users where user_id = $1`, userID)
	return err
}

// ImportLegacyPII copies email and credentials still held in the main users
// table into pii_users. Idempotent: rows already present in the PII DB are kept.
func (s *Store) ImportLegacyPII(ctx context.Context) (int, error) {
	rows, err := s.db.Query(ctx, `
		select id::text, coalesce(email, ''), coalesce(username, ''), coalesce(password_hash, ''), coalesce(password_algo, 'argon2id')
		from users
		where email is not null or password_hash is not null or username is not null`)
	if err != nil {
		return 0, err
	}
	type legacy struct{ id, email, username, hash, algo string }
	var batch []legacy
	for rows.Next() {
		var l legacy
		if err := rows.Scan(&l.id, &l.email, &l.username, &l.hash, &l.algo); err != nil {
			rows.Close()
			return 0, err
		}
		batch = append(batch, l)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, err
	}
	imported := 0
	for _, l := range batch {
		tag, err := s.pii.Exec(ctx, `
			insert into pii_users (user_id, email, username, password_hash, password_algo)
			values ($1, nullif($2, ''), nullif($3, ''), nullif($4, ''), $5)
			on conflict (user_id) do nothing`,
			l.id, l.email, l.username, l.hash, l.algo)
		if err != nil {
			return imported, normalizeDatabaseError(err)
		}
		imported += int(tag.RowsAffected())
	}
	return imported, nil
}
