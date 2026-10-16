import 'dart:convert';

import 'package:test/test.dart';
import 'package:wavebreak_links/wavebreak_links.dart';

void main() {
  test('the server name answered from hosts on Windows (DNS deadlock)', () {
    const link = 'vless://11111111-2222-3333-4444-555555555555'
        '@direct.example.com:443?type=ws&security=tls&path=%2Fwvb-dt'
        '&host=direct.example.com&sni=direct.example.com#x';
    final config = jsonDecode(parseShareLink(link).getWindowsTunConfiguration(
        probePort: 47984,
        serverHosts: const {
          'direct.example.com': ['203.0.113.7']
        })) as Map;
    expect(config['dns']['hosts'], {
      'direct.example.com': ['203.0.113.7']
    });
    final plain = jsonDecode(parseShareLink(link)
        .getWindowsTunConfiguration(probePort: 47984)) as Map;
    expect((plain['dns'] as Map).containsKey('hosts'), isFalse);
  });
}
