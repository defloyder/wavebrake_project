import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/services/vpn/windows_vpn_adapter.dart';
import 'package:wavebreak_links/wavebreak_links.dart';

void main() {
  final link = ShareLink.parse(
      'hysteria2://g:g@hy2.example.test:443/?sni=hy2.example.test&alpn=h3&cloak=1#t');

  test('a cloak link parses as cloak', () {
    expect(link.cloak, isTrue);
  });

  test('cloak: the real server IP goes past the tunnel, the outbound to the local proxy', () {
    final local = link.withHostPort('127.0.0.1', 50123, clearPortHopping: true);
    final cfg = singBoxConfigFor(local, directIps: ['45.15.41.3']);
    final route = cfg['route'] as Map<String, dynamic>;
    expect(route['rules'], [
      {
        'ip_cidr': ['45.15.41.3/32'],
        'outbound': 'direct',
      }
    ]);
    final out = (cfg['outbounds'] as List).first as Map<String, dynamic>;
    expect(out['server'], '127.0.0.1');
    expect(out['server_port'], 50123);
    expect((out['tls'] as Map)['server_name'], 'hy2.example.test');
    final dump = Platform.environment['WB_SINGBOX_DUMP'];
    if (dump != null) File(dump).writeAsStringSync(jsonEncode(cfg));
  });

  test('no cloak: no extra route rules', () {
    final route = singBoxConfigFor(link)['route'] as Map<String, dynamic>;
    expect(route.containsKey('rules'), isFalse);
  });
}
