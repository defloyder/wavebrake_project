import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/services/core_api/models.dart';
import 'package:wavebreak/services/vpn/connection_manager.dart';
import 'package:wavebreak/services/vpn/protocol_fallback.dart';

LocationItem loc(String id, String cc, {bool available = true}) =>
    LocationItem(
        id: id,
        countryCode: cc,
        country: cc,
        city: id,
        available: available,
        isCustom: true,
        rawLink: 'vless://x@h:443#$id');

void main() {
  final hy = loc('tr-hy2', 'TR');
  final reality = loc('tr-reality', 'TR');
  final direct = loc('tr-direct', 'TR');
  final ru = loc('ru-hy2', 'RU');
  final own = [hy, reality, ru, direct];

  group('H2: another protocol only on the user\'s tap', () {
    test('next protocol of the same country, in list order', () {
      expect(nextProtocolLocation(own, hy, {hy.id})?.id, reality.id);
      expect(nextProtocolLocation(own, reality, {hy.id, reality.id})?.id,
          direct.id);
    });

    test('wraps around and skips tried and unavailable ones', () {
      expect(nextProtocolLocation(own, direct, {direct.id})?.id, hy.id);
      final list = [hy, loc('tr-down', 'TR', available: false), direct];
      expect(nextProtocolLocation(list, hy, {hy.id})?.id, direct.id);
    });

    test('never another country: null once the country is exhausted', () {
      expect(
          nextProtocolLocation(own, direct, {hy.id, reality.id, direct.id}),
          isNull);
      expect(nextProtocolLocation(own, ru, {ru.id}), isNull);
    });
  });

  group('H2: noTraffic state', () {
    const connected = WbConnectionState(status: ConnectionStatus.connected);

    test('kept across unrelated updates while connected', () {
      final s = connected.copyWith(noTraffic: true);
      expect(s.noTraffic, isTrue);
      expect(s.copyWith(grantId: 'g').noTraffic, isTrue);
    });

    test('cleared by any status change and by a passing check', () {
      final s = connected.copyWith(noTraffic: true);
      expect(s.copyWith(status: ConnectionStatus.connecting).noTraffic,
          isFalse);
      expect(s.copyWith(status: ConnectionStatus.connected).noTraffic,
          isFalse);
      expect(s.copyWith(noTraffic: false).noTraffic, isFalse);
    });

    test('never set outside connected', () {
      const idle = WbConnectionState(status: ConnectionStatus.idle);
      expect(idle.copyWith(noTraffic: true).noTraffic, isFalse);
    });
  });
}
