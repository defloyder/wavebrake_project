import 'package:test/test.dart';
import 'package:wavebreak_links/wavebreak_links.dart';

String stack(String link) => ShareLink.tryParse(link)!.stackLabel;

void main() {
  test('the link says what it is, whatever its name', () {
    const id = '11111111-2222-3333-4444-555555555555';
    expect(
        stack('vless://$id@1.2.3.4:443?type=tcp&security=reality&sni=ya.ru'
            '&pbk=abc&sid=01&fp=chrome#%F0%9F%87%B7%F0%9F%87%BA%20LTE%20(%D0%91%D0%A1)'),
        'VLESS / TCP / REALITY');
    expect(
        stack('vless://$id@h.example:443?type=ws&security=tls&path=%2Fx'
            '&sni=h.example#Turkey'),
        'VLESS / WS / TLS');
    expect(
        stack('vless://$id@h.example:443?type=xhttp&security=reality'
            '&sni=www.zeit.de&pbk=abc&sid=01&path=%2Fp#Germany'),
        'VLESS / XHTTP / REALITY');
    expect(stack('vless://$id@h.example:80?type=grpc&serviceName=s#x'),
        'VLESS / gRPC');
    expect(stack('hysteria2://pw@h.example:443?sni=h.example#Hy'),
        'Hysteria2');
    expect(
        stack('hysteria2://pw@h.example:443?obfs=salamander'
            '&obfs-password=p#Hy'),
        'Hysteria2 / Salamander');
    expect(stack('trojan://pw@h.example:443?security=tls&type=grpc#t'),
        'Trojan / gRPC / TLS');
  });
}
