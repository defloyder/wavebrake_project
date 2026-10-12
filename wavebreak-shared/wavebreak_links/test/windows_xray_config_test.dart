import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wavebreak_links/wavebreak_links.dart';

// The Windows client's Xray-core config (handoff 12.10: PC moves from
// sing-box to Xray). Shapes are checked always; with XRAY_BIN pointing at
// an xray.exe (and XRAY_LOCATION_ASSET at geoip/geosite.dat) every config
// is also put through `xray run -test`, which parses and builds it without
// opening any adapter.

const _id = '11111111-2222-3333-4444-555555555555';
const _pbk = 'Z84J2IelR9ch3k8VtlVhhs5ycBUlXA7wHBWcBrjqnAw';

final links = <String, String>{
  'reality-vision': 'vless://$_id@45.15.41.3:443?encryption=none&flow=xtls-rprx-vision'
      '&fp=chrome&pbk=$_pbk&security=reality&sid=abcd&sni=www.cloudflare.com&type=tcp#R',
  'reality-xhttp': 'vless://$_id@45.15.41.3:443?encryption=none&fp=chrome&pbk=$_pbk'
      '&security=reality&sid=abcd&sni=www.cloudflare.com&type=xhttp&path=%2Fx&mode=auto#X',
  'direct-tls-ws': 'vless://$_id@direct.wavebreak.com.tr:443?encryption=none'
      '&host=direct.wavebreak.com.tr&path=%2Fwvb-dt&security=tls&sni=direct.wavebreak.com.tr&type=ws#D',
  'vless-grpc': 'vless://$_id@h.example.com:443?security=tls&type=grpc&serviceName=gs&sni=h.example.com#G',
  'vmess-ws-tls': 'vmess://${base64Encode(utf8.encode(jsonEncode({
        'add': 'h.example.com',
        'port': '443',
        'id': _id,
        'net': 'ws',
        'path': '/vm',
        'host': 'h.example.com',
        'tls': 'tls',
      })))}',
  'trojan': 'trojan://secret@t.example.com:443#T',
  'ss-2022': 'ss://2022-blake3-aes-128-gcm:YctPZ6U7xPPcU%2Bgp3u%2B0tx%2FtRizJN9K8y%2BuKlW2qjlI%3D@s.example.com:443#S',
  'hysteria2': 'hysteria2://$_id:$_id@45.15.41.3:443/?alpn=h3&sni=hy2.wavebreak.com.tr#H',
};

Map<String, dynamic> windowsConfig(String link, {bool smart = false}) {
  final parsed = parseShareLink(link);
  if (smart) applySmartRoutingPolicy(parsed, kClientSmartRoutingPolicy);
  return jsonDecode(
          parsed.getWindowsTunConfiguration(probePort: 47984, metricsPort: 47985))
      as Map<String, dynamic>;
}

void main() {
  test('TUN inbound owns routes, binds outbounds to the physical NIC', () {
    final c = windowsConfig(links['reality-vision']!, smart: true);
    final inbounds = (c['inbounds'] as List).cast<Map>();
    final tun = inbounds.first;
    expect(tun['protocol'], 'tun');
    // The smart-routing DNS rule matches on this tag.
    expect(tun['tag'], 'in_proxy');
    final s = tun['settings'] as Map;
    expect(s['autoSystemRoutingTable'], ['0.0.0.0/0', '::/0']);
    expect(s['autoOutboundsInterface'], 'auto');
    expect(s['dns'], isNotEmpty);
    final probe = inbounds[1];
    expect(probe['protocol'], 'socks');
    expect(probe['listen'], '127.0.0.1');
    expect(probe['port'], 47984);
    // Outbounds as on Android: the proxy first.
    expect(((c['outbounds'] as List).first as Map)['tag'], 'proxy');
    // Byte counters on loopback.
    expect(c['stats'], isA<Map>());
    expect(c['metrics'], {'tag': 'metrics_out', 'listen': '127.0.0.1:47985'});
    expect(((c['policy'] as Map)['system'] as Map)['statsOutboundDownlink'], isTrue);
  });

  final xray = Platform.environment['XRAY_BIN'];
  group('xray run -test', () {
    for (final entry in links.entries) {
      for (final smart in [false, true]) {
        test('${entry.key}${smart ? ' + smart routing' : ''}', () async {
          final dir = await Directory.systemTemp.createTemp('wbxray');
          try {
            final file = File('${dir.path}${Platform.pathSeparator}config.json');
            await file.writeAsString(jsonEncode(windowsConfig(entry.value, smart: smart)));
            final r = await Process.run(xray!, ['run', '-test', '-c', file.path]);
            expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
            expect('${r.stdout}', contains('Configuration OK'));
          } finally {
            await dir.delete(recursive: true);
          }
        });
      }
    }
  }, skip: xray == null ? 'XRAY_BIN not set' : false);
}
