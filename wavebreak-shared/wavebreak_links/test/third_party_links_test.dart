import 'dart:convert';

import 'package:test/test.dart';
import 'package:wavebreak_links/wavebreak_links.dart';

// Links the way third-party panels (3x-ui, Marzban, Remnawave, v2rayN
// exports) actually write them — not WAVEBREAK's own format.

String b64(String s) => base64Encode(utf8.encode(s));
String b64url(String s) => base64Url.encode(utf8.encode(s)).replaceAll('=', '');

Map<String, dynamic> server(V2RayURL l) =>
    ((l.outbound1['settings'] as Map)['servers'] as List).first
        as Map<String, dynamic>;
Map<String, dynamic> user(V2RayURL l) =>
    ((((l.outbound1['settings'] as Map)['vnext'] as List).first
            as Map)['users'] as List)
        .first as Map<String, dynamic>;

void main() {
  group('vmess', () {
    test('v2rayN JSON with ws + tls', () {
      final link = 'vmess://${b64(jsonEncode({
            'v': '2',
            'ps': '🇩🇪 Germany',
            'add': 'de.example.com',
            'port': '443',
            'id': 'a3482e88-686a-4a58-8126-99c9df64b7bf',
            'aid': '0',
            'scy': 'auto',
            'net': 'ws',
            'type': 'none',
            'host': 'cdn.example.com',
            'path': '/vm',
            'tls': 'tls',
            'sni': 'cdn.example.com',
          }))}';
      final l = parseShareLink(link) as VmessURL;
      expect(l.address, 'de.example.com');
      expect(l.port, 443);
      expect(l.remark, '🇩🇪 Germany');
      expect(user(l)['id'], 'a3482e88-686a-4a58-8126-99c9df64b7bf');
      expect(l.streamSetting['network'], 'ws');
      expect(l.streamSetting['wsSettings']['path'], '/vm');
      expect(l.streamSetting['security'], 'tls');
      expect(l.streamSetting['tlsSettings']['serverName'], 'cdn.example.com');
    });

    test('numbers as numbers, missing optional keys, no remark', () {
      final link = 'vmess://${b64(jsonEncode({
            'add': '1.2.3.4',
            'port': 8443,
            'id': 'a3482e88-686a-4a58-8126-99c9df64b7bf',
            'aid': 0,
          }))}';
      final l = parseShareLink(link) as VmessURL;
      expect(l.port, 8443);
      expect(l.remark, '');
      expect(l.streamSetting['network'], 'tcp');
      expect(user(l)['alterId'], 0);
      expect(l.fullConfiguration, isA<Map>());
    });

    test('missing address / port / id is a readable error, not a crash', () {
      for (final broken in [
        {'port': '443', 'id': 'x'},
        {'add': 'h', 'id': 'x'},
        {'add': 'h', 'port': 'abc', 'id': 'x'},
        {'add': 'h', 'port': '443'},
      ]) {
        expect(() => parseShareLink('vmess://${b64(jsonEncode(broken))}'),
            throwsA(isA<ArgumentError>()), reason: '$broken');
      }
      expect(() => parseShareLink('vmess://not-base64!!'),
          throwsA(isA<ArgumentError>()));
      expect(() => parseShareLink('vmess://${b64('[1,2]')}'),
          throwsA(isA<ArgumentError>()));
    });

    test('URL-safe base64 without padding', () {
      final link = 'vmess://${b64url(jsonEncode({
            'add': 'h.example.com',
            'port': '443',
            'id': 'a3482e88-686a-4a58-8126-99c9df64b7bf',
            'ps': 'Ünïcode ✓',
          }))}';
      expect((parseShareLink(link) as VmessURL).remark, 'Ünïcode ✓');
    });

    test('URI form', () {
      final l = parseShareLink(
              'vmess://a3482e88-686a-4a58-8126-99c9df64b7bf@h.example.com:2083'
              '?type=grpc&serviceName=gs&security=tls&sni=h.example.com#gRPC%20node')
          as VmessURL;
      expect(l.address, 'h.example.com');
      expect(l.port, 2083);
      expect(l.remark, 'gRPC node');
      expect(l.streamSetting['network'], 'grpc');
      expect(l.streamSetting['grpcSettings']['serviceName'], 'gs');
    });
  });

  group('trojan', () {
    test('no query string at all: TLS over TCP', () {
      final l = parseShareLink('trojan://secret@t.example.com:443#Node')
          as TrojanURL;
      expect(l.streamSetting['network'], 'tcp');
      expect(l.streamSetting['security'], 'tls');
      expect(server(l)['password'], 'secret');
    });

    test('empty query and empty values read the same', () {
      for (final link in [
        'trojan://secret@t.example.com:443?#Node',
        'trojan://secret@t.example.com:443?security=&type=#Node',
      ]) {
        final l = parseShareLink(link) as TrojanURL;
        expect(l.streamSetting['network'], 'tcp', reason: link);
        expect(l.streamSetting['security'], 'tls', reason: link);
      }
    });

    test('ws + tls, percent-encoded password, old "peer" for SNI', () {
      final l = parseShareLink(
              'trojan://p%40ss%3Aword@t.example.com:8443?type=ws&path=%2Ftr'
              '&host=cdn.example.com&peer=sni.example.com#T')
          as TrojanURL;
      expect(server(l)['password'], 'p@ss:word');
      expect(l.streamSetting['network'], 'ws');
      expect(l.streamSetting['wsSettings']['path'], '/tr');
      expect(l.streamSetting['tlsSettings']['serverName'], 'sni.example.com');
    });

    test('security=none is plain', () {
      final l = parseShareLink('trojan://s@t.example.com:80?security=none')
          as TrojanURL;
      expect(l.streamSetting['security'], '');
    });

    test('no password is an error', () {
      expect(() => parseShareLink('trojan://@t.example.com:443'),
          throwsA(isA<ArgumentError>()));
    });
  });

  group('shadowsocks', () {
    test('SIP002, base64url userinfo, no query', () {
      final l = parseShareLink(
              'ss://${b64url('chacha20-ietf-poly1305:pw123')}@s.example.com:8388#SS')
          as ShadowSocksURL;
      expect(server(l)['method'], 'chacha20-ietf-poly1305');
      expect(server(l)['password'], 'pw123');
      expect(l.port, 8388);
      expect(l.streamSetting['network'], 'tcp');
      expect(l.streamSetting['security'], '');
    });

    test('SIP002 with an open method:password (2022 ciphers)', () {
      final l = parseShareLink(
              'ss://2022-blake3-aes-128-gcm:YctPZ6U7xPPcU%2Bgp3u%2B0tx%2FtRizJN9K8y%2BuKlW2qjlI%3D'
              '@s.example.com:443#SS2022')
          as ShadowSocksURL;
      expect(server(l)['method'], '2022-blake3-aes-128-gcm');
      expect(server(l)['password'], 'YctPZ6U7xPPcU+gp3u+0tx/tRizJN9K8y+uKlW2qjlI=');
    });

    test('old form: the whole link in base64', () {
      final l = parseShareLink(
              'ss://${b64('aes-256-gcm:pa:ss@1.2.3.4:8388')}#Old')
          as ShadowSocksURL;
      expect(l.address, '1.2.3.4');
      expect(l.port, 8388);
      expect(server(l)['method'], 'aes-256-gcm');
      expect(server(l)['password'], 'pa:ss');
      expect(l.remark, 'Old');
    });

    test('empty query is the same as none', () {
      final l = parseShareLink(
              'ss://${b64url('aes-128-gcm:pw')}@s.example.com:8388?#SS')
          as ShadowSocksURL;
      expect(l.streamSetting['network'], 'tcp');
    });

    test('no cipher/password is a readable error', () {
      expect(() => parseShareLink('ss://garbage@s.example.com:8388'),
          throwsA(isA<ArgumentError>()));
    });
  });

  group('socks', () {
    test('base64 user:pass, plain user:pass, socks5://, no auth', () {
      final a = parseShareLink('socks://${b64('u:p')}@h.example.com:1080')
          as SocksURL;
      expect([a.username, a.password], ['u', 'p']);
      final b = parseShareLink('socks5://user:pa%3Ass@h.example.com:1080')
          as SocksURL;
      expect([b.username, b.password], ['user', 'pa:ss']);
      final c = parseShareLink('socks://h.example.com:1080') as SocksURL;
      expect(c.username, isNull);
    });
  });

  test('ssr:// is not runnable and says so', () {
    expect(() => parseShareLink('ssr://${b64('h:1:origin:aes-256-cfb:plain:cA')}'),
        throwsA(isA<ArgumentError>()));
    expect(subscriptionSchemes, isNot(contains('ssr')));
  });

  test('a ws link without a path gets "/" as a string', () {
    final l = parseShareLink(
        'vless://a3482e88-686a-4a58-8126-99c9df64b7bf@h.example.com:443?type=ws&security=tls');
    expect(l.streamSetting['wsSettings']['path'], '/');
  });
}
