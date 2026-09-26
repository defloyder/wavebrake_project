import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/core/api/auth_interceptor.dart';

/// Answers 401 unless the request carries `Bearer <validToken>`.
class _TokenCheckingAdapter implements HttpClientAdapter {
  _TokenCheckingAdapter(this.validToken);

  String validToken;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    final ok = options.headers['Authorization'] == 'Bearer $validToken';
    return ResponseBody.fromString(
      jsonEncode(ok ? {'ok': true} : {'code': 'unauthorized'}),
      ok ? 200 : 401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(_TokenCheckingAdapter adapter, AuthInterceptor Function(Dio) make) {
  final dio = Dio(BaseOptions(baseUrl: 'https://core.test'))
    ..httpClientAdapter = adapter;
  dio.interceptors.add(make(dio));
  return dio;
}

void main() {
  test('failed refresh fails the request instead of hanging (bug 1)',
      () async {
    final adapter = _TokenCheckingAdapter('fresh');
    final dio = _dio(
      adapter,
      (d) => AuthInterceptor(
        dio: d,
        readAccessToken: () async => 'stale',
        // Refresh through the SAME Dio, answered with 401 — the exact
        // production shape that used to deadlock the error queue.
        refreshSession: () async {
          try {
            await d.post<dynamic>('/auth/refresh');
            return true;
          } on DioException {
            return false;
          }
        },
        onAuthLost: () async {},
      ),
    );

    await expectLater(
      dio.get<dynamic>('/me').timeout(const Duration(seconds: 5)),
      throwsA(isA<DioException>()
          .having((e) => e.response?.statusCode, 'status', 401)),
    );
    // A second request after the failure must not be wedged either.
    await expectLater(
      dio.get<dynamic>('/locations').timeout(const Duration(seconds: 5)),
      throwsA(isA<DioException>()),
    );
  });

  test('parallel 401s share one refresh, then all succeed', () async {
    var token = 'stale';
    var refreshCalls = 0;
    Future<bool>? inFlight;
    final adapter = _TokenCheckingAdapter('fresh');
    final dio = _dio(
      adapter,
      (d) => AuthInterceptor(
        dio: d,
        readAccessToken: () async => token,
        refreshSession: () => inFlight ??= () async {
          refreshCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          token = 'fresh';
          return true;
        }(),
        onAuthLost: () async {},
      ),
    );

    final results = await Future.wait([
      for (final p in ['/me', '/locations', '/subscriptions/current', '/me/usage'])
        dio.get<dynamic>(p),
    ]).timeout(const Duration(seconds: 5));

    expect(results.map((r) => r.statusCode), everyElement(200));
    expect(refreshCalls, 1);
  });

  test('401 after someone else already rotated the token retries without refreshing',
      () async {
    var token = 'stale';
    var refreshCalls = 0;
    final adapter = _TokenCheckingAdapter('fresh');
    final dio = _dio(
      adapter,
      (d) => AuthInterceptor(
        dio: d,
        readAccessToken: () async {
          final current = token;
          token = 'fresh'; // rotated by another caller right after this read
          return current;
        },
        refreshSession: () async {
          refreshCalls++;
          return true;
        },
        onAuthLost: () async {},
      ),
    );

    final response = await dio.get<dynamic>('/me');
    expect(response.statusCode, 200);
    expect(refreshCalls, 0);
  });
}
