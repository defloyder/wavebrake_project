import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/language_controller.dart';
import '../../services/biometric/biometric_service.dart';
import '../../services/pin/pin_service.dart';
import 'settings_ui.dart';
import 'pin_setup_screen.dart';
import 'pin_verify_screen.dart';

class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  final _bio = BiometricService();
  final _pin = const PinService();
  bool _bioAvailable = false;
  bool _bioEnabled = false;
  bool _pinSet = false;

  // Bug 7: the PIN is the app lock (see AppLockGate); there is no separate
  // "App lock" switch any more. Biometrics are an alternative way to pass
  // the PIN lock and can only be on while a PIN is set.

  @override
  void initState() {
    super.initState();
    _pinSet = _pin.isSet;
    _bioEnabled = _pinSet && _bio.isEnabled;
    _bio.isAvailable().then((value) {
      if (mounted) setState(() => _bioAvailable = value);
    });
  }

  Future<void> _toggleBiometric(bool value) async {
    final s = ref.read(stringsProvider);
    if (value) {
      if (!_pinSet) return;
      final available = await _bio.isAvailable();
      if (!available) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.biometricsNotAvailable)),
          );
        }
        return;
      }
      final confirmed =
          await _bio.authenticate(reason: s.confirmToEnableBiometric);
      if (!confirmed) return;
    }
    await _bio.setEnabled(value);
    if (mounted) setState(() => _bioEnabled = value);
  }

  /// Set a PIN, or change it after proving the current one.
  Future<void> _setUpPin() async {
    if (_pinSet) {
      final verified = await showPinVerifyScreen(context);
      if (verified != true || !mounted) return;
    }
    final saved = await showPinSetupScreen(context);
    if (saved == true && mounted) setState(() => _pinSet = true);
  }

  /// Remove the PIN — only after the current PIN is entered. Biometrics
  /// go with it (they can't exist without a PIN).
  Future<void> _removePin() async {
    final verified = await showPinVerifyScreen(context);
    if (verified != true || !mounted) return;
    await _pin.clear();
    await _bio.setEnabled(false);
    if (!mounted) return;
    setState(() {
      _pinSet = false;
      _bioEnabled = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return SettingsPage(
      title: s.security,
      children: [
        SettingsGroup(
          children: [
            SettingsRow(
              icon: Icons.pin_rounded,
              title: s.pinCode,
              subtitle: _pinSet ? s.changePinCode : s.setPinCode,
              onTap: _setUpPin,
            ),
            if (_pinSet)
              SettingsRow(
                icon: Icons.delete_outline_rounded,
                title: s.removePinCode,
                destructive: true,
                chevron: false,
                onTap: _removePin,
              ),
            SettingsSwitchRow(
              icon: Icons.fingerprint_rounded,
              title: s.faceIdTouchId,
              subtitle: !_bioAvailable
                  ? s.biometricsNotAvailable
                  : _pinSet
                      ? s.useBiometricsForQuickUnlock
                      : s.pinRequiredForBiometric,
              value: _bioEnabled,
              onChanged:
                  (_bioAvailable && _pinSet) ? _toggleBiometric : null,
            ),
          ],
        ),
      ],
    );
  }
}
