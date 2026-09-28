package store

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
)

// EmailState is what the verification flow needs to know about a user.
type EmailState struct {
	VerifiedAt *time.Time
	Required   bool
	Language   string
}

// Verified reports whether the address has been confirmed.
func (e EmailState) Verified() bool { return e.VerifiedAt != nil }

// MaxEmailCodeAttempts wrong guesses lock a code; a new one must be sent.
const MaxEmailCodeAttempts = 5

var (
	ErrEmailCodeMissing  = errors.New("no pending email code")
	ErrEmailCodeExpired  = errors.New("email code expired")
	ErrEmailCodeLocked   = errors.New("too many wrong email codes")
	ErrEmailCodeMismatch = errors.New("wrong email code")
)

func (s *Store) UserEmailState(ctx context.Context, userID string) (EmailState, error) {
	var st EmailState
	err := s.db.QueryRow(ctx, `
		select email_verified_at, email_verification_required, email_language
		from users where id = $1`, userID,
	).Scan(&st.VerifiedAt, &st.Required, &st.Language)
	if errors.Is(err, pgx.ErrNoRows) {
		return EmailState{}, ErrNotFound
	}
	return st, err
}

// RequireEmailVerification marks an account created by an app that runs
// the verification step, and stores the language its emails are in.
func (s *Store) RequireEmailVerification(ctx context.Context, userID, language string) error {
	_, err := s.db.Exec(ctx, `
		update users set email_verification_required = true, email_language = $2, updated_at = now()
		where id = $1`, userID, language)
	return err
}

func (s *Store) SetEmailLanguage(ctx context.Context, userID, language string) error {
	_, err := s.db.Exec(ctx, `update users set email_language = $2 where id = $1`, userID, language)
	return err
}

// EmailCodeSentAt is when the pending code was sent (zero time: none).
func (s *Store) EmailCodeSentAt(ctx context.Context, userID string) (time.Time, error) {
	var sentAt time.Time
	err := s.db.QueryRow(ctx, `select sent_at from email_verification_codes where user_id = $1`, userID).Scan(&sentAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return time.Time{}, nil
	}
	return sentAt, err
}

// SaveEmailCode replaces the user's pending code (and resets attempts).
func (s *Store) SaveEmailCode(ctx context.Context, userID, codeHash string, expiresAt time.Time) error {
	_, err := s.db.Exec(ctx, `
		insert into email_verification_codes (user_id, code_hash, expires_at, attempts, sent_at)
		values ($1, $2, $3, 0, now())
		on conflict (user_id) do update
		set code_hash = excluded.code_hash, expires_at = excluded.expires_at, attempts = 0, sent_at = now()`,
		userID, codeHash, expiresAt)
	return err
}

// ConfirmEmailCode checks a code. On a match the address is marked
// verified and the code is consumed; a wrong code counts an attempt.
func (s *Store) ConfirmEmailCode(ctx context.Context, userID, codeHash string) error {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	var stored string
	var expiresAt time.Time
	var attempts int
	err = tx.QueryRow(ctx, `
		select code_hash, expires_at, attempts from email_verification_codes
		where user_id = $1 for update`, userID,
	).Scan(&stored, &expiresAt, &attempts)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrEmailCodeMissing
	}
	if err != nil {
		return err
	}
	switch {
	case attempts >= MaxEmailCodeAttempts:
		return ErrEmailCodeLocked
	case time.Now().After(expiresAt):
		return ErrEmailCodeExpired
	case stored != codeHash:
		if _, err := tx.Exec(ctx, `update email_verification_codes set attempts = attempts + 1 where user_id = $1`, userID); err != nil {
			return err
		}
		if err := tx.Commit(ctx); err != nil {
			return err
		}
		if attempts+1 >= MaxEmailCodeAttempts {
			return ErrEmailCodeLocked
		}
		return ErrEmailCodeMismatch
	}
	if _, err := tx.Exec(ctx, `delete from email_verification_codes where user_id = $1`, userID); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `
		update users set email_verified_at = coalesce(email_verified_at, now()), updated_at = now()
		where id = $1`, userID); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// SubscriptionNotice is what the "subscription active" email needs.
type SubscriptionNotice struct {
	Email     string
	Language  string
	PlanName  string
	Status    string
	PeriodEnd *time.Time
}

// Live: the subscription really is usable (not pending payment).
func (n SubscriptionNotice) Live() bool { return n.Status == "active" || n.Status == "trialing" }

func (s *Store) SubscriptionNoticeFor(ctx context.Context, subscriptionID string) (SubscriptionNotice, error) {
	var n SubscriptionNotice
	err := s.db.QueryRow(ctx, `
		select coalesce(u.email, ''), u.email_language, coalesce(p.name, ''), s.status, s.current_period_end
		from subscriptions s
		join users u on u.id = s.user_id
		left join plans p on p.id = s.plan_id
		where s.id = $1`, subscriptionID,
	).Scan(&n.Email, &n.Language, &n.PlanName, &n.Status, &n.PeriodEnd)
	if errors.Is(err, pgx.ErrNoRows) {
		return SubscriptionNotice{}, ErrNotFound
	}
	return n, err
}
