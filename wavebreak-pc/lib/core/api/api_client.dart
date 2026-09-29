import 'dart:async';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:uuid/uuid.dart';

import '../env/app_env.dart';
import '../errors/app_exception.dart';
import '../errors/error_mapper.dart';
import '../logging/app_logger.dart';
import 'auth_interceptor.dart';

typedef TokenRefresh = Future<bool> Function();
typedef OnAuthLost = Future<void> Function();

class ApiClient {
  ApiClient({
    required this.readAccessToken,
    required this.refreshSession,
    required this.onAuthLost,
    Dio? dio,
    ErrorMapper? mapper,
  }) : mapper = mapper ?? const ErrorMapper() {
    final options = BaseOptions(
      baseUrl: currentBaseUrl,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 12),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        // What this build's engines can run; Core only hands out links a
        // client declares here (e.g. the obfuscated Hysteria2 listener).
        // hysteria-pin: Hysteria2 verified by certificate pin with a
        // neutral SNI — Android's Xray does that; Windows' sing-box path
        // doesn't, so it keeps the plain link.
        'X-Wavebreak-Features': [
          'hysteria-obfs',
          'email-verification',
          if (Platform.isAndroid) 'hysteria-pin',
        ].join(','),
      },
    );
    _dio = dio ?? Dio(options);
    // Bug 1: /auth/refresh must never pass through AuthInterceptor. The
    // interceptor awaits the refresh from inside its own onError; when the
    // refresh itself failed (e.g. 401 "reuse detected"), that failure was
    // routed into the same interceptor and never delivered, wedging every
    // later 401 for the rest of the process (confirmed: server answered
    // 401 at 08:41:19, the app never logged the outcome).
    _authDio = Dio(options);
    _authDio.interceptors.add(_loggingInterceptor());
    _dio.interceptors.add(
      AuthInterceptor(
        dio: _dio,
        readAccessToken: readAccessToken,
        refreshSession: refreshSession,
        onAuthLost: onAuthLost,
      ),
    );
    _dio.interceptors.add(_loggingInterceptor());
  }

  static Interceptor _loggingInterceptor() => InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers['X-Request-Id'] ??= const Uuid().v4();
          AppLogger.debug('${options.method} ${options.path}');
          handler.next(options);
        },
        onError: (error, handler) {
          AppLogger.warn(
            'HTTP ${error.response?.statusCode ?? '-'} ${error.requestOptions.path}',
          );
          handler.next(error);
        },
      );

  /// Where Core is reached, best first: the Moscow relay (when configured,
  /// see [AppEnv.coreRelayUrl]), then Core directly. Shared by every
  /// ApiClient in the process.
  static List<String> _baseUrls = [
    if (AppEnv.coreRelayUrl.isNotEmpty)
      '${AppEnv.coreRelayUrl}${AppEnv.apiPrefix}',
    '${AppEnv.coreBaseUrl}${AppEnv.apiPrefix}',
  ];
  static int _activeBase = 0;
  static DateTime? _fellBackAt;

  @visibleForTesting
  static void debugSetBaseUrls(List<String> urls) {
    _baseUrls = urls;
    _activeBase = 0;
    _fellBackAt = null;
  }

  /// After this long on a fallback, the preferred route is tried again
  /// (the relay may have been down only briefly).
  static const _fallbackHold = Duration(minutes: 10);

  static String get currentBaseUrl {
    final since = _fellBackAt;
    if (_activeBase != 0 &&
        since != null &&
        DateTime.now().difference(since) > _fallbackHold) {
      _activeBase = 0;
      _fellBackAt = null;
    }
    return _baseUrls[_activeBase];
  }

  /// Moves every later request (and this request's own retries) off
  /// [failedBase] to the next route. Called when it gave no answer, or its
  /// relay couldn't reach Core. A no-op when another request already moved
  /// off it — parallel failures (Home loads four things at once) must not
  /// each switch and so flip the route back.
  void _switchBase(String failedBase) {
    if (_baseUrls.length < 2 || _baseUrls[_activeBase] != failedBase) {
      _syncBase();
      return;
    }
    _activeBase = (_activeBase + 1) % _baseUrls.length;
    _fellBackAt = _activeBase == 0 ? null : DateTime.now();
    _dio.options.baseUrl = _baseUrls[_activeBase];
    _authDio.options.baseUrl = _baseUrls[_activeBase];
    AppLogger.warn('Core route switched to ${_baseUrls[_activeBase]}');
  }

  void _syncBase() {
    final url = currentBaseUrl;
    if (_dio.options.baseUrl != url) _dio.options.baseUrl = url;
    if (_authDio.options.baseUrl != url) _authDio.options.baseUrl = url;
  }

  /// The relay answered but couldn't reach Core behind it. 502/503 mean the
  /// request never got to Core, so it is safe to resend
  /// even a POST; 504 (Core too slow) may have been processed.
  static int? _gatewayStatus(Object error, String base) {
    if (error is! DioException || base == _baseUrls.last) return null;
    final code = error.response?.statusCode;
    return (code == 502 || code == 503 || code == 504) ? code : null;
  }

  late final Dio _dio;
  late final Dio _authDio;
  final ErrorMapper mapper;
  final Future<String?> Function() readAccessToken;
  final TokenRefresh refreshSession;
  final OnAuthLost onAuthLost;

  Dio get raw => _dio;

  // Real-device bug this fixes: on this particular mobile connection,
  // individual requests to api.wavebreak.com.tr occasionally fail at the
  // TCP/TLS level with no HTTP response at all (confirmed via on-device
  // logcat: "[WB][warn] HTTP - /me" — the "-" is `error.response
  // ?.statusCode`, meaning Dio never got a response to have a status
  // code from) while the exact same endpoint, hit seconds later or from
  // a different network path (a desktop `curl`, or the user turning on a
  // third-party VPN), answers instantly and correctly. That's carrier/
  // path interference on individual connections, not the server or this
  // client being slow — and it explains "press sign in a second time and
  // it works" perfectly: a retry on a fresh connection is exactly what a
  // second tap already was doing manually. `get` retries by default
  // (always safe/idempotent); `post`/`patch`/`delete` don't unless the
  // caller explicitly says the request is safe to retry (idempotent by
  // the API's own contract, not just "GET" by HTTP convention) — login
  // and register both pass this from core_api.dart.
  static const _maxConnectionRetries = 2;

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? query,
    T Function(dynamic data)? parse,
  }) {
    return _run(() => _dio.get<dynamic>(path, queryParameters: query), parse,
        retries: _maxConnectionRetries);
  }

  Future<T> post<T>(
    String path, {
    Object? body,
    T Function(dynamic data)? parse,
    CancelToken? cancelToken,
    bool retryOnConnectionError = false,
  }) {
    return _run(
        () => _dio.post<dynamic>(path, data: body, cancelToken: cancelToken),
        parse,
        retries: retryOnConnectionError ? _maxConnectionRetries : 0);
  }

  /// POST that bypasses [AuthInterceptor] entirely — only for
  /// `/auth/refresh`, which the interceptor itself awaits.
  Future<T> postWithoutAuth<T>(
    String path, {
    Object? body,
    T Function(dynamic data)? parse,
  }) {
    return _run(() => _authDio.post<dynamic>(path, data: body), parse);
  }

  Future<T> patch<T>(
    String path, {
    Object? body,
    T Function(dynamic data)? parse,
  }) {
    return _run(() => _dio.patch<dynamic>(path, data: body), parse);
  }

  Future<T> delete<T>(
    String path, {
    T Function(dynamic data)? parse,
  }) {
    return _run(() => _dio.delete<dynamic>(path), parse);
  }

  /// True only for a failure where no real HTTP response ever came back
  /// (`error.response == null`) — never for an actual 4xx/5xx, which
  /// retrying would be wrong or pointless for. Real-device confirmation
  /// this list needs to include receive/send timeouts, not just
  /// connection-establishment failures: logcat on this exact class of bug
  /// showed `DioExceptionType.receiveTimeout` (TCP/TLS connected fine,
  /// the response itself just never arrived within the 20s budget) for
  /// `/me` and `/plans`, which the first version of this check — only
  /// `connectionError`/`connectionTimeout`/`unknown` — silently let
  /// through without ever retrying.
  bool _isRetryableConnectionError(Object error) {
    // From this class's own per-attempt `.timeout()` wrapper (see
    // `_retryAttemptTimeout`) — a plain Dart TimeoutException, not a
    // DioException, so it needs its own check here or every attempt
    // past the first would silently stop retrying the instant this
    // class's own timeout (rather than Dio's) was what actually fired.
    if (error is TimeoutException) return true;
    if (error is! DioException) return false;
    return error.response == null &&
        (error.type == DioExceptionType.connectionError ||
            error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.receiveTimeout ||
            error.type == DioExceptionType.sendTimeout ||
            error.type == DioExceptionType.unknown);
  }

  /// Each individual attempt's own budget when retries are enabled —
  /// deliberately shorter than BaseOptions' global 20s receiveTimeout.
  /// With that 20s applying per attempt, 2 retries could take up to ~60s
  /// end to end (3 attempts × 20s + backoff), blowing well past every
  /// caller's own outer timeout (login_screen's 25s, data_providers.dart's
  /// 26s `_withTimeout`) before a retry ever gets a chance to land —
  /// making the retry logic itself the reason nothing ever completed in
  /// time. 5s (was 7s — real-device logcat showed Home's own parallel
  /// subscription/locations/devices/plans fetches, hit by the same
  /// carrier interference at once, all taking the full 3-attempt budget
  /// before falling back to cache — 21s felt like "stuck", not
  /// "loading"): a genuinely blocked path doesn't get through by waiting
  /// longer per attempt, so this trims worst-case latency to ~15s without
  /// meaningfully reducing how often a retry actually succeeds.
  static const _retryAttemptTimeout = Duration(seconds: 5);

  Future<T> _run<T>(
    Future<Response<dynamic>> Function() request,
    T Function(dynamic data)? parse, {
    int retries = 0,
  }) async {
    var attempt = 0;
    var resent = false;
    while (true) {
      _syncBase();
      final base = _dio.options.baseUrl;
      try {
        final response = retries > 0
            ? await request().timeout(_retryAttemptTimeout)
            : await request();
        final data = response.data;
        if (parse != null) return parse(data);
        return data as T;
      } catch (error) {
        // No answer on this route (or the relay couldn't reach Core): the
        // next attempt — and every later request — takes the other one.
        final gateway = _gatewayStatus(error, base);
        if (gateway != null || _isRetryableConnectionError(error)) {
          _switchBase(base);
        }
        if ((gateway == 502 || gateway == 503) && !resent) {
          resent = true;
          continue;
        }
        if (attempt < retries && _isRetryableConnectionError(error)) {
          attempt++;
          AppLogger.warn(
              'Connection error, retrying ($attempt/$retries): $error');
          await Future<void>.delayed(Duration(milliseconds: 600 * attempt));
          continue;
        }
        throw mapper.map(error);
      }
    }
  }
}

bool isUnauthorized(Object error) {
  return error is AppException && error.kind == AppErrorKind.sessionExpired;
}
