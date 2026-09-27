// Package accounts holds the admin-facing account management use cases:
// user details, forced subscription assignment and password reset.
//
// Services depend only on the ports declared in ports.go; *store.Store
// implements them (store/accounts_repository.go), so the use cases are
// unit-testable without a database and the HTTP layer stays a thin adapter.
package accounts

import (
	"errors"
	"net/http"
)

// Error codes of the admin domain error model.
const (
	CodeUserNotFound                    = "USER_NOT_FOUND"
	CodePlanNotFound                    = "PLAN_NOT_FOUND"
	CodePlanInactive                    = "PLAN_INACTIVE"
	CodeSubscriptionAlreadyActive       = "SUBSCRIPTION_ALREADY_ACTIVE"
	CodeSubscriptionCreateFailed        = "SUBSCRIPTION_CREATE_FAILED"
	CodeSubscriptionNotFound            = "SUBSCRIPTION_NOT_FOUND"
	CodeSubscriptionNotActive           = "SUBSCRIPTION_NOT_ACTIVE"
	CodeAccessIssueFailed               = "ACCESS_ISSUE_FAILED"
	CodeNoNodeAvailable                 = "NO_NODE_AVAILABLE"
	CodePasswordResetChannelUnavailable = "PASSWORD_RESET_CHANNEL_UNAVAILABLE"
	CodePasswordResetFailed             = "PASSWORD_RESET_FAILED"
	CodePasswordResetTokenInvalid       = "PASSWORD_RESET_TOKEN_INVALID"
	CodeWeakPassword                    = "WEAK_PASSWORD"
	CodeDeviceLimitReached              = "DEVICE_LIMIT_REACHED"
	CodeInternal                        = "INTERNAL_ERROR"
)

// DomainError is a business failure with a stable code, a human message
// and the HTTP status it maps to.
type DomainError struct {
	Code    string
	Message string
	Status  int
	cause   error
}

func (e *DomainError) Error() string { return e.Code + ": " + e.Message }

func (e *DomainError) Unwrap() error { return e.cause }

func newError(status int, code, message string, cause error) *DomainError {
	return &DomainError{Code: code, Message: message, Status: status, cause: cause}
}

var (
	errUserNotFound = func() *DomainError {
		return newError(http.StatusNotFound, CodeUserNotFound, "User not found.", nil)
	}
	errPlanNotFound = func() *DomainError {
		return newError(http.StatusNotFound, CodePlanNotFound, "Plan not found.", nil)
	}
	errPlanInactive = func() *DomainError {
		return newError(http.StatusUnprocessableEntity, CodePlanInactive, "Plan is not active.", nil)
	}
	errAlreadyActive = func() *DomainError {
		return newError(http.StatusConflict, CodeSubscriptionAlreadyActive, "User already has an active subscription.", nil)
	}
	errNoSubscription = func() *DomainError {
		return newError(http.StatusNotFound, CodeSubscriptionNotFound, "User has no live subscription.", nil)
	}
	errSubscriptionNotActive = func() *DomainError {
		return newError(http.StatusUnprocessableEntity, CodeSubscriptionNotActive, "Access can only be issued for an active, unexpired subscription.", nil)
	}
	errNoNode = func() *DomainError {
		return newError(http.StatusServiceUnavailable, CodeNoNodeAvailable, "No node is available to issue access.", nil)
	}
	errResetChannel = func() *DomainError {
		return newError(http.StatusUnprocessableEntity, CodePasswordResetChannelUnavailable, "User has no email to send a reset link to.", nil)
	}
	errResetToken = func() *DomainError {
		return newError(http.StatusBadRequest, CodePasswordResetTokenInvalid, "Reset link is invalid, expired or already used.", nil)
	}
	errWeakPassword = func() *DomainError {
		return newError(http.StatusBadRequest, CodeWeakPassword, "Password must be at least 10 characters.", nil)
	}
)

func wrapInternal(code, message string, cause error) *DomainError {
	return newError(http.StatusInternalServerError, code, message, cause)
}

// AsDomainError returns err as a *DomainError, or wraps it as INTERNAL_ERROR.
func AsDomainError(err error) *DomainError {
	var de *DomainError
	if errors.As(err, &de) {
		return de
	}
	return wrapInternal(CodeInternal, "Internal error.", err)
}
