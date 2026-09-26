import 'dart:convert';

import 'package:test/test.dart';
import 'package:wavebreak_links/wavebreak_links.dart';

// Shapes exactly as wavebreak-core's httpapi/product.go builds them
// (url.Values.Encode sorts keys; label is PathEscape'd).
const _grant = '11111111-2222-3333-4444-555555555555';
const _reality = 'vless://$_grant@45.15.41.3:443'
    '?encryption=none&flow=xtls-rprx-vision&fp=chrome&packetEncoding=xudp'
    '&pbk=PUBKEY&security=reality&sid=abcd&sni=www.cloudflare.com&spx=%2F&type=tcp'
    '#%F0%9F%87%B9%F0%9F%87%B7%20Turkey,%20Istanbul%20%28VLESS%29';
const _directTls = 'vless://$_grant@direct.wavebreak.com.tr:443'
    '?encryption=none&host=direct.wavebreak.com.tr&path=%2Fwvb-dt'
    '&security=tls&sni=direct.wavebreak.com.tr&type=ws'
    '#Turkey,%20Istanbul%20%28Direct-TLS%29';
const _hysteria = 'hysteria2://$_grant:$_grant@45.15.41.3:443/'
    '?alpn=h3&sni=hy2.wavebreak.com.tr#Turkey,%20Istanbul%20%28Hysteria2%29';

void main() {
  group('ShareLink.parse — protocols in production use', () {
    test('VLESS REALITY', () {
      final l = ShareLink.parse(_reality);
      expect(l.protocol, LinkProtocol.vless);
      expect(l.host, '45.15.41.3');
      expect(l.port, 443);
      expect(l.credential, _grant);
      expect(l.network, 'tcp');
      expect(l.security, 'reality');
      expect(l.flow, 'xtls-rprx-vision');
      expect(l.publicKey, 'PUBKEY');
      expect(l.shortId, 'abcd');
      expect(l.sni, 'www.cloudflare.com');
      expect(l.fingerprint, 'chrome');
      expect(l.remark, '🇹🇷 Turkey, Istanbul (VLESS)');
      expect(l.supportedBy(TunnelEngine.xray), isTrue);
      expect(l.supportedBy(TunnelEngine.singBox), isTrue);
    });

    test('Direct-TLS (VLESS WS TLS)', () {
      final l = ShareLink.parse(_directTls);
      expect(l.network, 'ws');
      expect(l.security, 'tls');
      expect(l.path, '/wvb-dt');
      expect(l.hostHeader, 'direct.wavebreak.com.tr');
      expect(l.sni, 'direct.wavebreak.com.tr');
    });

    test('Hysteria2 (hysteria2:// and hy2://)', () {
      for (final link in [_hysteria, _hysteria.replaceFirst('hysteria2://', 'hy2://')]) {
        final l = ShareLink.parse(link);
        expect(l.protocol, LinkProtocol.hysteria2);
        expect(l.credential, '$_grant:$_grant');
        expect(l.security, 'tls');
        expect(l.sni, 'hy2.wavebreak.com.tr');
        expect(l.alpn, 'h3');
      }
    });
  });

  group('ShareLink.parse — other schemes', () {
    test('vmess base64 JSON', () {
      final payload = base64.encode(utf8.encode(jsonEncode({
        'v': '2', 'ps': 'vm', 'add': 'a.example', 'port': '8443', 'id': _grant,
        'aid': '0', 'net': 'ws', 'host': 'h.example', 'path': '/p', 'tls': 'tls',
      })));
      final l = ShareLink.parse('vmess://$payload');
      expect(l.protocol, LinkProtocol.vmess);
      expect(l.port, 8443);
      expect(l.network, 'ws');
      expect(l.security, 'tls');
      expect(l.sni, 'h.example');
      expect(l.remark, 'vm');
    });

    test('shadowsocks SIP002, legacy and 2022', () {
      final sip = 'ss://${base64Url.encode(utf8.encode('aes-256-gcm:pw'))}@s.example:8388#n';
      final legacy = 'ss://${base64.encode(utf8.encode('chacha20-ietf-poly1305:pw@s.example:1234'))}';
      final ss2022 = 'ss://2022-blake3-aes-128-gcm:${Uri.encodeComponent('AAAA/+==')}@s.example:443';
      expect(ShareLink.parse(sip).method, 'aes-256-gcm');
      expect(ShareLink.parse(sip).credential, 'pw');
      expect(ShareLink.parse(legacy).port, 1234);
      final l = ShareLink.parse(ss2022);
      expect(l.method, '2022-blake3-aes-128-gcm');
      expect(l.credential, 'AAAA/+==');
    });

    test('tuic v5', () {
      final l = ShareLink.parse(
          'tuic://$_grant:pw@t.example:443?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=t.example');
      expect(l.protocol, LinkProtocol.tuic);
      expect(l.username, _grant);
      expect(l.credential, 'pw');
      expect(l.congestionControl, 'bbr');
      expect(l.supportedBy(TunnelEngine.xray), isFalse);
      expect(l.supportedBy(TunnelEngine.singBox), isTrue);
    });

    test('wireguard', () {
      final l = ShareLink.parse(
          'wireguard://PRIV%3D@w.example:51820?publickey=PUB%3D&address=10.0.0.2,fd00::2&mtu=1280&reserved=1,2,3');
      expect(l.protocol, LinkProtocol.wireguard);
      expect(l.privateKey, 'PRIV=');
      expect(l.peerPublicKey, 'PUB=');
      expect(l.localAddresses, ['10.0.0.2/32', 'fd00::2/128']);
      expect(l.mtu, 1280);
      expect(l.reserved, [1, 2, 3]);
    });

    test('socks with base64 userinfo', () {
      final l = ShareLink.parse('socks://${base64.encode(utf8.encode('u:p'))}@p.example:1080');
      expect(l.username, 'u');
      expect(l.credential, 'p');
    });

    test('unknown scheme and malformed links', () {
      expect(() => ShareLink.parse('ssr://abc'), throwsFormatException);
      expect(() => ShareLink.parse('vless://@host:443'), throwsFormatException);
      expect(ShareLink.tryParse('not a link'), isNull);
    });
  });

  group('extractShareLinks', () {
    test('base64 and plain bodies, unknown lines skipped', () {
      const plain = '$_reality\nhttps://example.com/help\n$_hysteria\n\nssr://x\n';
      expect(extractShareLinks(plain), [_reality, _hysteria]);
      expect(extractShareLinks(base64.encode(utf8.encode(plain))), [_reality, _hysteria]);
    });
  });

  group('sing-box (Windows)', () {
    test('REALITY outbound keeps the original PC shape', () {
      final p = SingBoxProxy.fromLink(ShareLink.parse(_reality));
      expect(p.isEndpoint, isFalse);
      expect(p.entry, {
        'type': 'vless',
        'tag': 'proxy',
        'server': '45.15.41.3',
        'server_port': 443,
        'uuid': _grant,
        'flow': 'xtls-rprx-vision',
        'tls': {
          'enabled': true,
          'server_name': 'www.cloudflare.com',
          'utls': {'enabled': true, 'fingerprint': 'chrome'},
          'reality': {'enabled': true, 'public_key': 'PUBKEY', 'short_id': 'abcd'},
        },
      });
    });

    test('Direct-TLS outbound', () {
      final p = SingBoxProxy.fromLink(ShareLink.parse(_directTls));
      expect(p.entry['transport'], {
        'type': 'ws',
        'path': '/wvb-dt',
        'headers': {'Host': 'direct.wavebreak.com.tr'},
      });
      expect(p.entry.containsKey('flow'), isFalse);
    });

    test('Hysteria2 outbound', () {
      final p = SingBoxProxy.fromLink(ShareLink.parse(_hysteria));
      expect(p.entry['type'], 'hysteria2');
      expect(p.entry['password'], '$_grant:$_grant');
      expect(p.entry['tls'], {'enabled': true, 'server_name': 'hy2.wavebreak.com.tr'});
    });

    test('WireGuard is an endpoint, TUIC an outbound', () {
      expect(
          SingBoxProxy.fromLink(ShareLink.parse(
                  'wg://K@w.example:51820?publickey=P&address=10.0.0.2'))
              .isEndpoint,
          isTrue);
      expect(
          SingBoxProxy.fromLink(ShareLink.parse('tuic://$_grant:pw@t.example:443'))
              .entry['type'],
          'tuic');
    });

    test('XHTTP is reported as unsupported, not silently mangled', () {
      final l = ShareLink.parse(
          'vless://$_grant@c.example:443?type=xhttp&security=tls&path=%2Fx');
      expect(() => SingBoxProxy.fromLink(l),
          throwsA(isA<UnsupportedByEngineException>()));
    });
  });

  group('Xray (Android)', () {
    Map<String, dynamic> config(String link) =>
        jsonDecode(parseShareLink(link).getFullConfiguration()) as Map<String, dynamic>;

    test('Hysteria2 uses the Xray-native outbound verified against the pilot', () {
      final out = (config(_hysteria)['outbounds'] as List).first as Map;
      expect(out['protocol'], 'hysteria');
      expect(out['settings'], {'version': 2, 'address': '45.15.41.3', 'port': 443});
      expect(out['streamSettings'], {
        'network': 'hysteria',
        'security': 'tls',
        'tlsSettings': {'serverName': 'hy2.wavebreak.com.tr', 'alpn': ['h3']},
        'hysteriaSettings': {'version': 2, 'auth': '$_grant:$_grant'},
      });
      final inbound = (config(_hysteria)['inbounds'] as List).first as Map;
      expect(inbound['port'], 1080);
    });

    test('REALITY still builds the same VLESS outbound', () {
      final out = (config(_reality)['outbounds'] as List).first as Map;
      expect(out['protocol'], 'vless');
      final stream = out['streamSettings'] as Map;
      expect(stream['network'], 'tcp');
      expect(stream['security'], 'reality');
      expect((stream['realitySettings'] as Map)['publicKey'], 'PUBKEY');
      final user = (((out['settings'] as Map)['vnext'] as List).first as Map)['users'][0] as Map;
      expect(user['flow'], 'xtls-rprx-vision');
    });

    test('WireGuard builds an Xray wireguard outbound', () {
      final out = (config('wg://K@w.example:51820?publickey=P&address=10.0.0.2')['outbounds']
              as List)
          .first as Map;
      expect(out['protocol'], 'wireguard');
      expect((out['settings'] as Map)['peers'], [
        {'publicKey': 'P', 'endpoint': 'w.example:51820'}
      ]);
    });

    test('TUIC is rejected as unsupported by Xray', () {
      expect(() => parseShareLink('tuic://$_grant:pw@t.example:443'),
          throwsA(isA<UnsupportedByEngineException>()));
    });
  });
}
