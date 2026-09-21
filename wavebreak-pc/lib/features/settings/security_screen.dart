import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/language_controller.dart';
import '../../core/storage/prefs_store.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/biometric/biometric_service.dart';
import '../../services/pin/pin_service.dart';
import '../shared/detail_scaffold.dart';
import '../shared/nav_utils.dart';
import '../shared/wb_card.dart';
import 'pin_setup_screen.dart';

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
  bool _appLockEnabled = false;

  @override
  void initState() {
    super.initState();
    _bioEnabled = _bio.isEnabled;
    _pinSet = _pin.isSet;
    _appLockEnabled = PrefsStore.getBool(PrefsStore.appLockEnabled);
    _bio.isAvailable().then((value) {
      if (mounted) setState(() => _bioAvailable = value);
    });
  }

  bool get _hasAnyUnlockMethod => _bioEnabled || _pinSet;

  Future<void> _toggleBiometric(bool value) async {
    final s = ref.read(stringsProvider);
    if (value) {
      final available = await _bio.isAvailable();
      if (!available) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.biometricsNotAvailable)),
          );
        }
        return;
      }
      final confirmed = await _bio.authenticate(reason: s.confirmToEnableBiometric);
      if (!confirmed) return;
    }
    await _bio.setEnabled(value);
    if (mounted) setState(() => _bioEnabled = value);
    // Turning off the only unlock method the app lock relies on turns the
    // lock off too, rather than leaving it on with nothing to unlock with.
    if (!value && !_pinSet && _appLockEnabled) {
      await PrefsStore.setBool(PrefsStore.appLockEnabled, false);
      if (mounted) setState(() => _appLockEnabled = false);
    }
  }

  Future<void> _setUpPin() async {
    final saved = await showPinSetupScreen(context);
    if (saved == true && mounted) setState(() => _pinSet = true);
  }

  Future<void> _removePin() async {
    await _pin.clear();
    if (!mounted) return;
    setState(() => _pinSet = false);
    if (!_bioEnabled && _appLockEnabled) {
      await PrefsStore.setBool(PrefsStore.appLockEnabled, false);
      setState(() => _appLockEnabled = false);
    }
  }

  Future<void> _toggleAppLock(bool value) async {
    if (value && !_hasAnyUnlockMethod) {
      final saved = await showPinSetupScreen(context);
      if (saved != true || !mounted) return;
      setState(() => _pinSet = true);
    }
    await PrefsStore.setBool(PrefsStore.appLockEnabled, value);
    if (mounted) setState(() => _appLockEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return DetailScaffold(
      title: s.security,
      onBack: () => safePop(context, fallback: '/settings'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WbCard(
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeTrackColor: WbColors.waveCyan,
              title: Text(s.appLock),
              subtitle: Text(
                s.requireUnlockToOpen,
                style: const TextStyle(color: WbColors.ice60, fontSize: 12),
              ),
              value: _appLockEnabled,
              onChanged: _toggleAppLock,
            ),
          ),
          const SizedBox(height: 12),
          WbCard(
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeTrackColor: WbColors.waveCyan,
              title: Text(s.faceIdTouchId),
              subtitle: Text(
                _bioAvailable ? s.useBiometricsForQuickUnlock : s.biometricsNotAvailable,
                style: const TextStyle(color: WbColors.ice60, fontSize: 12),
              ),
              value: _bioEnabled,
              onChanged: _bioAvailable ? _toggleBiometric : null,
            ),
          ),
          const SizedBox(height: 12),
          WbCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.pin_rounded, color: WbColors.ice),
              title: Text(s.pinCode),
              subtitle: Text(
                _pinSet ? s.changePinCode : s.setPinCode,
                style: const TextStyle(color: WbColors.ice60, fontSize: 12),
              ),
              trailing: _pinSet
                  ? IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: WbColors.ice60),
                      onPressed: _removePin,
                    )
                  : const Icon(Icons.chevron_right_rounded, color: WbColors.ice60),
              onTap: _setUpPin,
            ),
          ),
        ],
      ),
    );
  }
}
