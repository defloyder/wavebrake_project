import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/services/vpn/network_change_policy.dart';

void main() {
  const wifi = ConnectivityResult.wifi;
  const ethernet = ConnectivityResult.ethernet;

  group('H1: network change on Windows', () {
    test('own TUN / another VPN adapter is not a real network', () {
      expect(
          physicalNetworks(
              [wifi, ConnectivityResult.vpn, ConnectivityResult.other]),
          {wifi});
      expect(physicalNetworks([ConnectivityResult.none]), isEmpty);
    });

    test('same networks, never lost: no reload', () {
      expect(
          networkChangeNeedsRecovery(previous: {wifi}, current: {wifi}),
          isFalse);
    });

    test('same network back after a blip: no reload', () {
      expect(
          networkChangeNeedsRecovery(
              previous: {wifi},
              current: {wifi},
              offlineFor: const Duration(milliseconds: 2500)),
          isFalse);
    });

    test('same network back after a long outage: reload', () {
      expect(
          networkChangeNeedsRecovery(
              previous: {wifi},
              current: {wifi},
              offlineFor: const Duration(seconds: 3)),
          isTrue);
    });

    test('a different network: reload', () {
      expect(
          networkChangeNeedsRecovery(previous: {wifi}, current: {ethernet}),
          isTrue);
      expect(
          networkChangeNeedsRecovery(
              previous: {wifi}, current: {wifi, ethernet}),
          isTrue);
    });

    test('no baseline yet or fully offline: no reload', () {
      expect(networkChangeNeedsRecovery(previous: null, current: {wifi}),
          isFalse);
      expect(networkChangeNeedsRecovery(previous: {wifi}, current: {}),
          isFalse);
    });
  });
}
