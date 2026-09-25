import 'package:dio/dio.dart';

import '../logging/app_logger.dart';

class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required this.dio,
    required this.readAccessToken,
    required this.refreshSession,
    required this.onAuthLost,
  });

  final Dio dio;
  final Future<String?> Function() readAccessToken;
  final Future<bool> Function() refreshSession;
  final Future<void> Function() onAuthLost;

  static const _retryFlag = 'wb_retried';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_isPublic(options.path)) {
      handler.next(options);
      return;
    }
    // Real-device bug this fixes: the whole app going permanently
    // unresponsive — every screen stuck loading forever, nothing ever
    // resolves, not even a fresh retry. Root cause: this is a
    // QueuedInterceptor, which processes every request's onRequest/onError
    // strictly in order across the ENTIRE Dio client — if `readAccessToken`
    // (a flutter_secure_storage platform-channel read) never completes on
    // some device (see session_controller.dart's own doc comment on
    // Android Keystore reads that can hang rather than cleanly returning
    // null/throwing), this handler never calls `handler.next()`, which
    // wedges the queue itself, not just this one request — every OTHER
    // request already queued or queued after it is then stuck forever too,
    // and no per-call `.timeout()` on the caller's side can ever unstick
    // it, since the caller's Future abandoning its wait doesn't tell this
    // interceptor to stop waiting. Bounding the read here, at the one
    // place that can actually wedge the shared queue, is what makes a
    // stuck platform channel degrade into "this one request proceeds
    // unauthenticated (then 401s and goes through the normal refresh/
    // auth-lost path)" instead of "the entire app is dead until restart."
    String? token;
    try {
      token = await readAccessToken().timeout(const Duration(seconds: 8));
    } catch (e) {
      AppLogger.warn('readAccessToken stalled/failed, proceeding without it: $e');
    }
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final status = err.response?.statusCode;
    final alreadyRetried = err.requestOptions.extra[_retryFlag] == true;
    final isAuthCall = _isAuthPath(err.requestOptions.path);

    if (status != 401 || alreadyRetried || isAuthCall) {
      handler.next(err);
      return;
    }

    AppLogger.debug('Access token rejected, attempting refresh');
    final refreshed = await refreshSession();
    if (!refreshed) {
      // Real-device bug this fixes: an access token expiring naturally
      // during ordinary use (nothing wrong — Core's own ~15min lifetime)
      // triggers this exact path on the very next request, and used to
      // force-log-out the whole session if the refresh call itself
      // happened to hit a network hiccup — indistinguishable here from
      // Core genuinely rejecting the refresh token. refreshSession()
      // (SessionController.refreshTokens) now makes that distinction
      // itself and already ends the session when it's a real rejection
      // — calling onAuthLost() again here unconditionally would either
      // be a harmless duplicate (real rejection: already logged out) or
      // the actual bug (transient failure: logs the user out anyway).
      // Neither case needs it called from here at all anymore.
      handler.next(err);
      return;
    }

    final token = await readAccessToken();
    final request = err.requestOptions;
    request.extra[_retryFlag] = true;
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    try {
      final response = await dio.fetch<dynamic>(request);
      handler.resolve(response);
    } catch (retryError) {
      if (retryError is DioException) {
        handler.next(retryError);
      } else {
        handler.next(err);
      }
    }
  }

  bool _isPublic(String path) {
    return path.contains('/auth/login') ||
        path.contains('/auth/register') ||
        path.contains('/auth/refresh') ||
        path.contains('/auth/forgot');
  }

  bool _isAuthPath(String path) {
    return path.contains('/auth/login') ||
        path.contains('/auth/register') ||
        path.contains('/auth/refresh') ||
        path.contains('/auth/logout');
  }
}
