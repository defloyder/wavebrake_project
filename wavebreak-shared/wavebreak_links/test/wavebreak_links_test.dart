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

const _hysteriaObfs = 'hysteria2://$_grant:$_grant@45.15.41.3:20443/'
    '?alpn=h3&sni=hy2.wavebreak.com.tr&obfs=salamander&obfs-password=OBFSPW&mport=20000-30000'
    '#Turkey,%20Istanbul%20%28Hysteria2%20Obfs%29';

void main() {
  group('Hysteria2 obfuscation and port hopping', () {
    test('mport is parsed; a malformed one is ignored', () {
      expect(ShareLink.parse(_hysteriaObfs).portHopping, '20000-30000');
      expect(ShareLink.parse(_hysteriaObfs).obfs, 'salamander');
      for (final bad in ['30000-20000', '0-100', '20000-70000', 'abc', '1-2-3']) {
        expect(ShareLink.parse(_hysteriaObfs.replaceFirst('20000-30000', bad)).portHopping, isNull,
            reason: bad);
      }
      expect(ShareLink.parse(_hysteriaObfs.replaceFirst('20000-30000', '20000-25000,27000')).portHopping,
          '20000-25000,27000');
      expect(ShareLink.parse(_hysteria).portHopping, isNull);
    });

    test('Xray: salamander mask and UDP hop', () {
      final out = (jsonDecode(parseShareLink(_hysteriaObfs).getFullConfiguration())['outbounds'] as List)
          .first as Map;
      final mask = (out['streamSettings'] as Map)['finalmask'] as Map;
      expect(mask['udp'], [
        {'type': 'salamander', 'settings': {'password': 'OBFSPW'}}
      ]);
      expect((mask['quicParams'] as Map)['udpHop'], {'ports': '20000-30000', 'interval': '5-10'});
      // Plain Hysteria2: no mask, but still a new source port every 5-10 s
      // (hops on its own port).
      final plain = (jsonDecode(parseShareLink(_hysteria).getFullConfiguration())['outbounds'] as List)
          .first as Map;
      final plainMask = (plain['streamSettings'] as Map)['finalmask'] as Map;
      expect(plainMask.containsKey('udp'), isFalse);
      expect((plainMask['quicParams'] as Map)['udpHop'], {'ports': '443', 'interval': '5-10'});
    });

    test('sing-box: obfs, server_ports and hop_interval', () {
      final out = SingBoxProxy.fromLink(ShareLink.parse(_hysteriaObfs)).entry;
      expect(out['obfs'], {'type': 'salamander', 'password': 'OBFSPW'});
      expect(out['server_ports'], ['20000:30000']);
      expect(out['hop_interval'], '15s');
    });
  });

  group('Hysteria2 with a pinned certificate', () {
    const pin = 'aB:cd:ef:01:23:45:67:89:ab:cd:ef:01:23:45:67:89:ab:cd:ef:01:23:45:67:89:ab:cd:ef:01:23:45:67:89';
    const link = 'hysteria2://$_grant:$_grant@45.15.41.3:443/?sni=www.example.com&alpn=h3&pinSHA256=$pin#TR';

    test('parsed as lowercase hex without colons; junk ignored', () {
      expect(ShareLink.parse(link).pinSha256, pin.replaceAll(':', '').toLowerCase());
      expect(ShareLink.parse(link.replaceFirst(pin, 'abc')).pinSha256, isNull);
      expect(ShareLink.parse(_hysteria).pinSha256, isNull);
    });

    test('Xray verifies by the pin with the neutral SNI', () {
      final out = (jsonDecode(parseShareLink(link).getFullConfiguration())['outbounds'] as List).first as Map;
      final tls = (out['streamSettings'] as Map)['tlsSettings'] as Map;
      expect(tls['serverName'], 'www.example.com');
      expect(tls['pinnedPeerCertSha256'], pin.replaceAll(':', '').toLowerCase());
      final plain = (jsonDecode(parseShareLink(_hysteria).getFullConfiguration())['outbounds'] as List).first as Map;
      expect(((plain['streamSettings'] as Map)['tlsSettings'] as Map).containsKey('pinnedPeerCertSha256'), isFalse);
    });
  });

  group('smart routing (WAVEBREAK locations)', () {
    Map<String, dynamic> routed(String link, Map<String, dynamic>? policy) {
      final parsed = parseShareLink(link);
      applySmartRoutingPolicy(parsed, policy);
      return jsonDecode(parsed.getFullConfiguration()) as Map<String, dynamic>;
    }

    test('apps DNS goes to Xray DNS; Russian names via Yandex directly, the rest through the tunnel', () {
      final c = routed(_hysteria, kClientSmartRoutingPolicy);
      final outbounds = (c['outbounds'] as List).cast<Map>();
      expect(outbounds.map((o) => o['tag']), ['proxy', 'direct', 'blackhole', 'dns-out']);
      expect(outbounds.last['protocol'], 'dns');
      final dns = c['dns'] as Map;
      expect(dns['tag'], 'dns-internal');
      expect(dns['queryStrategy'], 'UseIPv4');
      final servers = dns['servers'] as List;
      expect((servers.first as Map)['address'], '77.88.8.8');
      expect((servers.first as Map)['domains'], contains('domain:xn--p1ai'));
      expect(servers.sublist(1), ['1.1.1.1', '8.8.8.8']);

      final rules = ((c['routing'] as Map)['rules'] as List).cast<Map>();
      expect(rules[0], {'type': 'field', 'inboundTag': ['in_proxy'], 'port': '53', 'outboundTag': 'dns-out'});
      expect(rules[1], {'type': 'field', 'inboundTag': ['dns-internal'], 'ip': ['77.88.8.8'], 'outboundTag': 'direct'});
      expect(rules[2], {'type': 'field', 'inboundTag': ['dns-internal'], 'outboundTag': 'proxy'});
      expect((c['routing'] as Map)['domainStrategy'], 'IPIfNonMatch');
    });

    test('blocked-in-Russia goes through the tunnel before the direct Russian rules', () {
      final rules = ((routed(_reality, kClientSmartRoutingPolicy)['routing'] as Map)['rules'] as List).cast<Map>();
      final blocked = rules.indexWhere((r) => (r['domain'] as List?)?.contains('geosite:category-media-ru-blocked') ?? false);
      final ru = rules.indexWhere((r) => (r['domain'] as List?)?.contains('domain:ru') ?? false);
      final geoip = rules.indexWhere((r) => (r['ip'] as List?)?.contains('geoip:ru') ?? false);
      expect(blocked, greaterThan(-1));
      expect(rules[blocked]['outboundTag'], 'proxy');
      expect(blocked, lessThan(ru));
      expect(rules[ru]['outboundTag'], 'direct');
      expect(rules[ru]['domain'], containsAll(['domain:ru', 'domain:su', 'domain:xn--p1ai', 'geosite:category-ru']));
      expect(geoip, greaterThan(ru));
    });

    test('Direct-TLS (WebSocket) is multiplexed; REALITY Vision and Hysteria are not', () {
      Map outbound(String link) =>
          (routed(link, kClientSmartRoutingPolicy)['outbounds'] as List).first as Map;
      expect(outbound(_directTls)['mux'],
          {'enabled': true, 'concurrency': 8, 'xudpConcurrency': 16, 'xudpProxyUDP443': 'reject'});
      expect((outbound(_reality)['mux'] as Map)['enabled'], false);
      expect(outbound(_hysteria).containsKey('mux'), isFalse);
      // A user's own server keeps mux off.
      final own = jsonDecode(parseShareLink(_directTls).getFullConfiguration()) as Map;
      expect((((own['outbounds'] as List).first as Map)['mux'] as Map)['enabled'], false);
    });

    test('known names are answered from cache while refreshed', () {
      final dns = routed(_hysteria, kClientSmartRoutingPolicy)['dns'] as Map;
      expect(dns['serveStale'], true);
      expect(dns['serveExpiredTTL'], 86400);
    });

    test('domains are sniffed for routing only', () {
      final inbound = (routed(_directTls, kClientSmartRoutingPolicy)['inbounds'] as List).first as Map;
      expect(inbound['sniffing'], {'enabled': true, 'destOverride': ['http', 'tls', 'quic'], 'routeOnly': true});
    });

    test("Core's own policy: geosite 'ru' becomes category-ru, no DNS change", () {
      final c = routed(_reality, {
        'mode': 'smart_split',
        'direct': {'private_networks': true, 'domain_suffixes': ['.ru', '.рф'], 'geosite': ['ru'], 'geoip': ['ru']},
      });
      final rules = ((c['routing'] as Map)['rules'] as List).cast<Map>();
      expect(rules.any((r) => (r['domain'] as List?)?.contains('geosite:category-ru') ?? false), isTrue);
      expect(rules.any((r) => (r['domain'] as List?)?.contains('geosite:ru') ?? false), isFalse);
      expect(c['dns'], {'servers': ['1.1.1.1', '8.8.8.8']});
      // proxy, direct, blackhole, fragment-out (REALITY is fragmented).
      expect((c['outbounds'] as List).length, 4);
    });

    test('no policy: config unchanged (users own servers)', () {
      final c = routed(_hysteria, null);
      expect((c['outbounds'] as List).length, 3);
      expect(((c['routing'] as Map)['rules'] as List).length, 1);
      expect(((c['inbounds'] as List).first as Map)['sniffing']['enabled'], false);
    });
  });

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
          'fragment': true,
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

    test('REALITY and Direct-TLS outbounds fragment their ClientHello', () {
      expect(SingBoxProxy.fromLink(ShareLink.parse(_reality)).entry['tls']['fragment'],
          isTrue);
      expect(
          SingBoxProxy.fromLink(ShareLink.parse(_directTls)).entry['tls']['fragment'],
          isTrue);
    });

    test('Hysteria2 is not fragmented — no TLS ClientHello to hide (QUIC)',
        () {
      expect(
          SingBoxProxy.fromLink(ShareLink.parse(_hysteria))
              .entry['tls']
              .containsKey('fragment'),
          isFalse);
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
        'finalmask': {
          'quicParams': {
            'congestion': 'bbr',
            'initStreamReceiveWindow': 8388608,
            'maxStreamReceiveWindow': 16777216,
            'initConnectionReceiveWindow': 20971520,
            'maxConnectionReceiveWindow': 41943040,
            'keepAlivePeriod': 10,
            'maxIdleTimeout': 30,
            'udpHop': {'ports': '443', 'interval': '5-10'},
          },
        },
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

    test('XHTTP + REALITY builds an xhttp stream without Vision flow', () {
      // Shape of wavebreak-core's buildVLESSRealityXHTTPLink.
      const xhttp = 'vless://$_grant@45.15.41.3:443'
          '?encryption=none&fp=chrome&mode=auto&path=%2Fwvb-rx&pbk=PUBKEY'
          '&security=reality&sid=abcd&sni=x.wavebreak.com.tr&spx=%2F&type=xhttp'
          '#Turkey,%20Istanbul%20%28XHTTP%29';
      final out = (config(xhttp)['outbounds'] as List).first as Map;
      final stream = out['streamSettings'] as Map;
      expect(stream['network'], 'xhttp');
      expect(stream['xhttpSettings'], {'path': '/wvb-rx', 'mode': 'auto'});
      expect(stream['security'], 'reality');
      final reality = stream['realitySettings'] as Map;
      expect(reality['serverName'], 'x.wavebreak.com.tr');
      expect(reality['publicKey'], 'PUBKEY');
      expect(reality['shortId'], 'abcd');
      final user = (((out['settings'] as Map)['vnext'] as List).first as Map)['users'][0] as Map;
      expect(user['flow'] ?? '', isEmpty);
      // sing-box (Windows) has no XHTTP: the link is reported, not mis-built.
      expect(ShareLink.parse(xhttp).supportedBy(TunnelEngine.singBox), isFalse);
    });

    test('Direct-TLS takes the TLS fingerprint from the link', () {
      // A single-packet ClientHello (fp=ios, ~0.5 KB) survives carrier DPI
      // that drops the second segment of the large post-quantum ones.
      final out = (config(_directTls.replaceFirst('&type=ws', '&type=ws&fp=ios'))['outbounds'] as List).first as Map;
      final tls = (out['streamSettings'] as Map)['tlsSettings'] as Map;
      expect(tls['fingerprint'], 'ios');
      expect(tls['serverName'], 'direct.wavebreak.com.tr');
    });

    test('TCP outbounds give up an unacknowledged connection after 20 s', () {
      // After sleep the carrier has dropped idle connections; this makes
      // the engine redial in seconds instead of minutes (owner, 06.10).
      for (final link in [_directTls, _reality]) {
        final outs = (config(link)['outbounds'] as List).cast<Map>();
        Map<String, dynamic>? sockopt(String tag) => ((outs.firstWhere(
                (o) => o['tag'] == tag)['streamSettings'] as Map?)?['sockopt'])
            ?.cast<String, dynamic>();
        expect(sockopt('proxy')?['tcpUserTimeout'], kTcpUserTimeoutMs, reason: link);
        expect(sockopt('direct')?['tcpUserTimeout'], kTcpUserTimeoutMs);
        expect(sockopt('fragment-out')?['tcpUserTimeout'], kTcpUserTimeoutMs);
      }
      final hy = (config(_hysteria)['outbounds'] as List).first as Map;
      expect(((hy['streamSettings'] as Map?)?['sockopt'] as Map?)?['tcpUserTimeout'], isNull,
          reason: 'QUIC, not TCP');
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

    test('REALITY gets a fragment-out outbound chained via dialerProxy', () {
      final cfg = config(_reality);
      final outbounds = (cfg['outbounds'] as List).cast<Map<String, dynamic>>();
      final fragmentOut =
          outbounds.where((o) => o['tag'] == 'fragment-out').firstOrNull;
      expect(fragmentOut, isNotNull);
      expect(fragmentOut!['protocol'], 'freedom');
      expect(fragmentOut['settings']['fragment'], {
        'packets': 'tlshello',
        'length': '10-20',
        'interval': '10-20',
      });
      final proxyOut = outbounds.firstWhere((o) => o['tag'] == 'proxy');
      expect(proxyOut['streamSettings']['sockopt']['dialerProxy'],
          'fragment-out');
    });

    test('Direct-TLS (plain tls, not reality) is also fragmented', () {
      final outbounds =
          (config(_directTls)['outbounds'] as List).cast<Map<String, dynamic>>();
      expect(outbounds.any((o) => o['tag'] == 'fragment-out'), isTrue);
    });

    test('Hysteria2 is not fragmented — it is QUIC, not a TLS ClientHello',
        () {
      final outbounds =
          (config(_hysteria)['outbounds'] as List).cast<Map<String, dynamic>>();
      expect(outbounds.any((o) => o['tag'] == 'fragment-out'), isFalse);
    });
  });
}
