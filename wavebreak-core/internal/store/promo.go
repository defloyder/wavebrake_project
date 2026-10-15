package store

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// PromoCode is a discount code: a percent or a fixed amount off, maybe
// only for one plan, valid within a window, up to [MaxActivations] uses.
type PromoCode struct {
	ID               string     `json:"id"`
	Code             string     `json:"code"`
	Description      string     `json:"description"`
	DiscountType     string     `json:"discount_type"` // percent | fixed
	DiscountValue    int64      `json:"discount_value"`
	Currency         *string    `json:"currency,omitempty"`
	PlanID           *string    `json:"plan_id,omitempty"`
	ValidFrom        *time.Time `json:"valid_from,omitempty"`
	ValidUntil       *time.Time `json:"valid_until,omitempty"`
	MaxActivations   *int       `json:"max_activations,omitempty"`
	ActivationsCount int        `json:"activations_count"`
	IsActive         bool       `json:"is_active"`
	CreatedAt        time.Time  `json:"created_at"`
	UpdatedAt        time.Time  `json:"updated_at"`
}

// Why a promo code can't be used; the API returns these as error codes.
const (
	PromoNotFound      = "PROMO_NOT_FOUND"
	PromoInactive      = "PROMO_INACTIVE"
	PromoNotStarted    = "PROMO_NOT_STARTED"
	PromoExpired       = "PROMO_EXPIRED"
	PromoExhausted     = "PROMO_EXHAUSTED"
	PromoAlreadyUsed   = "PROMO_ALREADY_USED"
	PromoNotForPlan    = "PROMO_NOT_FOR_PLAN"
	PromoWrongCurrency = "PROMO_CURRENCY_MISMATCH"
)

// ErrPromoRejected wraps a rejection code from RedeemPromoCode.
var ErrPromoRejected = errors.New("promo code rejected")

// NormalizePromoCode: codes are matched upper-case, without spaces.
func NormalizePromoCode(code string) string {
	return strings.ToUpper(strings.Join(strings.Fields(code), ""))
}

// Usable says why the code can't be used right now (by a user who has /
// hasn't used it before), or "" when it can.
func (p PromoCode) Usable(now time.Time, usedByUser bool) string {
	switch {
	case !p.IsActive:
		return PromoInactive
	case p.ValidFrom != nil && now.Before(*p.ValidFrom):
		return PromoNotStarted
	case p.ValidUntil != nil && !now.Before(*p.ValidUntil):
		return PromoExpired
	case p.MaxActivations != nil && p.ActivationsCount >= *p.MaxActivations:
		return PromoExhausted
	case usedByUser:
		return PromoAlreadyUsed
	}
	return ""
}

// AppliesTo says why the code doesn't apply to [plan], or "".
func (p PromoCode) AppliesTo(plan Plan) string {
	if p.PlanID != nil && *p.PlanID != plan.ID {
		return PromoNotForPlan
	}
	if p.DiscountType == "fixed" && (p.Currency == nil || !strings.EqualFold(*p.Currency, plan.Currency)) {
		return PromoWrongCurrency
	}
	return ""
}

// DiscountedPrice of [plan] with this code, in minor units, never below 0.
// Percent discounts round to the nearest minor unit.
func (p PromoCode) DiscountedPrice(plan Plan) int64 {
	price := plan.PriceMinor
	var off int64
	switch p.DiscountType {
	case "percent":
		off = (price*p.DiscountValue + 50) / 100
	case "fixed":
		off = p.DiscountValue
	}
	if off > price {
		return 0
	}
	return price - off
}

const promoColumns = `id::text, code, description, discount_type, discount_value, currency, plan_id::text,
	valid_from, valid_until, max_activations, activations_count, is_active, created_at, updated_at`

func scanPromo(row pgx.Row) (PromoCode, error) {
	var p PromoCode
	err := row.Scan(&p.ID, &p.Code, &p.Description, &p.DiscountType, &p.DiscountValue, &p.Currency, &p.PlanID,
		&p.ValidFrom, &p.ValidUntil, &p.MaxActivations, &p.ActivationsCount, &p.IsActive, &p.CreatedAt, &p.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return PromoCode{}, ErrNotFound
	}
	return p, err
}

func (s *Store) ListPromoCodes(ctx context.Context) ([]PromoCode, error) {
	rows, err := s.db.Query(ctx, `select `+promoColumns+` from promo_codes order by created_at desc`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []PromoCode
	for rows.Next() {
		p, err := scanPromo(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// FindPromoCode by its code (any case); ErrNotFound when there's none.
func (s *Store) FindPromoCode(ctx context.Context, code string) (PromoCode, error) {
	return scanPromo(s.db.QueryRow(ctx, `select `+promoColumns+` from promo_codes where code = $1`, NormalizePromoCode(code)))
}

// ErrPromoCodeTaken: another promo code already has this code.
var ErrPromoCodeTaken = errors.New("promo code already exists")

func (s *Store) CreatePromoCode(ctx context.Context, p PromoCode, createdBy string) (PromoCode, error) {
	var by *string
	if createdBy != "" {
		by = &createdBy
	}
	created, err := scanPromo(s.db.QueryRow(ctx, `
		insert into promo_codes (code, description, discount_type, discount_value, currency, plan_id,
		                         valid_from, valid_until, max_activations, is_active, created_by)
		values ($1, $2, $3, $4, $5, $6::uuid, $7, $8, $9, $10, $11::uuid)
		returning `+promoColumns,
		NormalizePromoCode(p.Code), p.Description, p.DiscountType, p.DiscountValue, p.Currency, p.PlanID,
		p.ValidFrom, p.ValidUntil, p.MaxActivations, p.IsActive, by))
	return created, promoWriteError(err)
}

func (s *Store) UpdatePromoCode(ctx context.Context, p PromoCode) (PromoCode, error) {
	updated, err := scanPromo(s.db.QueryRow(ctx, `
		update promo_codes
		set code = $2, description = $3, discount_type = $4, discount_value = $5, currency = $6,
		    plan_id = $7::uuid, valid_from = $8, valid_until = $9, max_activations = $10,
		    is_active = $11, updated_at = now()
		where id = $1
		returning `+promoColumns,
		p.ID, NormalizePromoCode(p.Code), p.Description, p.DiscountType, p.DiscountValue, p.Currency, p.PlanID,
		p.ValidFrom, p.ValidUntil, p.MaxActivations, p.IsActive))
	return updated, promoWriteError(err)
}

func promoWriteError(err error) error {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" {
		return ErrPromoCodeTaken
	}
	return err
}

// DeletePromoCode removes the code and its activation history.
func (s *Store) DeletePromoCode(ctx context.Context, id string) error {
	tag, err := s.db.Exec(ctx, `delete from promo_codes where id = $1`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// PromoUsedBy: whether [userID] has already activated the code.
func (s *Store) PromoUsedBy(ctx context.Context, promoID, userID string) (bool, error) {
	var used bool
	err := s.db.QueryRow(ctx, `
		select exists(select 1 from promo_redemptions where promo_code_id = $1 and user_id = $2)`,
		promoID, userID).Scan(&used)
	return used, err
}

// RedeemPromoCode records one activation by [userID] for a purchase of
// [planID] — for the payment step, once a purchase with the code has gone
// through. Atomic: the count is raised only while under the limit, and a
// user activates a code once. A refusal wraps ErrPromoRejected with the
// rejection code.
func (s *Store) RedeemPromoCode(ctx context.Context, promoID, userID, planID string, subscriptionID *string) error {
	tag, err := s.db.Exec(ctx, `
		with upd as (
			update promo_codes
			set activations_count = activations_count + 1, updated_at = now()
			where id = $1 and is_active
			  and (max_activations is null or activations_count < max_activations)
			  and (valid_from is null or valid_from <= now())
			  and (valid_until is null or valid_until > now())
			returning id
		)
		insert into promo_redemptions (promo_code_id, user_id, plan_id, subscription_id)
		select id, $2::uuid, $3::uuid, $4::uuid from upd`,
		promoID, userID, planID, subscriptionID)
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" {
		return errors.Join(ErrPromoRejected, errors.New(PromoAlreadyUsed))
	}
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.Join(ErrPromoRejected, errors.New(PromoExhausted))
	}
	return nil
}
