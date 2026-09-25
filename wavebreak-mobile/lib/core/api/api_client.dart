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

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? query,
    T Function(dynamic data)? parse,
  }) {
    return _run(() => _dio.get<dynamic>(path, queryParameters: query), parse);
  }

  Future<T> post<T>(
    String path, {
    Object? body,
    T Function(dynamic data)? parse,
  }) {
    return _run(() => _dio.post<dynamic>(path, data: body), parse);
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

  Future<T> _run<T>(
    Future<Response<dynamic>> Function() request,
    T Function(dynamic data)? parse,
  ) async {
    try {
      final response = await request();
      final data = response.data;
      if (parse != null) return parse(data);
      return data as T;
    } catch (error) {
      throw mapper.map(error);
    }
  }
}

bool isUnauthorized(Object error) {
  return error is AppException && error.kind == AppErrorKind.sessionExpired;
}
