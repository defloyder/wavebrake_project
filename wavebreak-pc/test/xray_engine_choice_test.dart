import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/services/vpn/windows_tunnel.dart';
import 'package:wavebreak/services/vpn/windows_xray_adapter.dart';

const _id = '11111111-2222-3333-4444-555555555555';

void main() {
  test('Xray takes what it runs as it is; the rest stays on sing-box', () {
    // WAVEBREAK REALITY + Vision, XHTTP, Direct-TLS, Hysteria2.
    expect(
        WindowsXrayAdapter.supports('vless://$_id@45.15.41.3:443?security=reality'
            '&pbk=Z84J2IelR9ch3k8VtlVhhs5ycBUlXA7wHBWcBrjqnAw&sid=ab&sni=a.com'
            '&flow=xtls-rprx-vision&type=tcp#R'),
        isTrue);
    expect(
        WindowsXrayAdapter.supports(
            'vless://$_id@h.example.com:443?security=tls&type=xhttp&path=%2Fx#X'),
        isTrue);
    expect(
        WindowsXrayAdapter.supports(
            'hysteria2://$_id@45.15.41.3:443/?sni=hy2.wavebreak.com.tr#H'),
        isTrue);
    // cloak: only sing-box + cloak-client-proxy wrap it.
    expect(
        WindowsXrayAdapter.supports(
            'hysteria2://$_id@45.15.41.3:443/?sni=hy2.wavebreak.com.tr&cloak=1#C'),
        isFalse);
    // TUIC: not in Xray.
    expect(WindowsXrayAdapter.supports('tuic://$_id:pw@h.example.com:443#T'),
        isFalse);
    // A self-signed third-party server: Xray rejects allowInsecure.
    expect(
        WindowsXrayAdapter.supports(
            'trojan://pw@h.example.com:443?allowInsecure=1#I'),
        isFalse);
    expect(WindowsXrayAdapter.supports('garbage'), isFalse);
  });

  test('profile link and routing policy are read as on Android', () {
    expect(windowsProfileUrl('vless://a@b:1#x'), 'vless://a@b:1#x');
    expect(
        windowsProfileUrl('{"vless":{"connection_url":"vless://a@b:1"}}'),
        'vless://a@b:1');
    expect(windowsProfileRoutingPolicy('vless://a@b:1'), isNull);
    expect(
        windowsProfileRoutingPolicy(
            '{"vless":{"connection_url":"x"},"routing_policy":{"id":"p"}}'),
        {'id': 'p'});
  });
}
