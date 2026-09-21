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
Future<bool?> showPinSetupScreen(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(builder: (_) => const PinSetupScreen()),
  );
}

class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key});

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
    return Scaffold(
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
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _confirming ? s.confirmPin : s.setPinCode,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
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
    );
  }
}
