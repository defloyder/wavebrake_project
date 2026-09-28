import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/core/api/api_client.dart';

/// A tiny HTTP server that answers every request with [status] and counts
/// what it saw.
class _Server {
  _Server(this.status);
  int status;
  final paths = <String>[];
  late HttpServer _server;

  String get base => 'http://127.0.0.1:${_server.port}/v1';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      paths.add('${req.method} ${req.uri.path}');
      req.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'ok': status == 200}));
      await req.response.close();
    });
  }

  Future<void> close() => _server.close(force: true);
}

ApiClient _client() => ApiClient(
      readAccessToken: () async => null,
      refreshSession: () async => false,
      onAuthLost: () async {},
    );

void main() {
  late _Server relay;
  late _Server core;

  setUp(() async {
    relay = _Server(200);
    core = _Server(200);
    await relay.start();
    await core.start();
    ApiClient.debugSetBaseUrls([relay.base, core.base]);
  });

  tearDown(() async {
    await relay.close();
    await core.close();
  });

  test('uses the relay first', () async {
    final data = await _client().get<Map<String, dynamic>>('/me');
    expect(data['ok'], true);
    expect(relay.paths, ['GET /v1/me']);
    expect(core.paths, isEmpty);
  });

  test('a relay that cannot reach Core (502) is resent to Core, also a POST',
      () async {
    relay.status = 502;
    final client = _client();
    final data =
        await client.post<Map<String, dynamic>>('/me/access', body: {});
    expect(data['ok'], true);
    expect(relay.paths, ['POST /v1/me/access']);
    expect(core.paths, ['POST /v1/me/access']);
    // Sticky: the next request goes straight to Core.
    await client.get<Map<String, dynamic>>('/me');
    expect(relay.paths.length, 1);
    expect(core.paths.last, 'GET /v1/me');
  });

  test('a dead relay: retried GET lands on Core', () async {
    final deadPort = relay._server.port;
    await relay.close();
    ApiClient.debugSetBaseUrls(['http://127.0.0.1:$deadPort/v1', core.base]);
    final data = await _client().get<Map<String, dynamic>>('/locations');
    expect(data['ok'], true);
    expect(core.paths, ['GET /v1/locations']);
  });

  test('parallel failures switch the route once, not back and forth', () async {
    relay.status = 502;
    final client = _client();
    await Future.wait([
      for (var i = 0; i < 4; i++) client.get<Map<String, dynamic>>('/me'),
    ]);
    expect(core.paths.length, 4);
    await client.get<Map<String, dynamic>>('/me');
    expect(relay.paths.length, 4, reason: 'no request went back to the relay');
    expect(core.paths.length, 5);
  });

  test('a real error from Core (404) is not a route problem', () async {
    relay.status = 404;
    await expectLater(
        _client().get<Map<String, dynamic>>('/nope'), throwsA(anything));
    expect(core.paths, isEmpty);
  });
}
