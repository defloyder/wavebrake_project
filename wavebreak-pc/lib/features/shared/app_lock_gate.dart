import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/session_controller.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/biometric/biometric_service.dart';
import '../../services/pin/pin_service.dart';
import '../settings/pin_setup_screen.dart';
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

  // Bug 7: a set PIN IS the lock. It used to also need the separate
  // "App lock" switch, so setting a PIN alone never showed a prompt.
  // Biometrics are only an alternative way to pass a PIN lock.
  static bool _shouldLock() => const PinService().isSet;

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
  // app re-locks it.
  //
  // This used to be 2 minutes, which is where the actual real-device
  // security bug this comment now documents came from: a product owner
  // swiped the app away from Recents (a deliberate close, not a trivial
  // app-switch) and reopened it well within that window, and account/
  // subscription/connection-status content was sitting there fully
  // visible and interactive with no lock prompt at all — a real exposure
  // on a security-sensitive VPN app, not just a UX rough edge. A handful
  // of seconds is still comfortably longer than the trivial-blip cases
  // above (a permission dialog round-trip, a BiometricPrompt's own
  // spurious pause/resume) while closing the multi-minute window where a
  // deliberately-closed-and-reopened app stayed completely unprotected.
  // Bug 7 spec: re-lock after more than N minutes in the background
  // (N = 1). A cold start (including a swipe-away) always locks via the
  // initial _shouldLock() above.
  static const _relockAfterBackground = Duration(minutes: 1);

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
    if (!ok) return;
    if (!_pin.isSet) {
      // Migration path: biometric lock could be turned on before a PIN
      // was a mandatory fallback (see security_screen.dart's own
      // comment), so an existing install can reach this point with
      // biometric-only lock and no escape hatch at all. This is the one
      // moment identity is actually confirmed, so close the gap right
      // here rather than risk the user backgrounding the app again
      // before ever being asked — non-dismissible: skip it and the lock
      // stays exactly as unrecoverable as it was a moment ago.
      final saved = await showPinSetupScreen(
        context,
        dismissible: false,
        subtitle: ref.read(stringsProvider).pinRequiredForBiometric,
      );
      if (!mounted || saved != true) return;
    }
    widget.onUnlocked();
  }

  /// Escape hatch for the state this whole change exists to fix: an
  /// install where biometric lock is on, no PIN was ever set (either it
  /// never got the mandatory-PIN migration prompt above because biometric
  /// itself has stopped authenticating at all, or this build is the very
  /// first one to reach the device), and the fingerprint/face scan simply
  /// won't succeed. Logging out doesn't bypass anything security-wise —
  /// it requires the same real credentials a fresh install would — but it
  /// unconditionally clears the local biometric flag (see
  /// SessionController.forceLogout), so app lock has nothing left to
  /// enforce and the user gets back into their own account rather than
  /// being stuck forever short of reinstalling.
  Future<void> _logOutToEscape() async {
    // Also the escape from a forgotten PIN (bug 7): the PIN goes with the
    // session, and getting back in needs the real account password.
    await _pin.clear();
    await ref.read(sessionControllerProvider.notifier).forceLogout();
    if (!mounted) return;
    widget.onUnlocked();
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
          // Scrolls instead of overflowing on short screens (the PIN pad
          // plus the log-out escape don't fit everywhere); on normal
          // screens IntrinsicHeight keeps the Spacers' centered layout.
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const SizedBox(height: 56),
                      const WavebreakMark(size: 56, glow: true),
                      const SizedBox(height: 20),
                      Text(
                        s.unlockWavebreak,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      if (showPinPad) ...[
                        PinEntry(s: s, onVerified: widget.onUnlocked),
                        if (_bio.isEnabled) ...[
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: _biometricBusy ? null : _tryBiometric,
                            icon:
                                const Icon(Icons.fingerprint_rounded, size: 20),
                            label: Text(s.faceIdTouchId),
                          ),
                        ],
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _biometricBusy ? null : _logOutToEscape,
                          child: Text(
                            s.troubleUnlockingLogOut,
                            style: const TextStyle(
                                color: WbColors.ice60, fontSize: 13),
                          ),
                        ),
                      ] else ...[
                        _biometricBusy
                            ? const CircularProgressIndicator(strokeWidth: 2)
                            : TextButton.icon(
                                onPressed: _tryBiometric,
                                icon: const Icon(Icons.fingerprint_rounded,
                                    size: 22),
                                label: Text(s.tryAgain),
                              ),
                        // Biometric-only lock, no PIN ever set — this is exactly
                        // the "permanently locked out" state a flaky scan used to
                        // leave someone in with no way back short of reinstalling.
                        // Always visible here, not tucked behind repeated failures
                        // — a user who already knows the scan isn't working
                        // shouldn't have to keep failing it first to find the way
                        // out.
                        const SizedBox(height: 20),
                        TextButton(
                          onPressed: _biometricBusy ? null : _logOutToEscape,
                          child: Text(
                            s.troubleUnlockingLogOut,
                            style: const TextStyle(
                                color: WbColors.ice60, fontSize: 13),
                          ),
                        ),
                      ],
                      const Spacer(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
