import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../shared/ocean_background.dart';
import '../shared/wave_params.dart';
import '../shared/wavebreak_mark.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final waves = ref.watch(appWaveParamsProvider);
    return Scaffold(
      body: OceanBackground(
        illuminate: true,
        tint: waves.tint,
        waveSpeed: waves.speed,
        waveAmplitude: waves.amplitude,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const WavebreakMark(size: 96, glow: true),
              const SizedBox(height: 28),
              const WavebreakWordmark(size: 16),
              const SizedBox(height: 40),
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: WbColors.waveCyan,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                s.preparingApp,
                style: const TextStyle(color: WbColors.ice60, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
