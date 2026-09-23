import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/vpn/speed_test_controller.dart';
import '../shared/menu_button.dart';
import '../shared/ocean_background.dart';
import '../shared/wave_params.dart';
import '../shared/wb_card.dart';
import '../shell/app_shell.dart';
import 'wave_meter.dart';

/// A reasonable ceiling for the meter's fill — most mobile/VPN
/// connections this app will ever measure land well under this, and a
/// connection that somehow exceeds it just fills the porthole all the
/// way rather than needing to rescale live (which would make the fill
/// level itself misleading — the same 50 Mbps would paint a different
/// level depending on what else happened during the test).
const _meterMaxMbps = 250.0;

String _formatMbps(double? value) {
  if (value == null) return '–';
  return value.toStringAsFixed(value >= 100 ? 0 : 1);
}

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

    final visualState = switch (state.status) {
      SpeedTestStatus.testingLatency ||
      SpeedTestStatus.testingDownload ||
      SpeedTestStatus.testingUpload =>
        WaveMeterVisualState.running,
      SpeedTestStatus.idle => WaveMeterVisualState.idle,
      SpeedTestStatus.done => WaveMeterVisualState.done,
      SpeedTestStatus.failed => WaveMeterVisualState.failed,
    };

    // While running, the meter tracks the live throughput sample (the
    // latency phase has no throughput of its own, so it just holds at
    // zero — the phase label and stepper below are what carry "latency
    // is what's happening right now", not the fill level). Once done, it
    // settles on whichever leg finished last (download runs first, so
    // that's upload) rather than snapping back to empty — a completed
    // test should still visibly show a result in the porthole, not just
    // in the numbers below it.
    final meterValue = state.isRunning
        ? (state.status == SpeedTestStatus.testingLatency
            ? 0.0
            : state.liveMbps)
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
                const SizedBox(height: 8),
                // Always names what's actively being measured (or that
                // nothing is yet, or that it's finished/failed) right
                // under the title — the porthole and its label say the
                // same thing, but this is the plain-language version
                // that's readable at a glance without parsing the
                // animation, exactly the "unclear what's happening"
                // complaint this redesign exists to fix.
                Text(
                  switch (state.status) {
                    SpeedTestStatus.idle => s.speedTestIdleHint,
                    SpeedTestStatus.done => s.speedTestDoneHint,
                    SpeedTestStatus.failed => s.speedTestFailedHint,
                    _ => phaseLabel,
                  },
                  style: const TextStyle(color: WbColors.ice60, fontSize: 13),
                ),
                const SizedBox(height: 20),
                AspectRatio(
                  aspectRatio: 1,
                  child: WaveMeter(
                    visualState: visualState,
                    valueMbps: meterValue,
                    maxMbps: _meterMaxMbps,
                    unit: 'Mbps',
                    label: phaseLabel,
                  ),
                ),
                const SizedBox(height: 8),
                // Determinate progress for whichever leg is actively
                // running — a clear "how far through this is" signal
                // distinct from the porthole's own live-speed reading.
                // Latency has no meaningful sub-progress (one TCP
                // connect, not a multi-second transfer), so it shows an
                // indeterminate bar instead of a fake determinate one.
                _PhaseProgress(status: state.status, progress: state.progress),
                const SizedBox(height: 20),
                _PhaseStepper(state: state, s: s),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _ResultCard(
                        icon: Icons.speed_rounded,
                        label: s.speedTestLatency,
                        value: state.latencyMs != null
                            ? '${state.latencyMs} ms'
                            : '–',
                        highlighted:
                            state.status == SpeedTestStatus.testingLatency,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ResultCard(
                        icon: Icons.arrow_downward_rounded,
                        label: s.speedTestDownload,
                        value: '${_formatMbps(state.downloadMbps)} Mbps',
                        highlighted:
                            state.status == SpeedTestStatus.testingDownload,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ResultCard(
                        icon: Icons.arrow_upward_rounded,
                        label: s.speedTestUpload,
                        value: '${_formatMbps(state.uploadMbps)} Mbps',
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

/// A determinate bar while download/upload run ([SpeedTestState.progress]
/// already tracks 0..1 through the current leg — see
/// SpeedTestService/_ProgressSampler), an indeterminate one for latency
/// (a single TCP connect has no meaningful sub-progress to report), and
/// nothing at all once idle/done/failed — a progress bar sitting at some
/// arbitrary leftover position after the test ends would read as
/// "unfinished", which is exactly backwards.
class _PhaseProgress extends StatelessWidget {
  const _PhaseProgress({required this.status, required this.progress});

  final SpeedTestStatus status;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final visible = status == SpeedTestStatus.testingLatency ||
        status == SpeedTestStatus.testingDownload ||
        status == SpeedTestStatus.testingUpload;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: visible ? 1 : 0,
      child: SizedBox(
        height: 4,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: status == SpeedTestStatus.testingLatency ? null : progress,
            minHeight: 4,
            backgroundColor: WbColors.ice08,
            valueColor: const AlwaysStoppedAnimation(WbColors.waveCyan),
          ),
        ),
      ),
    );
  }
}

/// Three steps, always visible in the same order latency → download →
/// upload run in — the "always know what's actively being measured, and
/// what's still to come" signal a bare phase label alone doesn't give:
/// seeing "download" highlighted while "upload" still sits dim tells you
/// there's another whole leg coming, not just what's happening this
/// instant.
class _PhaseStepper extends StatelessWidget {
  const _PhaseStepper({required this.state, required this.s});

  final SpeedTestState state;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StepDot(
            label: s.speedTestLatency,
            active: state.status == SpeedTestStatus.testingLatency,
            done: state.latencyMs != null,
            failed: false,
          ),
        ),
        _StepConnector(
            lit: state.latencyMs != null ||
                state.status.index > SpeedTestStatus.testingLatency.index),
        Expanded(
          child: _StepDot(
            label: s.speedTestDownload,
            active: state.status == SpeedTestStatus.testingDownload,
            done: state.downloadMbps != null,
            failed: state.status == SpeedTestStatus.failed &&
                state.downloadMbps == null,
          ),
        ),
        _StepConnector(
            lit: state.downloadMbps != null ||
                state.status.index > SpeedTestStatus.testingDownload.index),
        Expanded(
          child: _StepDot(
            label: s.speedTestUpload,
            active: state.status == SpeedTestStatus.testingUpload,
            done: state.uploadMbps != null,
            failed: state.status == SpeedTestStatus.failed &&
                state.uploadMbps == null,
          ),
        ),
      ],
    );
  }
}

class _StepConnector extends StatelessWidget {
  const _StepConnector({required this.lit});

  final bool lit;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 20,
      height: 2,
      margin: const EdgeInsets.only(bottom: 18),
      color: lit ? WbColors.waveCyan.withValues(alpha: 0.5) : WbColors.ice08,
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.label,
    required this.active,
    required this.done,
    required this.failed,
  });

  final String label;
  final bool active;
  final bool done;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final color = failed
        ? WbColors.error
        : done
            ? WbColors.oceanTeal
            : active
                ? WbColors.waveCyan
                : WbColors.ice60;
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (done || active)
                ? color.withValues(alpha: 0.18)
                : Colors.transparent,
            border: Border.all(color: color, width: active ? 2 : 1.4),
          ),
          child: done
              ? Icon(Icons.check_rounded, size: 13, color: color)
              : failed
                  ? Icon(Icons.close_rounded, size: 13, color: color)
                  : active
                      ? Padding(
                          padding: const EdgeInsets.all(6),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(color),
                          ),
                        )
                      : null,
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: color,
            letterSpacing: 0.2,
          ),
        ),
      ],
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
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return WbCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon,
                  size: 14,
                  color: highlighted ? WbColors.waveCyan : WbColors.ice60),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: highlighted ? WbColors.waveCyan : WbColors.ice60,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
