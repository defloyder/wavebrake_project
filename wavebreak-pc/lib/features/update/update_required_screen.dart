import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/session_controller.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../shared/ocean_background.dart';
import '../shared/wave_params.dart';
import '../shared/wavebreak_mark.dart';

class UpdateRequiredScreen extends ConsumerWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(sessionControllerProvider).config;
    final s = ref.watch(stringsProvider);
    final updateUrl = config.websiteUrl;
    final waves = ref.watch(appWaveParamsProvider);

    return Scaffold(
      body: OceanBackground(
        illuminate: true,
        tint: waves.tint,
        waveSpeed: waves.speed,
        waveAmplitude: waves.amplitude,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const WavebreakMark(size: 72, glow: true),
                  const SizedBox(height: 28),
                  Text(
                    s.updateRequiredTitle,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    s.updateRequiredBody,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: WbColors.ice60),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: updateUrl == null
                          ? null
                          : () => launchUrl(Uri.parse(updateUrl)),
                      style: FilledButton.styleFrom(
                        backgroundColor: WbColors.waveCyan,
                        foregroundColor: WbColors.midnight,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(s.updateNow),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
