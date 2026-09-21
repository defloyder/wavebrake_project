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
    final token = await readAccessToken();
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
      await onAuthLost();
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
