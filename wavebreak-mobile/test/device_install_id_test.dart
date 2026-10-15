import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/core/api/api_client.dart';
import 'package:wavebreak/services/core_api/core_api.dart';

/// POST /me/devices like Core: an old Core refuses unknown fields (400),
/// a new one accepts install_id.
class _DevicesAdapter implements HttpClientAdapter {
  _DevicesAdapter({required this.knowsInstallId});

  final bool knowsInstallId;
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final body = Map<String, dynamic>.from(options.data as Map);
    bodies.add(body);
    final json = {'content-type': ['application/json']};
    if (body.containsKey('install_id') && !knowsInstallId) {
      return ResponseBody.fromString(
          jsonEncode({'error': 'invalid json body'}), 400,
          headers: json);
    }
    return ResponseBody.fromString(
        jsonEncode({
          'id': 'dev-1',
          'device_public_id': 'dev-1',
          'name': body['name'],
          'platform': body['platform'],
          'created_at': '2026-10-06T10:00:00Z',
          'updated_at': '2026-10-06T10:00:00Z',
        }),
        201,
        headers: json);
  }

  @override
  void close({bool force = false}) {}
}

CoreApi _api(_DevicesAdapter adapter) => CoreApi(ApiClient(
      readAccessToken: () async => 'token',
      refreshSession: () async => false,
      onAuthLost: () async {},
      dio: Dio(BaseOptions(baseUrl: 'https://core.test'))
        ..httpClientAdapter = adapter,
    ));

void main() {
  test('sends install_id to a Core that knows it', () async {
    final adapter = _DevicesAdapter(knowsInstallId: true);
    final d = await _api(adapter)
        .registerDevice(platform: 'android', name: 'Xiaomi', installId: 'abc');
    expect(d.id, 'dev-1');
    expect(adapter.bodies.single['install_id'], 'abc');
  });

  test('an older Core (400 on the unknown field) still registers', () async {
    final adapter = _DevicesAdapter(knowsInstallId: false);
    final d = await _api(adapter)
        .registerDevice(platform: 'android', name: 'Xiaomi', installId: 'abc');
    expect(d.id, 'dev-1');
    expect(adapter.bodies, hasLength(2));
    expect(adapter.bodies.last.containsKey('install_id'), isFalse);
  });
}
