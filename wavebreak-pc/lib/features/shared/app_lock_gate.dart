import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/language_controller.dart';
import '../../core/storage/prefs_store.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/biometric/biometric_service.dart';
import '../../services/pin/pin_service.dart';
import 'ocean_background.dart';
import 'pin_keypad.dart';
import 'wavebreak_mark.dart';

/// Whether App Lock can actually engage — it needs *some* unlock method
/// configured, not just the master switch on. Read by Security settings so
/// the toggle can't be flipped on with nothing to unlock with.
bool appLockAvailable() =>
    BiometricService().isEnabled || const PinService().isSet;

/// Covers the entire app behind a lock screen whenever App Lock is on —
/// at cold launch, and again every time the app returns to the foreground
/// after being backgrounded. Sits above everything (including the offline
/// banner) so nothing behind it is ever visible while locked.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget? child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  bool _locked = _shouldLock();

  static bool _shouldLock() =>
      PrefsStore.getBool(PrefsStore.appLockEnabled) && appLockAvailable();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  DateTime? _backgroundedAt;

  // Real-device bug this fixes: re-locking on every single pause->resume
  // transition with no threshold at all re-prompted for biometrics on
  // completely trivial backgrounding — switching apps for a second,
  // dismissing a system permission dialog, or (separately) the native
  // BiometricPrompt itself: showing it can trigger paused/resumed on the
  // host Activity on some Android versions/OEMs even though the user
  // never actually left the app, which combined with a zero threshold
  // here could re-arm the lock while a scan was still in flight and read
  // as "it re-prompted right after a successful scan." A real elapsed-
  // time threshold means only an actual meaningful stretch away from the
  // app re-locks it — most apps use something in this same ballpark
  // rather than re-prompting on every trivial resume.
  static const _relockAfterBackground = Duration(minutes: 2);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _backgroundedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final backgroundedAt = _backgroundedAt;
      _backgroundedAt = null;
      if (backgroundedAt == null) return;
      final wasBackgroundedLongEnough =
          DateTime.now().difference(backgroundedAt) >= _relockAfterBackground;
      if (wasBackgroundedLongEnough && _shouldLock() && !_locked) {
        setState(() => _locked = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (widget.child != null) widget.child!,
        if (_locked)
          _LockScreen(onUnlocked: () => setState(() => _locked = false)),
      ],
    );
  }
}

class _LockScreen extends ConsumerStatefulWidget {
  const _LockScreen({required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  ConsumerState<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<_LockScreen> {
  final _bio = BiometricService();
  final _pin = const PinService();
  String _entered = '';
  bool _error = false;
  bool _biometricBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
  }

  Future<void> _tryBiometric() async {
    // Defensive: the button already disables itself while busy, but the
    // very first call comes from initState's postFrameCallback rather
    // than a tap, so this guards that path too against ever overlapping
    // with a manual retry.
    if (!_bio.isEnabled || _biometricBusy) return;
    setState(() => _biometricBusy = true);
    final ok = await _bio.authenticate(reason: 'Unlock WAVEBREAK');
    if (!mounted) return;
    setState(() => _biometricBusy = false);
    if (ok) widget.onUnlocked();
  }

  Future<void> _onDigit(String digit) async {
    if (_entered.length >= 6) return;
    setState(() {
      _entered += digit;
      _error = false;
    });
    if (_entered.length < 4) return;
    // Auto-submit once a plausible PIN length is reached rather than
    // requiring a separate "confirm" tap — one less step to unlock.
    final ok = await _pin.verify(_entered);
    if (!mounted) return;
    if (ok) {
      unawaited(HapticFeedback.mediumImpact());
      widget.onUnlocked();
      return;
    }
    if (_entered.length == 6) {
      unawaited(HapticFeedback.heavyImpact());
      setState(() {
        _error = true;
        _entered = '';
      });
    }
  }

  void _onBackspace() {
    if (_entered.isEmpty) return;
    setState(() {
      _entered = _entered.substring(0, _entered.length - 1);
      _error = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final showPinPad = _pin.isSet;
    return Material(
      color: WbColors.midnight,
      child: OceanBackground(
        illuminate: true,
        animateWaves: true,
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 56),
              const WavebreakMark(size: 56, glow: true),
              const SizedBox(height: 20),
              Text(
                s.unlockWavebreak,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (showPinPad) ...[
                PinDots(length: _entered.length, error: _error),
                if (_error) ...[
                  const SizedBox(height: 10),
                  Text(
                    s.incorrectPin,
                    style: const TextStyle(color: WbColors.error, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 32),
                PinKeypad(onDigit: _onDigit, onBackspace: _onBackspace),
                if (_bio.isEnabled) ...[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _biometricBusy ? null : _tryBiometric,
                    icon: const Icon(Icons.fingerprint_rounded, size: 20),
                    label: Text(s.faceIdTouchId),
                  ),
                ],
              ] else ...[
                _biometricBusy
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : TextButton.icon(
                        onPressed: _tryBiometric,
                        icon: const Icon(Icons.fingerprint_rounded, size: 22),
                        label: Text(s.tryAgain),
                      ),
              ],
              const Spacer(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
