import 'dart:async';

import 'package:dio/dio.dart';
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
    _dio = dio ??
        Dio(
          BaseOptions(
            baseUrl: '${AppEnv.coreBaseUrl}${AppEnv.apiPrefix}',
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 20),
            sendTimeout: const Duration(seconds: 12),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
          ),
        );
    _dio.interceptors.add(
      AuthInterceptor(
        dio: _dio,
        readAccessToken: readAccessToken,
        refreshSession: refreshSession,
        onAuthLost: onAuthLost,
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
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
      ),
    );
  }

  late final Dio _dio;
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
  /// 20s `_withTimeout`) before a retry ever gets a chance to land —
  /// making the retry logic itself the reason nothing ever completed in
  /// time. Bounding each attempt to 7s means 3 attempts + backoff fits
  /// comfortably inside those outer budgets instead of racing past them.
  static const _retryAttemptTimeout = Duration(seconds: 7);

  Future<T> _run<T>(
    Future<Response<dynamic>> Function() request,
    T Function(dynamic data)? parse, {
    int retries = 0,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        final response = retries > 0
            ? await request().timeout(_retryAttemptTimeout)
            : await request();
        final data = response.data;
        if (parse != null) return parse(data);
        return data as T;
      } catch (error) {
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
