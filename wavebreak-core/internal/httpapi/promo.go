package httpapi

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"wavebreak-core/internal/store"
)

// promoPlanPrice: a plan's price with the code applied.
type promoPlanPrice struct {
	PlanID               string `json:"plan_id"`
	PriceMinor           int64  `json:"price_minor"`
	DiscountedPriceMinor int64  `json:"discounted_price_minor"`
	Currency             string `json:"currency"`
}

type promoCheckResponse struct {
	Code          string           `json:"code"`
	Description   string           `json:"description"`
	DiscountType  string           `json:"discount_type"`
	DiscountValue int64            `json:"discount_value"`
	Currency      *string          `json:"currency,omitempty"`
	PlanID        *string          `json:"plan_id,omitempty"`
	ValidUntil    *time.Time       `json:"valid_until,omitempty"`
	Plans         []promoPlanPrice `json:"plans"`
}

// checkPromoCode: POST /v1/promo-codes/check {code, plan_id?}. Says
// whether the signed-in user can use the code and what the public plans
// cost with it. Checking doesn't use up an activation — that happens at
// the payment step. A refusal is 422 with the reason as the error code
// (PROMO_NOT_FOUND, PROMO_EXPIRED, ...).
func (s *Server) checkPromoCode(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Code   string `json:"code"`
		PlanID string `json:"plan_id"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	code := store.NormalizePromoCode(req.Code)
	if code == "" {
		writeError(w, http.StatusBadRequest, "code is required")
		return
	}
	ctx := r.Context()
	promo, err := s.app.Store.FindPromoCode(ctx, code)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusUnprocessableEntity, store.PromoNotFound)
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not check promo code")
		return
	}
	used, err := s.app.Store.PromoUsedBy(ctx, promo.ID, currentUser(ctx).ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not check promo code")
		return
	}
	if reason := promo.Usable(time.Now(), used); reason != "" {
		writeError(w, http.StatusUnprocessableEntity, reason)
		return
	}
	plans, err := s.app.Store.ListPlans(ctx)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not list plans")
		return
	}
	resp := promoCheckResponse{
		Code: promo.Code, Description: promo.Description, DiscountType: promo.DiscountType,
		DiscountValue: promo.DiscountValue, Currency: promo.Currency, PlanID: promo.PlanID,
		ValidUntil: promo.ValidUntil, Plans: []promoPlanPrice{},
	}
	reason := store.PromoNotForPlan
	for _, plan := range plans {
		if req.PlanID != "" && plan.ID != req.PlanID {
			continue
		}
		if why := promo.AppliesTo(plan); why != "" {
			reason = why
			continue
		}
		resp.Plans = append(resp.Plans, promoPlanPrice{
			PlanID: plan.ID, PriceMinor: plan.PriceMinor,
			DiscountedPriceMinor: promo.DiscountedPrice(plan), Currency: plan.Currency,
		})
	}
	if len(resp.Plans) == 0 {
		writeError(w, http.StatusUnprocessableEntity, reason)
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

func (s *Server) adminPromoCodes(w http.ResponseWriter, r *http.Request) {
	codes, err := s.app.Store.ListPromoCodes(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not list promo codes")
		return
	}
	if codes == nil {
		codes = []store.PromoCode{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"promo_codes": codes})
}

func (s *Server) adminCreatePromoCode(w http.ResponseWriter, r *http.Request) {
	promo, ok := decodePromoRequest(w, r)
	if !ok {
		return
	}
	actor := currentUser(r.Context()).ID
	created, err := s.app.Store.CreatePromoCode(r.Context(), promo, actor)
	if !promoWriteOK(w, err) {
		return
	}
	_ = s.app.Store.WriteAuditEvent(r.Context(), &actor, "promo_code.created", "promo_code", &created.ID, map[string]any{"code": created.Code})
	writeJSON(w, http.StatusCreated, created)
}

func (s *Server) adminUpdatePromoCode(w http.ResponseWriter, r *http.Request) {
	promo, ok := decodePromoRequest(w, r)
	if !ok {
		return
	}
	promo.ID = chi.URLParam(r, "promoID")
	updated, err := s.app.Store.UpdatePromoCode(r.Context(), promo)
	if !promoWriteOK(w, err) {
		return
	}
	actor := currentUser(r.Context()).ID
	_ = s.app.Store.WriteAuditEvent(r.Context(), &actor, "promo_code.updated", "promo_code", &updated.ID, map[string]any{"code": updated.Code})
	writeJSON(w, http.StatusOK, updated)
}

func (s *Server) adminDeletePromoCode(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "promoID")
	err := s.app.Store.DeletePromoCode(r.Context(), id)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "promo code not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not delete promo code")
		return
	}
	actor := currentUser(r.Context()).ID
	_ = s.app.Store.WriteAuditEvent(r.Context(), &actor, "promo_code.deleted", "promo_code", &id, nil)
	writeJSON(w, http.StatusOK, map[string]any{"deleted": true})
}

func promoWriteOK(w http.ResponseWriter, err error) bool {
	switch {
	case err == nil:
		return true
	case errors.Is(err, store.ErrPromoCodeTaken):
		writeError(w, http.StatusConflict, "PROMO_CODE_TAKEN")
	case errors.Is(err, store.ErrNotFound):
		writeError(w, http.StatusNotFound, "promo code not found")
	default:
		writeError(w, http.StatusBadRequest, "could not save promo code")
	}
	return false
}

// decodePromoRequest validates an admin create/update body.
func decodePromoRequest(w http.ResponseWriter, r *http.Request) (store.PromoCode, bool) {
	var req struct {
		Code           string     `json:"code"`
		Description    string     `json:"description"`
		DiscountType   string     `json:"discount_type"`
		DiscountValue  int64      `json:"discount_value"`
		Currency       string     `json:"currency"`
		PlanID         string     `json:"plan_id"`
		ValidFrom      *time.Time `json:"valid_from"`
		ValidUntil     *time.Time `json:"valid_until"`
		MaxActivations *int       `json:"max_activations"`
		IsActive       *bool      `json:"is_active"`
	}
	if !decodeJSON(w, r, &req) {
		return store.PromoCode{}, false
	}
	p, problem := buildPromo(req.Code, req.Description, req.DiscountType, req.DiscountValue,
		req.Currency, req.PlanID, req.ValidFrom, req.ValidUntil, req.MaxActivations, req.IsActive)
	if problem != "" {
		writeError(w, http.StatusBadRequest, problem)
		return store.PromoCode{}, false
	}
	return p, true
}

// buildPromo checks and normalizes the fields of a promo code; the
// second result is what's wrong ("" when nothing).
func buildPromo(code, description, discountType string, value int64, currency, planID string,
	validFrom, validUntil *time.Time, maxActivations *int, isActive *bool) (store.PromoCode, string) {
	code = store.NormalizePromoCode(code)
	if n := len([]rune(code)); n < 3 || n > 40 {
		return store.PromoCode{}, "code must be 3 to 40 characters"
	}
	for _, c := range code {
		if !(c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '-' || c == '_') {
			return store.PromoCode{}, "code may contain only latin letters, digits, - and _"
		}
	}
	p := store.PromoCode{
		Code:          code,
		Description:   strings.TrimSpace(description),
		DiscountType:  strings.ToLower(strings.TrimSpace(discountType)),
		DiscountValue: value,
		IsActive:      isActive == nil || *isActive,
	}
	switch p.DiscountType {
	case "percent":
		if value < 1 || value > 100 {
			return store.PromoCode{}, "percent discount must be 1 to 100"
		}
	case "fixed":
		if value < 1 {
			return store.PromoCode{}, "fixed discount must be positive"
		}
		cur := strings.ToUpper(strings.TrimSpace(currency))
		if cur == "" {
			return store.PromoCode{}, "fixed discount needs a currency"
		}
		p.Currency = &cur
	default:
		return store.PromoCode{}, "discount_type must be percent or fixed"
	}
	if id := strings.TrimSpace(planID); id != "" {
		p.PlanID = &id
	}
	if validFrom != nil && validUntil != nil && !validUntil.After(*validFrom) {
		return store.PromoCode{}, "valid_until must be after valid_from"
	}
	p.ValidFrom, p.ValidUntil = validFrom, validUntil
	if maxActivations != nil && *maxActivations < 1 {
		return store.PromoCode{}, "max_activations must be positive"
	}
	p.MaxActivations = maxActivations
	return p, ""
}
