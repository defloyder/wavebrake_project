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
