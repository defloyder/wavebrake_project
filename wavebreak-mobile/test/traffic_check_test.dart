import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/services/vpn/traffic_check.dart';

void main() {
  group('H2: an instant probe failure is "engine not ready", not a miss', () {
    test('an answer passes', () {
      expect(classifyProbe(120, const Duration(milliseconds: 300), notReadySoFar: 0),
          ProbeResult.passed);
    });

    test('an instant failure right after a reconnect is not ready', () {
      expect(classifyProbe(null, const Duration(milliseconds: 40), notReadySoFar: 0),
          ProbeResult.notReady);
    });

    test('a failure that waited for the network is a miss', () {
      expect(classifyProbe(null, const Duration(seconds: 4), notReadySoFar: 0),
          ProbeResult.miss);
    });

    test('fast failures that keep coming count as misses in the end', () {
      expect(
          classifyProbe(null, const Duration(milliseconds: 40),
              notReadySoFar: maxNotReadyProbes),
          ProbeResult.miss);
    });
  });
}
