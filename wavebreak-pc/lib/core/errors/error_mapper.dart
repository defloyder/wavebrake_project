import 'dart:io';

import 'package:dio/dio.dart';

import 'app_exception.dart';

/// Maps transport/HTTP failures onto [AppException]. Core's error body is
/// `{"code": "...", "error": "..."}`, but `code` isn't a stable enum in
/// every case — some responses use a real error code
/// (`DEVICE_LIMIT_REACHED`), others just repeat the human message
/// (`"active subscription is required"`). Matching is done on lowercased
/// substrings of both fields rather than exact equality so either shape
/// still maps correctly.
class ErrorMapper {
  const ErrorMapper();

  AppException map(Object error) {
    if (error is AppException) return error;

    if (error is SocketException) {
      return AppException(AppErrorKind.noInternet);
    }

    if (error is DioException) {
      final type = error.type;
      if (type == DioExceptionType.connectionError ||
          type == DioExceptionType.connectionTimeout ||
          error.error is SocketException) {
        return AppException(AppErrorKind.noInternet);
      }
      if (type == DioExceptionType.receiveTimeout ||
          type == DioExceptionType.sendTimeout) {
        return AppException(AppErrorKind.unavailable);
      }

      final status = error.response?.statusCode;
      final text = _extractText(error.response?.data);

      if (status == 401) {
        // login/register/refresh never send an Authorization header — a
        // 401 from one of those can only mean bad credentials, never an
        // *expired* session (there was no session to expire). Only a 401
        // on a request that actually carried a token is a real session
        // expiry. Getting this wrong is exactly how a plain wrong-password
        // login attempt ends up telling the user their session expired.
        final headers = error.requestOptions.headers;
        final hadAuthHeader =
            headers.containsKey('Authorization') || headers.containsKey('authorization');
        if (!hadAuthHeader) {
          return AppException(AppErrorKind.invalidCredentials, statusCode: status);
        }
        return AppException(AppErrorKind.sessionExpired, statusCode: status);
      }
      // Register-specific failures. Scoped to the register path for the
      // same reason the 400/credentials check below is scoped to auth
      // paths: "already exists" or a password-length complaint from some
      // unrelated endpoint must never get relabeled as a signup error.
      if (_isRegisterPath(error.requestOptions.path)) {
        if (status == 409 || text.contains('already exists') || text.contains('already registered')) {
          return AppException(AppErrorKind.emailTaken, statusCode: status);
        }
        if (status == 400 && (text.contains('password') || text.contains('characters'))) {
          return AppException(AppErrorKind.weakPassword, statusCode: status);
        }
      }
      if (text.contains('device_limit_reached')) {
        return AppException(AppErrorKind.deviceLimitReached, statusCode: status);
      }
      if (text.contains('traffic_limit_reached')) {
        return AppException(AppErrorKind.trafficLimitReached, statusCode: status);
      }
      if (status == 403 || text.contains('device_revoked')) {
        return AppException(AppErrorKind.accessDenied, statusCode: status);
      }
      if (text.contains('subscription') &&
          (text.contains('required') || text.contains('expired'))) {
        return AppException(
          text.contains('required')
              ? AppErrorKind.subscriptionRequired
              : AppErrorKind.subscriptionExpired,
          statusCode: status,
        );
      }
      if (status == 402) {
        return AppException(AppErrorKind.subscriptionExpired, statusCode: status);
      }
      if (text.contains('location_unavailable')) {
        return AppException(AppErrorKind.locationUnavailable, statusCode: status);
      }
      // Scoped to the auth paths on purpose — a generic 400 elsewhere in
      // the app (subscriptions, devices, grants, ...) whose message
      // happens to mention "credentials" for an unrelated reason must
      // never get relabeled as a wrong-password login error.
      if (status == 400 && text.contains('credentials') && _isAuthPath(error.requestOptions.path)) {
        return AppException(AppErrorKind.invalidCredentials, statusCode: status);
      }
      if (status != null && status >= 500) {
        return AppException(AppErrorKind.unavailable, statusCode: status);
      }
      return AppException(AppErrorKind.unavailable, statusCode: status);
    }

    return AppException(AppErrorKind.unavailable);
  }

  bool _isAuthPath(String path) {
    return path.contains('/auth/login') ||
        path.contains('/auth/register') ||
        path.contains('/auth/refresh');
  }

  bool _isRegisterPath(String path) => path.contains('/auth/register');

  /// Both `code` and `error` fields, lowercased and concatenated, so a
  /// single `.contains(...)` check matches whichever field actually
  /// carries the useful text.
  String _extractText(dynamic data) {
    if (data is! Map) return '';
    final code = data['code'];
    final err = data['error'];
    final parts = <String>[
      if (code is String) code,
      if (err is String) err,
      if (err is Map && err['code'] is String) err['code'] as String,
    ];
    return parts.join(' ').toLowerCase();
  }
}
