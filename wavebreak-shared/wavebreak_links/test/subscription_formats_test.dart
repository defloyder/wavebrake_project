import 'dart:io';

import 'package:test/test.dart';
import 'package:wavebreak_links/wavebreak_links.dart';
import 'package:wavebreak_links/src/mini_yaml.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

ShareLink only(ParsedSubscription sub, String remark) =>
    sub.links.map(ShareLink.parse).firstWhere((l) => l.remark == remark);

void main() {
  group('formats', () {
    test('plain share links, one per line', () {
      final sub = parseSubscription(fixture('links.txt'));
      expect(sub.format, SubscriptionFormat.shareLinks);
      expect(sub.links, hasLength(2));
    });

    test('base64 of share links', () {
      final sub = parseSubscription(fixture('links_base64.txt'));
      expect(sub.format, SubscriptionFormat.base64Links);
      expect(sub.links.map((l) => ShareLink.parse(l).remark), ['A', 'B']);
    });

    test('Clash/Mihomo YAML: every supported proxy becomes a share link', () {
      final sub = parseSubscription(fixture('clash_profile.yaml'));
      expect(sub.format, SubscriptionFormat.clash);
      expect(sub.links, hasLength(6));
      expect(sub.unsupported.map((n) => '${n.name}/${n.type}'), ['Old SSR/ssr']);

      final reality = only(sub, '🇩🇪 Germany, Frankfurt');
      expect(reality.protocol, LinkProtocol.vless);
      expect(reality.host, 'de.example.com');
      expect(reality.credential, '00000000-0000-4000-8000-000000000001');
      expect(reality.security, 'reality');
      expect(reality.sni, 'www.example.org');
      expect(reality.publicKey, 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA');
      expect(reality.shortId, '0123abcd');
      expect(reality.flow, 'xtls-rprx-vision');
      expect(reality.fingerprint, 'chrome');

      final ws = only(sub, '🇳🇱 Netherlands WS');
      expect(ws.protocol, LinkProtocol.vmess);
      expect(ws.port, 8443);
      expect(ws.network, 'ws');
      expect(ws.path, '/ray');
      expect(ws.hostHeader, 'cdn.example.com');
      expect(ws.security, 'tls');

      final trojan = only(sub, 'Trojan gRPC');
      expect(trojan.credential, 'pa:ss#word', reason: 'special characters survive');
      expect(trojan.network, 'grpc');
      expect(trojan.serviceName, 'tunnel');

      final ss = only(sub, 'SS 2022');
      expect(ss.method, '2022-blake3-aes-128-gcm');
      expect(ss.credential, 'AAAAAAAAAAAAAAAAAAAAAA==');

      final hy = only(sub, 'Hy2 hopping');
      expect(hy.protocol, LinkProtocol.hysteria2);
      expect(hy.obfs, 'salamander');
      expect(hy.obfsPassword, 'obfs-secret');
      expect(hy.insecure, isTrue);
      expect(hy.portHopping, isNotNull);

      final tuic = only(sub, 'TUIC v5');
      expect(tuic.protocol, LinkProtocol.tuic);
      expect(tuic.username, '00000000-0000-4000-8000-000000000003');
      expect(tuic.credential, 'tuic-secret');
      expect(tuic.supportedBy(TunnelEngine.xray), isFalse,
          reason: 'shown greyed out on Android');
    });

    test('sing-box JSON: proxy outbounds become share links, service ones are skipped', () {
      final sub = parseSubscription(fixture('singbox_profile.json'));
      expect(sub.format, SubscriptionFormat.singBox);
      expect(sub.links, hasLength(4));
      expect(sub.unsupported.map((n) => '${n.name}/${n.type}'), ['ShadowTLS/shadowtls']);

      final reality = only(sub, '🇫🇮 Finland REALITY');
      expect(reality.security, 'reality');
      expect(reality.publicKey, 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB');
      expect(reality.shortId, 'ab12');
      expect(reality.fingerprint, 'chrome');

      final ws = only(sub, 'Trojan WS');
      expect(ws.network, 'ws');
      expect(ws.path, '/tw');
      expect(ws.hostHeader, 'cdn.example.com');

      expect(only(sub, 'Hy2').insecure, isTrue);
      expect(only(sub, 'SS').method, 'aes-256-gcm');
    });

    test('garbage is unknown and empty', () {
      final sub = parseSubscription('<html>Not found</html>');
      expect(sub.format, SubscriptionFormat.unknown);
      expect(sub.isEmpty, isTrue);
    });
  });

  group('headers', () {
    test('subscription-userinfo', () {
      final info = SubscriptionUserInfo.parse(
          'upload=455727941; download=6174315083; total=1073741824000; expire=1798675200')!;
      expect(info.used, 455727941 + 6174315083);
      expect(info.total, 1073741824000);
      expect(info.expire, DateTime.utc(2026, 12, 31));
      expect(SubscriptionUserInfo.parse('upload=0; download=0; total=0; expire=0')!.expire, isNull);
      expect(SubscriptionUserInfo.parse(''), isNull);
    });

    test('profile-title, plain and base64', () {
      expect(decodeProfileTitle('My VPN'), 'My VPN');
      expect(decodeProfileTitle('base64:0JzQvtC5IFZQTg=='), 'Мой VPN');
      expect(decodeProfileTitle('  '), isNull);
    });

    test('profile-update-interval', () {
      expect(parseUpdateIntervalHours('12'), 12);
      expect(parseUpdateIntervalHours('0'), isNull);
      expect(parseUpdateIntervalHours('99999'), 720);
      expect(parseUpdateIntervalHours(null), isNull);
    });
  });

  group('mini YAML', () {
    test('block and flow collections, quotes, comments', () {
      final doc = parseMiniYaml('''
a: 1 # comment
b: "x # not a comment"
c:
  - one
  - {k: v, list: [1, 2, "three"]}
  - name: nested
    deep:
      flag: true
d: 'it''s'
e: ~
f: |
  line1
  line2
''') as Map;
      expect(doc['a'], 1);
      expect(doc['b'], 'x # not a comment');
      final c = doc['c'] as List;
      expect(c[0], 'one');
      expect(c[1], {'k': 'v', 'list': [1, 2, 'three']});
      expect(c[2], {'name': 'nested', 'deep': {'flag': true}});
      expect(doc['d'], "it's");
      expect(doc['e'], isNull);
      expect(doc['f'], 'line1\nline2');
    });

    test('a sequence at the same indent as its key', () {
      final doc = parseMiniYaml('proxies:\n- name: a\n  port: 1\n- name: b\n') as Map;
      expect(doc['proxies'], [
        {'name': 'a', 'port': 1},
        {'name': 'b'},
      ]);
    });
  });
}
