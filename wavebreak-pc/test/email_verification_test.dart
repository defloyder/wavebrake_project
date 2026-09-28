import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/core/api/api_client.dart';
import 'package:wavebreak/core/errors/app_exception.dart';
import 'package:wavebreak/services/core_api/core_api.dart';
import 'package:wavebreak/services/core_api/models.dart';

/// Answers each path with a fixed status and JSON body, and records the
/// requests (path, body, features header).
class _Core {
  _Core(this.routes);
  final Map<String, (int, Map<String, dynamic>)> routes;
  final seen = <(String, Map<String, dynamic>, String?)>[];
  late HttpServer _server;

  String get base => 'http://127.0.0.1:${_server.port}/v1';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      final path = req.uri.path.replaceFirst('/v1', '');
      seen.add((
        path,
        body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(body) as Map<String, dynamic>,
        req.headers.value('X-Wavebreak-Features'),
      ));
      final (status, json) = routes[path] ?? (404, {'error': 'not found'});
      req.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(json));
      await req.response.close();
    });
  }

  Future<void> close() => _server.close(force: true);
}

CoreApi _api() => CoreApi(ApiClient(
      readAccessToken: () async => null,
      refreshSession: () async => false,
      onAuthLost: () async {},
    ));

void main() {
  late _Core core;
  tearDown(() => core.close());

  Future<void> serve(Map<String, (int, Map<String, dynamic>)> routes) async {
    core = _Core(routes);
    await core.start();
    ApiClient.debugSetBaseUrls([core.base]);
  }

  test(
      'sign-up that needs a code: emailNotVerified, and the app says it can verify',
      () async {
    await serve({
      '/auth/register': (
        201,
        {
          'user': {'id': 'u'},
          'verification_required': true,
          'code_sent': true
        }
      ),
    });
    await expectLater(
      _api().register(
          email: 'a@b.c', password: 'long-password-1', language: 'ru'),
      throwsA(isA<AppException>()
          .having((e) => e.kind, 'kind', AppErrorKind.emailNotVerified)
          .having((e) => e.message, 'message', 'sent')),
    );
    final (path, body, features) = core.seen.single;
    expect(path, '/auth/register');
    expect(body['language'], 'ru');
    expect(features, contains('email-verification'));
  });

  test('code not sent is reported to the screen', () async {
    await serve({
      '/auth/register': (
        201,
        {'verification_required': true, 'code_sent': false}
      ),
    });
    await expectLater(
      _api().register(email: 'a@b.c', password: 'long-password-1'),
      throwsA(
          isA<AppException>().having((e) => e.message, 'message', 'not_sent')),
    );
  });

  test('old-style sign-up still returns tokens', () async {
    await serve({
      '/auth/register': (
        201,
        {
          'user': {'id': 'u'},
          'tokens': {'access_token': 'a', 'refresh_token': 'r'}
        }
      ),
    });
    final tokens =
        await _api().register(email: 'a@b.c', password: 'long-password-1');
    expect(tokens.accessToken, 'a');
  });

  test('login of an unconfirmed account maps to emailNotVerified', () async {
    await serve({
      '/auth/login': (
        403,
        {'code': 'email_not_verified', 'error': 'email address is not verified'}
      ),
    });
    await expectLater(
      _api().login(email: 'a@b.c', password: 'x'),
      throwsA(isA<AppException>()
          .having((e) => e.kind, 'kind', AppErrorKind.emailNotVerified)),
    );
  });

  test('code errors are told apart', () async {
    final cases = {
      'invalid_code': AppErrorKind.codeInvalid,
      'code_expired': AppErrorKind.codeExpired,
      'too_many_attempts': AppErrorKind.codeTooManyAttempts,
    };
    for (final entry in cases.entries) {
      await serve({
        '/auth/email/verify': (
          entry.value == AppErrorKind.codeTooManyAttempts ? 429 : 400,
          {'code': entry.key, 'error': entry.key}
        ),
      });
      await expectLater(
        _api().verifyEmail(email: 'a@b.c', code: '123456'),
        throwsA(isA<AppException>().having((e) => e.kind, 'kind', entry.value)),
        reason: entry.key,
      );
      await core.close();
    }
    await serve({
      '/auth/email/verify': (
        200,
        {'access_token': 'a2', 'refresh_token': 'r2'}
      ),
    });
    final TokenPair tokens =
        await _api().verifyEmail(email: 'a@b.c', code: '123456');
    expect(tokens.refreshToken, 'r2');
  });

  test('profile carries the verification state', () {
    final p = UserProfile.fromJson({
      'id': 'u',
      'email': 'a@b.c',
      'email_verified': false,
      'email_verification_available': true,
    });
    expect(p.emailVerified, false);
    expect(p.emailVerificationAvailable, true);
    final roundTrip = UserProfile.fromJson(p.toJson());
    expect(roundTrip.emailVerified, false);
    expect(
        UserProfile.fromJson({'id': 'u', 'email': 'x'}).emailVerified, isNull);
  });
}
