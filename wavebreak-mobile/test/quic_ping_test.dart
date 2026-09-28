import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/services/core_api/models.dart';
import 'package:wavebreak/services/vpn/connection_test_service.dart';

/// Answers like a QUIC server: a Version Negotiation packet for an
/// unsupported version, echoing the client's connection IDs swapped.
Future<RawDatagramSocket> _fakeQuicServer({bool echoWrongId = false}) async {
  final server = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((event) {
    if (event != RawSocketEvent.read) return;
    final dg = server.receive();
    if (dg == null) return;
    final d = dg.data;
    final dcid = d.sublist(6, 14);
    final scid = d.sublist(15, 23);
    final reply = BytesBuilder()
      ..addByte(0x80)
      ..add([0, 0, 0, 0])
      ..addByte(8)
      ..add(echoWrongId ? List<int>.filled(8, 7) : scid)
      ..addByte(8)
      ..add(dcid)
      ..add([0, 0, 0, 1]);
    server.send(reply.toBytes(), dg.address, dg.port);
  });
  return server;
}

LocationItem _row(String link) => LocationItem(
      id: 'x',
      countryCode: 'TR',
      country: 'Turkey',
      city: 'Istanbul',
      available: true,
      isCustom: true,
      rawLink: link,
    );

void main() {
  test('measures the round trip from a Version Negotiation reply', () async {
    final server = await _fakeQuicServer();
    final ms = await quicPing('127.0.0.1', server.port);
    server.close();
    expect(ms, isNotNull);
    expect(ms, lessThan(1000));
  });

  test('ignores a reply that is not for this probe', () async {
    final server = await _fakeQuicServer(echoWrongId: true);
    final ms = await quicPing('127.0.0.1', server.port,
        timeout: const Duration(milliseconds: 300));
    server.close();
    expect(ms, isNull);
  });

  test('nothing listening: null, not a hang', () async {
    final idle = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = idle.port;
    final ms = await quicPing('127.0.0.1', port,
        timeout: const Duration(milliseconds: 300));
    idle.close();
    expect(ms, isNull);
  });

  test('targets: Hysteria2 links, but not obfuscated ones or other transports',
      () {
    expect(
        resolveQuicPingTarget(_row('hysteria2://a:a@45.15.41.3:443/?sni=x#TR')),
        ('45.15.41.3', 443));
    expect(resolveQuicPingTarget(_row('hy2://a@h.example/?sni=x')),
        ('h.example', 443));
    expect(
        resolveQuicPingTarget(_row(
            'hysteria2://a:a@45.15.41.3:20443/?obfs=salamander&obfs-password=p')),
        isNull);
    expect(
        resolveQuicPingTarget(
            _row('vless://id@45.15.41.3:443?security=reality')),
        isNull);
  });
}
