import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/services/custom_servers/custom_server_controller.dart';
import 'package:wavebreak/features/shared/share_subscription_sheet.dart';

void main() {
  test('the same server link with another label is the same link', () {
    expect(
      CustomServerController.sameLinkKey('vless://id@de.example:443?security=tls#Germany'),
      CustomServerController.sameLinkKey(' vless://id@de.example:443?security=tls#Другое имя '),
    );
  });

  test('WAVEBREAK subscription on api. and core. is one subscription', () {
    expect(
      CustomServerController.sameLinkKey('https://api.wavebreak.com.tr/v1/sub/57afe491/'),
      CustomServerController.sameLinkKey('https://CORE.wavebreak.com.tr/v1/sub/57afe491'),
    );
    expect(
      CustomServerController.sameLinkKey('https://core.wavebreak.com.tr/v1/sub/a'),
      isNot(CustomServerController.sameLinkKey('https://core.wavebreak.com.tr/v1/sub/b')),
    );
  });

  test('shared WAVEBREAK subscription links go out on core.', () {
    expect(publicSubscriptionLink('https://api.wavebreak.com.tr/v1/sub/57afe491'),
        'https://core.wavebreak.com.tr/v1/sub/57afe491');
    expect(publicSubscriptionLink('vless://id@h:443#x'), 'vless://id@h:443#x');
  });
}
