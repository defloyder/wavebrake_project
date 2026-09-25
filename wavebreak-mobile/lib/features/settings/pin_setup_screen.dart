import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/pin/pin_service.dart';
import '../shared/ocean_background.dart';
import '../shared/pin_keypad.dart';
import '../shared/wave_params.dart';

/// Two-step "enter, then confirm" PIN setup. Pushed as a full-screen modal
/// (not a go_router route — it's a transient flow, not a place worth
/// bookmarking). Pops `true` once a PIN is saved, `null`/`false` if the
/// user backs out.
///
/// [dismissible] false removes the close button and blocks the system back
/// gesture/button — for the cases where skipping isn't a safe option: a PIN
/// is the only fallback biometric lock has, so once biometric is on (or,
/// for an existing install from before this was enforced, the moment a
/// biometric-only user next unlocks successfully) a PIN has to actually get
/// set, not just be offered. [subtitle], when given, explains why —
/// exactly what a non-dismissible modal that showed up unprompted most
/// needs.
Future<bool?> showPinSetupScreen(
  BuildContext context, {
  bool dismissible = true,
  String? subtitle,
}) {
  return Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(
      builder: (_) =>
          PinSetupScreen(dismissible: dismissible, subtitle: subtitle),
    ),
  );
}

class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key, this.dismissible = true, this.subtitle});

  final bool dismissible;
  final String? subtitle;

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  final _pin = const PinService();
  String _first = '';
  String _entered = '';
  bool _confirming = false;
  bool _error = false;

  void _onDigit(String digit) {
    if (_entered.length >= 6) return;
    setState(() {
      _entered += digit;
      _error = false;
    });
  }

  void _onBackspace() {
    if (_entered.isEmpty) return;
    setState(() {
      _entered = _entered.substring(0, _entered.length - 1);
      _error = false;
    });
  }

  Future<void> _onNext() async {
    if (_entered.length < 4) return;
    if (!_confirming) {
      unawaited(HapticFeedback.selectionClick());
      setState(() {
        _first = _entered;
        _entered = '';
        _confirming = true;
      });
      return;
    }
    if (_entered != _first) {
      unawaited(HapticFeedback.heavyImpact());
      setState(() {
        _error = true;
        _entered = '';
        _confirming = false;
        _first = '';
      });
      return;
    }
    await _pin.setPin(_entered);
    unawaited(HapticFeedback.mediumImpact());
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final waves = ref.watch(appWaveParamsProvider);
    return PopScope(
      // Blocks the system back gesture/button too, not just the on-screen
      // close button — otherwise a non-dismissible PIN setup (the whole
      // point of which is "this has to happen before we unlock/enable
      // biometric") could still be swiped away on Android with nothing set.
      canPop: widget.dismissible,
      child: Scaffold(
        body: OceanBackground(
          illuminate: true,
          tint: waves.tint,
          waveSpeed: waves.speed,
          waveAmplitude: waves.amplitude,
          child: SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: widget.dismissible
                        ? IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded),
                          )
                        : const SizedBox(height: 48),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _confirming ? s.confirmPin : s.setPinCode,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600),
                ),
                if (!_confirming && widget.subtitle != null) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      widget.subtitle!,
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: WbColors.ice60, fontSize: 13),
                    ),
                  ),
                ],
                const Spacer(),
                PinDots(length: _entered.length, error: _error),
                if (_error) ...[
                  const SizedBox(height: 10),
                  Text(
                    s.pinsDontMatch,
                    style: const TextStyle(color: WbColors.error, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 32),
                PinKeypad(onDigit: _onDigit, onBackspace: _onBackspace),
                const SizedBox(height: 20),
                SizedBox(
                  width: 220,
                  height: 52,
                  child: FilledButton(
                    onPressed: _entered.length >= 4 ? _onNext : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: WbColors.waveCyan,
                      foregroundColor: WbColors.midnight,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(_confirming ? s.enable : s.continueLabel),
                  ),
                ),
                const Spacer(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
