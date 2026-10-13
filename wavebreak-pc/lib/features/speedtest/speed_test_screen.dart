import '../../core/theme/wb_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/vpn/connection_manager.dart';
import '../../services/vpn/speed_test_controller.dart';
import '../home/location_bar.dart';
import '../shared/menu_button.dart';
import '../shared/ocean_background.dart';
import '../shared/wave_params.dart';
import '../immersive/tinted_glass.dart';
import '../shell/app_shell.dart';
import 'speed_gauge.dart';
import 'wave_meter.dart' show WaveMeterVisualState;

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
    final loc = ref.watch(connectionManagerProvider).location;
    final (place, _) = splitPlaceAndProtocol(loc.city);
    final serverLine = [
      if (place.isNotEmpty) place else loc.country,
      if (protocolLabel(loc) case final p?) p,
    ].join(' · ');

    final statusText = Text(
      switch (state.status) {
        SpeedTestStatus.idle => s.speedTestIdleHint,
        SpeedTestStatus.done => s.speedTestDoneHint,
        SpeedTestStatus.failed => s.speedTestFailedHint,
        _ => phaseLabel,
      },
      style: const TextStyle(color: WbColors.ice60, fontSize: 13),
    );
    final meter = SpeedGauge(
      visualState: visualState,
      valueMbps: meterValue,
      maxMbps: _meterMaxMbps,
      unit: 'Mbps',
      // Idle: the title already says it.
      label: state.status == SpeedTestStatus.idle ? '' : phaseLabel,
      accent: context.accent,
    );
    // One glass block of rows, like every settings group (owner, 13.10:
    // the page should look like the rest of the new design).
    final results = _Results(state: state, s: s);
    // While a test runs the button stops it (owner, 12.10).
    final button = SizedBox(
      width: double.infinity,
      child: state.isRunning
          ? OutlinedButton.icon(
              onPressed: notifier.cancel,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: WbColors.ice,
                side: const BorderSide(color: WbColors.ice60),
              ),
              icon: const Icon(Icons.close_rounded, size: 20),
              label: Text(s.cancel),
            )
          : FilledButton(
              onPressed: notifier.run,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child: Text(
                state.status == SpeedTestStatus.idle
                    ? s.speedTestStart
                    : s.speedTestRetest,
              ),
            ),
    );
    Widget title({required bool withMenu}) => Row(
          children: [
            if (withMenu) ...[
              const MenuButton(),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.speedTest,
                    style: const TextStyle(fontFamily: 'serif', fontSize: 30),
                  ),
                  // Which server is being measured (V5 header line).
                  Text(
                    serverLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: WbColors.muted, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        );

    // A real top-level tab now (its own bottom-nav destination — see
    // app_shell.dart), not a screen pushed on top of another one, so it
    // matches Home/Settings/Locations' own pattern (OceanBackground +
    // plain title row, no back button, MenuButton only on desktop where
    // there's a rail to open) instead of DetailScaffold's back-button
    // header — that header sat lower and the offline banner overlapped it.
    return LayoutBuilder(
      builder: (context, outer) {
        final isDesktop = outer.maxWidth >= 820;
        if (isDesktop) {
          // Desktop: the meter on the left sized to the window's height,
          // everything else in a column beside it. Stacked like the phone
          // layout, a full-width square meter plus the rest never fit a
          // desktop window and the page scrolled.
          return OceanBackground(
            illuminate: true,
            tint: waves.tint,
            waveSpeed: waves.speed,
            waveAmplitude: waves.amplitude,
            maxContentWidth: 1040,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title(withMenu: true),
                    const SizedBox(height: 16),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) {
                          final side = (box.maxHeight < box.maxWidth * 0.5
                                  ? box.maxHeight
                                  : box.maxWidth * 0.5)
                              .clamp(160.0, 520.0);
                          return Row(
                            children: [
                              SizedBox(width: side, height: side, child: meter),
                              const SizedBox(width: 36),
                              Expanded(
                                child: Center(
                                  child: SingleChildScrollView(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        statusText,
                                        const SizedBox(height: 14),
                                        _PhaseProgress(
                                            status: state.status,
                                            progress: state.progress),
                                        const SizedBox(height: 22),
                                        results,
                                        const SizedBox(height: 24),
                                        button,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return OceanBackground(
          illuminate: true,
          tint: waves.tint,
          waveSpeed: waves.speed,
          waveAmplitude: waves.amplitude,
          maxContentWidth: 560,
          // Full height: the background centres its child.
          child: SizedBox.expand(
            child: SafeArea(
              // One screen, no scrolling (owner, 12.10): the porthole takes
              // whatever height the rest leaves. Only a very short window
              // (landscape, split screen) scrolls, at a fixed height.
              child: LayoutBuilder(builder: (context, box) {
                final page = Padding(
                  // The button is the last thing on the page: a wider gap
                  // so it doesn't sit on the nav bar (owner, 06.10).
                  padding: const EdgeInsets.fromLTRB(
                      20, 12, 20, kMobileBottomBarReserve + 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      title(withMenu: false),
                      const SizedBox(height: 8),
                      // Always names what's actively being measured (or
                      // that nothing is yet, or that it's finished/failed)
                      // — the plain-language version of the porthole.
                      statusText,
                      const SizedBox(height: 12),
                      Expanded(child: meter),
                      const SizedBox(height: 8),
                      // Determinate progress for whichever leg is running;
                      // latency (one TCP connect) gets an indeterminate bar.
                      _PhaseProgress(
                          status: state.status, progress: state.progress),
                      const SizedBox(height: 16),
                      results,
                      const SizedBox(height: 20),
                      button,
                    ],
                  ),
                );
                const minHeight = 600.0;
                if (box.maxHeight >= minHeight) return page;
                return SingleChildScrollView(
                  child: SizedBox(height: minHeight, child: page),
                );
              }),
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
            valueColor: AlwaysStoppedAnimation(context.accent),
          ),
        ),
      ),
    );
  }
}

/// Latency, download and upload as rows of one glass block — the icon
/// tile, the name, and the reading on the right; the leg being measured
/// is lit in the accent with a spinner, a finished one gets its number,
/// one that failed an ✕.
class _Results extends StatelessWidget {
  const _Results({required this.state, required this.s});

  final SpeedTestState state;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final failed = state.status == SpeedTestStatus.failed;
    final rows = [
      _ResultRow(
        icon: Icons.timer_outlined,
        label: s.speedTestLatency,
        value: state.latencyMs != null ? '${state.latencyMs} ${s.unitMs}' : '–',
        active: state.status == SpeedTestStatus.testingLatency,
        done: state.latencyMs != null,
        failed: false,
      ),
      _ResultRow(
        icon: Icons.south_rounded,
        label: s.speedTestDownload,
        value: '${_formatMbps(state.downloadMbps)} Mbps',
        active: state.status == SpeedTestStatus.testingDownload,
        done: state.downloadMbps != null,
        failed: failed && state.downloadMbps == null,
      ),
      _ResultRow(
        icon: Icons.north_rounded,
        label: s.speedTestUpload,
        value: '${_formatMbps(state.uploadMbps)} Mbps',
        active: state.status == SpeedTestStatus.testingUpload,
        done: state.uploadMbps != null,
        failed: failed && state.uploadMbps == null,
      ),
    ];
    return TintedGlass(
      padding: EdgeInsets.zero,
      radius: 18,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Divider(
                  height: 1, thickness: 1, indent: 62, color: WbColors.ice08),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.active,
    required this.done,
    required this.failed,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool active;
  final bool done;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    final tone = failed
        ? WbColors.error
        : active
            ? accent
            : WbColors.ice;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: active ? accent.withValues(alpha: 0.08) : Colors.transparent,
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? accent.withValues(alpha: 0.18) : WbColors.ice08,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 18, color: tone),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 15.5,
                  color: active ? accent : WbColors.ice,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400),
            ),
          ),
          const SizedBox(width: 8),
          if (active)
            SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            )
          else if (failed)
            const Icon(Icons.close_rounded, size: 18, color: WbColors.error)
          else ...[
            Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            if (done) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check_rounded,
                  size: 16, color: WbColors.oceanTeal),
            ],
          ],
        ],
      ),
    );
  }
}
