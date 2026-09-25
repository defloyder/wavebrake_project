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

  // Real bug this timeout exists to fix: sign-in visibly succeeding and
  // then spinning forever with no way out, confirmed cross-platform
  // (Windows and Android) with the server itself independently confirmed
  // healthy/fast. login_screen.dart calls isAvailable() as part of the
  // "want to enable Face ID/Touch ID?" offer immediately after a
  // successful login — a native platform-channel call
  // (canCheckBiometrics/isDeviceSupported) with no timeout anywhere
  // above it in that chain. The existing PlatformException catch does
  // nothing for a call that hangs rather than throws — a genuinely stuck
  // platform channel (a real, if uncommon, plugin failure mode on any
  // platform) has no business ever blocking sign-in over an optional
  // convenience prompt.
  static const _availabilityTimeout = Duration(seconds: 5);

  Future<bool> isAvailable() async {
    try {
      return await _checkAvailable().timeout(_availabilityTimeout);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _checkAvailable() async {
    final can = await _auth.canCheckBiometrics;
    final supported = await _auth.isDeviceSupported();
    return can && supported;
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
