import '../i18n/app_strings.dart';

enum AppErrorKind {
  noInternet,
  unavailable,
  sessionExpired,
  subscriptionExpired,
  subscriptionRequired,
  locationUnavailable,
  connectionFailed,
  invalidCredentials,
  emailTaken,
  weakPassword,
  accessDenied,
  updateRequired,
  deviceLimitReached,
  trafficLimitReached,
  unsupportedProtocol,
  shareInvalid,
  shareOwnSubscription,
  // Email verification (Core answers with these codes).
  emailNotVerified,
  codeInvalid,
  codeExpired,
  codeTooManyAttempts,
  resendTooSoon,
  emailSendFailed,
  // Promo codes (Core POST /v1/promo-codes/check, PROMO_* codes).
  promoNotFound,
  promoExpired,
  promoNotStarted,
  promoExhausted,
  promoAlreadyUsed,
  promoNotApplicable,
  promoInactive,
  unknown,
}

class AppException implements Exception {
  AppException(this.kind, {this.message, this.statusCode});

  final AppErrorKind kind;
  final String? message;
  final int? statusCode;

  /// Localized, user-facing copy for this error. Prefer this over
  /// [userMessage] wherever an [AppStrings] instance is available.
  String localized(AppStrings s) {
    switch (kind) {
      case AppErrorKind.noInternet:
        return s.errNoInternet;
      case AppErrorKind.unavailable:
        return s.errUnavailable;
      case AppErrorKind.sessionExpired:
        return s.errSessionExpired;
      case AppErrorKind.subscriptionExpired:
        return s.errSubscriptionExpired;
      case AppErrorKind.subscriptionRequired:
        return s.errSubscriptionRequired;
      case AppErrorKind.locationUnavailable:
        return s.errLocationUnavailable;
      case AppErrorKind.connectionFailed:
        return s.errConnectionFailed;
      case AppErrorKind.invalidCredentials:
        return s.errInvalidCredentials;
      case AppErrorKind.emailTaken:
        return s.errEmailTaken;
      case AppErrorKind.weakPassword:
        return s.errWeakPassword;
      case AppErrorKind.accessDenied:
        return s.errAccessDenied;
      case AppErrorKind.updateRequired:
        return s.errUpdateRequired;
      case AppErrorKind.deviceLimitReached:
        return s.errDeviceLimitReached;
      case AppErrorKind.trafficLimitReached:
        return s.errTrafficLimitReached;
      case AppErrorKind.unsupportedProtocol:
        return s.errUnsupportedProtocol;
      case AppErrorKind.shareInvalid:
        return s.shareInvalid;
      case AppErrorKind.shareOwnSubscription:
        return s.shareOwnSubscription;
      case AppErrorKind.emailNotVerified:
        return s.errEmailNotVerified;
      case AppErrorKind.codeInvalid:
        return s.errCodeInvalid;
      case AppErrorKind.codeExpired:
        return s.errCodeExpired;
      case AppErrorKind.codeTooManyAttempts:
        return s.errCodeTooManyAttempts;
      case AppErrorKind.resendTooSoon:
        return s.errResendTooSoon;
      case AppErrorKind.emailSendFailed:
        return s.errEmailSendFailed;
      case AppErrorKind.promoNotFound:
        return s.errPromoNotFound;
      case AppErrorKind.promoExpired:
        return s.errPromoExpired;
      case AppErrorKind.promoNotStarted:
        return s.errPromoNotStarted;
      case AppErrorKind.promoExhausted:
        return s.errPromoExhausted;
      case AppErrorKind.promoAlreadyUsed:
        return s.errPromoAlreadyUsed;
      case AppErrorKind.promoNotApplicable:
        return s.errPromoNotApplicable;
      case AppErrorKind.promoInactive:
        return s.errPromoInactive;
      case AppErrorKind.unknown:
        return message ?? s.errUnknown;
    }
  }

  /// English fallback, used only where an [AppStrings] instance isn't
  /// conveniently available (e.g. non-widget code paths).
  String get userMessage => localized(kEnglishStrings);

  @override
  String toString() => 'AppException($kind)';
}
