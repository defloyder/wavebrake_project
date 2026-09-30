import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/services/vpn/native_vpn_adapter.dart';

void main() {
  test('only cloak=1 Hysteria2 links go to the bridge', () {
    expect(usesCloak('hysteria2://a:a@1.2.3.4:443/?sni=x&cloak=1#t'), isTrue);
    expect(usesCloak('hysteria2://a:a@1.2.3.4:443/?sni=x&cloak=true#t'), isTrue);
    expect(usesCloak('hysteria2://a:a@1.2.3.4:443/?sni=x#t'), isFalse);
    expect(usesCloak('hysteria2://a:a@1.2.3.4:443/?sni=x&cloak=0#t'), isFalse);
  });
}
