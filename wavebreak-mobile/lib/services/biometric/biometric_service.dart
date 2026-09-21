import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/storage/prefs_store.dart';

class BiometricService {
  BiometricService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  bool get isEnabled => PrefsStore.getBool(PrefsStore.biometricEnabled);

  Future<void> setEnabled(bool value) {
    return PrefsStore.setBool(PrefsStore.biometricEnabled, value);
  }

  bool get requireOnOpen =>
      PrefsStore.getBool(PrefsStore.requireBiometricOnOpen);

  Future<void> setRequireOnOpen(bool value) {
    return PrefsStore.setBool(PrefsStore.requireBiometricOnOpen, value);
  }

  Future<bool> isAvailable() async {
    try {
      final can = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      return can && supported;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> authenticate({String reason = 'Unlock WAVEBREAK'}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}
