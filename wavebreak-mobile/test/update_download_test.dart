import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/services/update/resumable_download.dart';
import 'package:wavebreak/services/update/update_service.dart';

/// A file server that misbehaves like a throttling carrier: [breakAfter]
/// bytes into each response it either closes the connection or goes
/// silent, depending on [stall]. Raw sockets, so it can cut a response
/// mid-body the way a carrier does.
class _FlakyServer {
  _FlakyServer(this.body,
      {this.breakAfter, this.stall = false, this.ranges = true});

  final Uint8List body;
  int? breakAfter;
  final bool stall;
  final bool ranges;
  final requests = <String?>[];
  final _open = <Socket>[];
  late ServerSocket _server;

  String get url => 'http://127.0.0.1:${_server.port}/app.apk';

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((socket) {
      _open.add(socket);
      final head = StringBuffer();
      late StreamSubscription<Uint8List> sub;
      sub = socket.listen((data) {
        head.write(latin1.decode(data));
        if (!head.toString().contains('\r\n\r\n')) return;
        sub.onData(null);
        _respond(socket, head.toString());
      }, onError: (_) {});
    });
  }

  Future<void> _respond(Socket socket, String head) async {
    final range =
        RegExp(r'^range: *(.+?)\r$', multiLine: true, caseSensitive: false)
            .firstMatch(head)
            ?.group(1);
    requests.add(range);
    var start = 0;
    final m = RegExp(r'bytes=(\d+)-').firstMatch(range ?? '');
    final headers = StringBuffer();
    if (ranges && m != null) {
      start = int.parse(m.group(1)!);
      headers
        ..write('HTTP/1.1 206 Partial Content\r\n')
        ..write(
            'Content-Range: bytes $start-${body.length - 1}/${body.length}\r\n');
    } else {
      headers.write('HTTP/1.1 200 OK\r\n');
    }
    headers
      ..write('Content-Length: ${body.length - start}\r\n')
      ..write('Connection: close\r\n\r\n');
    socket.add(latin1.encode(headers.toString()));
    final cut = breakAfter;
    if (cut == null || start + cut >= body.length) {
      socket.add(body.sublist(start));
      await socket.flush();
      await socket.close();
      return;
    }
    socket.add(body.sublist(start, start + cut));
    await socket.flush();
    if (stall) return; // silent, connection open
    socket.destroy();
  }

  Future<void> close() async {
    for (final s in _open) {
      s.destroy();
    }
    await _server.close();
  }
}

Uint8List _payload(int n) =>
    Uint8List.fromList(List<int>.generate(n, (i) => (i * 31 + 7) & 0xff));

ResumableDownloader _downloader(
        {Duration stall = const Duration(seconds: 5)}) =>
    ResumableDownloader(
      dio: Dio(BaseOptions(receiveTimeout: stall)),
      stallTimeout: stall,
      retryDelay: Duration.zero,
    );

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('wb-dl'));
  tearDown(() async => dir.delete(recursive: true));

  test('resumes after the connection drops mid-file', () async {
    final body = _payload(300000);
    final server = _FlakyServer(body, breakAfter: 70000);
    await server.start();
    final path = '${dir.path}/app.apk';
    await _downloader().download([server.url], path);
    await server.close();
    expect(await File(path).readAsBytes(), body);
    expect(server.requests.first, isNull);
    expect(server.requests.skip(1), everyElement(startsWith('bytes=')));
    expect(server.requests.length, 5); // 70k per connection
    expect(dir.listSync().length, 1, reason: 'no .part left behind');
  });

  test('a silent (stalled) connection is abandoned and resumed', () async {
    final body = _payload(200000);
    final server = _FlakyServer(body, breakAfter: 120000, stall: true);
    await server.start();
    final path = '${dir.path}/app.apk';
    await _downloader(stall: const Duration(milliseconds: 400))
        .download([server.url], path);
    await server.close();
    expect(await File(path).readAsBytes(), body);
    expect(server.requests, [null, 'bytes=120000-']);
  });

  test('a server that ignores Range restarts the file cleanly', () async {
    final body = _payload(100000);
    final server = _FlakyServer(body, ranges: false);
    await server.start();
    final path = '${dir.path}/app.apk';
    // A stale partial from an earlier attempt.
    final stale = ResumableDownloader.partPathFor(path, server.url);
    await File(stale).writeAsBytes(List<int>.filled(5000, 1));
    await _downloader().download([server.url], path);
    await server.close();
    expect(await File(path).readAsBytes(), body);
  });

  test('moves to the next URL when one never delivers', () async {
    final body = _payload(50000);
    final dead = _FlakyServer(body, breakAfter: 0);
    final good = _FlakyServer(body);
    await dead.start();
    await good.start();
    final path = '${dir.path}/app.apk';
    var lastProgress = 0.0;
    await _downloader().download([dead.url, good.url], path,
        onProgress: (r, t) => lastProgress = r / t);
    await dead.close();
    await good.close();
    expect(await File(path).readAsBytes(), body);
    expect(dead.requests.length, 4); // maxFailuresPerUrl
    expect(lastProgress, 1);
  });

  group('manifest', () {
    final info = UpdateInfo.fromJson({
      'versionCode': 26,
      'versionName': '1.2.0',
      'url': 'https://dl.example/universal.apk',
      'mirrors': [
        'https://site.example/universal.apk',
        'http://insecure/x.apk'
      ],
      'abis': {
        'arm64-v8a': [
          'https://dl.example/arm64.apk',
          'https://site.example/arm64.apk'
        ],
        'armeabi-v7a': 'https://dl.example/v7a.apk',
      },
    });

    test('prefers the device ABI, then universal and mirrors', () {
      expect(info.downloadUrls(['arm64-v8a', 'armeabi-v7a', 'armeabi']), [
        'https://dl.example/arm64.apk',
        'https://site.example/arm64.apk',
        'https://dl.example/universal.apk',
        'https://site.example/universal.apk',
      ]);
      expect(info.downloadUrls(['armeabi-v7a']).first,
          'https://dl.example/v7a.apk');
      expect(info.downloadUrls(['x86_64']), [
        'https://dl.example/universal.apk',
        'https://site.example/universal.apk'
      ]);
    });

    test('an old-style manifest still works', () {
      final old =
          UpdateInfo.fromJson({'versionCode': 20, 'url': 'https://a/b.apk'});
      expect(old.downloadUrls(['arm64-v8a']), ['https://a/b.apk']);
    });
  });
}
