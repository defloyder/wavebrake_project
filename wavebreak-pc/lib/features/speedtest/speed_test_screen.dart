import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/vpn/speed_test_controller.dart';
import '../shared/menu_button.dart';
import '../shared/ocean_background.dart';
import '../shared/wave_params.dart';
import '../shared/wb_card.dart';
import '../shell/app_shell.dart';
import 'speedometer_gauge.dart';

/// A reasonable ceiling for the gauge's sweep — most mobile/VPN
/// connections this app will ever measure land well under this, and a
/// connection that somehow exceeds it just pins the needle at 100%
/// rather than the gauge needing to rescale live (which would make the
/// sweep itself misleading — the same 50 Mbps would paint a different
/// arc position depending on what else happened during the test).
const _gaugeMaxMbps = 250.0;

class SpeedTestScreen extends ConsumerWidget {
  const SpeedTestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final state = ref.watch(speedTestControllerProvider);
    final notifier = ref.read(speedTestControllerProvider.notifier);

    final phaseLabel = switch (state.status) {
      SpeedTestStatus.testingLatency => s.speedTestTestingLatency,
      SpeedTestStatus.testingDownload => s.speedTestDownloading,
      SpeedTestStatus.testingUpload => s.speedTestUploading,
      SpeedTestStatus.idle => s.speedTest,
      SpeedTestStatus.done => s.speedTestDone,
      SpeedTestStatus.failed => s.speedTestFailed,
    };

    // While running, the gauge tracks the live sample. Once done, it
    // settles on whichever leg finished last (download runs first, so
    // that's upload) rather than snapping back to zero — a completed
    // test should still visibly show a result on the dial, not just in
    // the numbers below it.
    final gaugeValue = state.isRunning
        ? state.liveMbps
        : (state.uploadMbps ?? state.downloadMbps ?? 0);

    final waves = ref.watch(appWaveParamsProvider);

    // A real top-level tab now (its own bottom-nav destination — see
    // app_shell.dart), not a screen pushed on top of another one, so it
    // matches Home/Settings/Locations' own pattern (OceanBackground +
    // ListView, no back button, MenuButton only on desktop where there's
    // a rail to open) instead of DetailScaffold's back-button header.
    // DetailScaffold's header sat at a different vertical position than
    // this pattern's plain title row — that mismatch was the actual
    // cause of the offline banner overlapping this screen's title
    // specifically; matching the same header shape every other tab uses
    // means the banner's existing clearance now applies here too.
    return LayoutBuilder(
      builder: (context, outer) {
        final isDesktop = outer.maxWidth >= 820;
        return OceanBackground(
          illuminate: true,
          tint: waves.tint,
          waveSpeed: waves.speed,
          waveAmplitude: waves.amplitude,
          maxContentWidth: isDesktop ? 640 : 560,
          child: SafeArea(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                isDesktop ? 12 : kMobileBottomBarReserve + 12,
              ),
              children: [
                Row(
                  children: [
                    if (isDesktop) ...[
                      const MenuButton(),
                      const SizedBox(width: 12),
                    ],
                    Text(
                      s.speedTest,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                AspectRatio(
                  aspectRatio: 1.7,
                  child: SpeedometerGauge(
                    valueMbps: gaugeValue,
                    maxMbps: _gaugeMaxMbps,
                    label: phaseLabel,
                    unit: 'Mbps',
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: _ResultCard(
                        icon: Icons.arrow_downward_rounded,
                        label: s.speedTestDownload,
                        value: state.downloadMbps,
                        highlighted:
                            state.status == SpeedTestStatus.testingDownload,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ResultCard(
                        icon: Icons.arrow_upward_rounded,
                        label: s.speedTestUpload,
                        value: state.uploadMbps,
                        highlighted:
                            state.status == SpeedTestStatus.testingUpload,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: state.isRunning ? null : notifier.run,
                    style: FilledButton.styleFrom(
                      backgroundColor: WbColors.waveCyan,
                      foregroundColor: WbColors.midnight,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      state.isRunning
                          ? phaseLabel
                          : state.status == SpeedTestStatus.idle
                              ? s.speedTestStart
                              : s.speedTestRetest,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.highlighted,
  });

  final IconData icon;
  final String label;
  final double? value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return WbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon,
                  size: 16,
                  color: highlighted ? WbColors.waveCyan : WbColors.ice60),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: highlighted ? WbColors.waveCyan : WbColors.ice60,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value != null
                ? '${value!.toStringAsFixed(value! >= 100 ? 0 : 1)} Mbps'
                : '–',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
