import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/session_controller.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../core/theme/wb_theme.dart';
import '../../services/biometric/biometric_service.dart';
import '../../services/pin/pin_service.dart';
import '../immersive/immersive_clock.dart';
import '../immersive/tinted_glass.dart';
import '../immersive/wave_field.dart';
import '../settings/pin_setup_screen.dart';
import 'pin_keypad.dart';
import 'wave_params.dart';
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

/// Where the scan emblem is: at rest, a biometric prompt open, the
/// moment of success (rings burst outward) or a failed scan (amber).
enum _Scan { idle, scanning, success, failed }

/// The V5 lock screen (P13). The system BiometricPrompt can't be styled,
/// so this screen is built around it: the WAVEBREAK mark in scanning
/// rings, a status line saying what's happening (prompt open / not
/// recognized), the PIN pad, and a short burst of the rings on success
/// before the app shows. With "reduce motion" the rings stand still and
/// the app opens at once.
class _LockScreen extends ConsumerStatefulWidget {
  const _LockScreen({required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  ConsumerState<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<_LockScreen>
    with SingleTickerProviderStateMixin {
  final _bio = BiometricService();
  final _pin = const PinService();
  bool _biometricBusy = false;
  _Scan _scan = _Scan.idle;

  /// One-shot (success burst / failure shake) — never repeating; the
  /// idle and scanning motion runs on the shared ImmersiveClock.
  late final _burst = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 260));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
  }

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  Future<void> _succeed() async {
    if (ImmersiveClock.frozen(context)) {
      widget.onUnlocked();
      return;
    }
    setState(() => _scan = _Scan.success);
    await _burst.forward(from: 0);
    if (mounted) widget.onUnlocked();
  }

  Future<void> _tryBiometric() async {
    // Defensive: the button already disables itself while busy, but the
    // very first call comes from initState's postFrameCallback rather
    // than a tap, so this guards that path too against ever overlapping
    // with a manual retry.
    if (!_bio.isEnabled || _biometricBusy) return;
    final s = ref.read(stringsProvider);
    setState(() {
      _biometricBusy = true;
      _scan = _Scan.scanning;
    });
    final ok = await _bio.authenticate(reason: s.unlockWavebreak);
    if (!mounted) return;
    setState(() {
      _biometricBusy = false;
      _scan = ok ? _Scan.idle : _Scan.failed;
    });
    if (!ok) {
      if (!ImmersiveClock.frozen(context)) unawaited(_burst.forward(from: 0));
      return;
    }
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
        subtitle: s.pinRequiredForBiometric,
      );
      if (!mounted || saved != true) return;
    }
    await _succeed();
  }

  /// Escape hatch for an install where biometric lock is on, no PIN was
  /// ever set and the scan simply won't succeed, or for a forgotten PIN.
  /// Logging out doesn't bypass anything security-wise — getting back in
  /// needs the real account password — but it clears the local PIN and
  /// biometric flag (see SessionController.forceLogout), so the user gets
  /// back into their own account instead of reinstalling.
  Future<void> _logOutToEscape() async {
    await _pin.clear();
    await ref.read(sessionControllerProvider.notifier).forceLogout();
    if (!mounted) return;
    widget.onUnlocked();
  }

  String _status(AppStrings s, bool showPinPad) => switch (_scan) {
        _Scan.scanning => s.lockScanning,
        _Scan.failed => s.lockScanFailed,
        _ => showPinPad ? s.enterPin : s.lockUseBiometric,
      };

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final tint = ref.watch(appWaveParamsProvider).tint;
    final showPinPad = _pin.isSet;
    return Material(
      color: WbColors.midnight,
      child: Stack(
        children: [
          Positioned.fill(child: WaveField(tint: tint, intensity: 0.45)),
          SafeArea(
            // Scrolls instead of overflowing on short screens; on normal
            // screens IntrinsicHeight keeps the Spacers' centered layout.
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 700;
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            SizedBox(height: compact ? 4 : 48),
                            _ScanEmblem(
                              scan: _scan,
                              burst: _burst,
                              size: compact ? 64 : 128,
                            ),
                            SizedBox(height: compact ? 4 : 16),
                            Text(
                              s.unlockWavebreak,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontFamily: 'serif', fontSize: 24),
                            ),
                            const SizedBox(height: 6),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: Text(
                                _status(s, showPinPad),
                                key: ValueKey(_scan),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  height: 1.35,
                                  color: _scan == _Scan.failed
                                      ? WbColors.warning
                                      : WbColors.muted,
                                ),
                              ),
                            ),
                            const Spacer(),
                            SizedBox(height: compact ? 4 : 24),
                            if (showPinPad)
                              PinEntry(s: s, onVerified: _succeed),
                            if (_bio.isEnabled) ...[
                              const SizedBox(height: 12),
                              _BiometricButton(
                                label: showPinPad
                                    ? s.lockBiometricButton
                                    : s.tryAgain,
                                busy: _biometricBusy,
                                onPressed: _tryBiometric,
                              ),
                            ],
                            // The way out is always visible, not hidden
                            // behind repeated failed scans.
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed:
                                  _biometricBusy ? null : _logOutToEscape,
                              child: Text(
                                s.troubleUnlockingLogOut,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: WbColors.ice60, fontSize: 13),
                              ),
                            ),
                            const Spacer(),
                            SizedBox(height: compact ? 0 : 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Fingerprint button: a glass pill under the PIN pad.
class _BiometricButton extends StatelessWidget {
  const _BiometricButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IntrinsicWidth(
      child: TintedGlass(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        radius: 999,
        onTap: busy ? null : onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.fingerprint_rounded,
                size: 22, color: busy ? WbColors.ice60 : context.accent),
            const SizedBox(width: 10),
            Flexible(
              child: Text(label,
                  style: const TextStyle(fontSize: 15),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

/// The WAVEBREAK mark inside scanning rings. Idle: three rings breathe
/// slowly. Scanning: they brighten and a scan line sweeps the disc.
/// Success: they burst outward in teal. Failed: amber, a short shake.
/// Driven by the shared ImmersiveClock (frozen with reduce motion).
class _ScanEmblem extends StatelessWidget {
  const _ScanEmblem({
    required this.scan,
    required this.burst,
    required this.size,
  });

  final _Scan scan;
  final Animation<double> burst;
  final double size;

  @override
  Widget build(BuildContext context) {
    final time = ImmersiveClock.of(context);
    return SizedBox(
      width: size * 1.5,
      height: size * 1.5,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _ScanPainter(
                  repaint: Listenable.merge([time, burst]),
                  time: time,
                  burst: burst,
                  scan: scan,
                  accent: context.accent,
                  core: size / 2,
                ),
              ),
            ),
          ),
          WavebreakMark(size: size * 0.5, glow: true),
        ],
      ),
    );
  }
}

class _ScanPainter extends CustomPainter {
  _ScanPainter({
    required Listenable repaint,
    required this.time,
    required this.burst,
    required this.scan,
    required this.accent,
    required this.core,
  }) : super(repaint: repaint);

  final ValueListenable<double> time;
  final Animation<double> burst;
  final _Scan scan;
  final Color accent;

  /// Radius of the inner ring.
  final double core;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final b = burst.value;
    var c = size.center(Offset.zero);
    final color = switch (scan) {
      _Scan.success => WbColors.oceanTeal,
      _Scan.failed => WbColors.warning,
      _ => accent,
    };
    if (scan == _Scan.failed && b > 0 && b < 1) {
      c = c.translate(math.sin(b * math.pi * 6) * 6 * (1 - b), 0);
    }
    final active = scan == _Scan.scanning;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // Soft disc behind the mark.
    canvas.drawCircle(
      c,
      core,
      Paint()
        ..shader = RadialGradient(colors: [
          color.withValues(alpha: active ? 0.20 : 0.12),
          color.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: c, radius: core)),
    );

    for (var i = 0; i < 3; i++) {
      final phase = t * (active ? 1.6 : 0.6) + i * 2.1;
      var r = core * (0.74 + i * 0.16) + math.sin(phase) * core * 0.03;
      var alpha = (active ? 0.55 : 0.28) - i * 0.07;
      if (scan == _Scan.success) {
        r *= 1 + b * (0.35 + i * 0.15);
        alpha *= 1 - b;
      }
      canvas.drawCircle(
          c, r, ring..color = color.withValues(alpha: alpha.clamp(0.0, 1.0)));
    }

    if (active) {
      // A scan line sweeping the disc up and down.
      final y = math.sin(t * 2.4) * core * 0.72;
      final half = math.sqrt(math.max(0, core * core * 0.6 - y * y));
      if (half > 1) {
        final line = Rect.fromCenter(
            center: c.translate(0, y), width: half * 2, height: 14);
        canvas.drawRect(
          line,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0),
                color.withValues(alpha: 0.35),
                color.withValues(alpha: 0),
              ],
            ).createShader(line),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ScanPainter old) =>
      old.scan != scan || old.accent != accent || old.core != core;
}
