import 'package:flutter_test/flutter_test.dart';

import 'package:wavebreak/services/biometric/biometric_service.dart';

import 'test_helpers.dart';

void main() {
  setUp(setUpTestEnvironment);

  test('biometric preference defaults to disabled', () {
    final service = BiometricService();
    expect(service.isEnabled, isFalse);
  });

  test('enabling and disabling biometrics persists the preference', () async {
    final service = BiometricService();
    await service.setEnabled(true);
    expect(service.isEnabled, isTrue);

    await service.setEnabled(false);
    expect(service.isEnabled, isFalse);
  });

  test('require-on-open cannot be inferred without being set explicitly', () async {
    final service = BiometricService();
    expect(service.requireOnOpen, isFalse);
    await service.setRequireOnOpen(true);
    expect(service.requireOnOpen, isTrue);
  });
}
