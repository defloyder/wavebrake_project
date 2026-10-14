import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/core/errors/app_exception.dart';
import 'package:wavebreak/core/errors/error_mapper.dart';

DioException _err(int status, dynamic data, String type) {
  final options = RequestOptions(path: '/auth/refresh');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(
      requestOptions: options,
      statusCode: status,
      data: data,
      headers: Headers.fromMap({
        Headers.contentTypeHeader: [type]
      }),
    ),
  );
}

// 13.10: signed out on the PC right after turning the VPN off. A 403 page
// from Cloudflare or a relay is not Core rejecting the session.
void main() {
  final mapper = ErrorMapper();

  test('a non-JSON 403/401 from something in between is not a rejection', () {
    expect(mapper.map(_err(403, '<html>Attention Required</html>', 'text/html')).kind,
        AppErrorKind.unavailable);
    expect(mapper.map(_err(401, 'Unauthorized', 'text/plain')).kind,
        AppErrorKind.unavailable);
  });

  test('Core\'s own JSON 401 still ends the session', () {
    expect(
        mapper
            .map(_err(401, {'code': 'unauthorized', 'error': 'invalid token'},
                'application/json'))
            .kind,
        isNot(AppErrorKind.unavailable));
  });
}
