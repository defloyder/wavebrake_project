import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/vpn/connection_manager.dart';
import '../../services/vpn/speed_test_controller.dart';
import '../home/location_bar.dart';
import '../immersive/immersive_clock.dart';
import '../immersive/immersive_colors.dart';
import '../immersive/tinted_glass.dart';
import '../shared/flag_icon.dart';
import '../shared/ocean_background.dart';
import '../shell/app_shell.dart';
import 'wave_tunnel.dart';

String _formatMbps(double? value) {
  if (value == null) return '–';
  return value.toStringAsFixed(value >= 100 ? 0 : 1);
}

const _tabular = [FontFeature.tabularFigures()];

/// Speed test (V5): the "wave tunnel" scene with the live number in its
/// calm centre, a three-step stepper (latency → download → upload), the
/// three results and one action. Real measurements only (see
/// [SpeedTestController]); the tunnel's flow follows the live throughput.
class SpeedTestScreen extends ConsumerWidget {
  const SpeedTestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final state = ref.watch(speedTestControllerProvider);
    final notifier = ref.read(speedTestControllerProvider.notifier);
    final location =
        ref.watch(connectionManagerProvider.select((c) => c.location));

    final phaseLabel = switch (state.status) {
      SpeedTestStatus.testingLatency => s.speedTestTestingLatency,
      SpeedTestStatus.testingDownload => s.speedTestDownloading,
      SpeedTestStatus.testingUpload => s.speedTestUploading,
      SpeedTestStatus.idle => s.speedTest,
      SpeedTestStatus.done => s.speedTestDone,
      SpeedTestStatus.failed => s.speedTestFailed,
    };
    final tunnelPhase = switch (state.status) {
      SpeedTestStatus.testingLatency => TunnelPhase.latency,
      SpeedTestStatus.testingDownload => TunnelPhase.download,
      SpeedTestStatus.testingUpload => TunnelPhase.upload,
      SpeedTestStatus.idle => TunnelPhase.idle,
      SpeedTestStatus.done => TunnelPhase.done,
      SpeedTestStatus.failed => TunnelPhase.failed,
    };
    // Number in the centre: live throughput while a leg runs, the ping
    // while measuring latency, the download result once done.
    final (double? centreValue, String centreUnit) = switch (state.status) {
      SpeedTestStatus.testingLatency => (state.latencyMs?.toDouble(), 'ms'),
      SpeedTestStatus.testingDownload || SpeedTestStatus.testingUpload => (
          state.liveMbps,
          'Mbps'
        ),
      SpeedTestStatus.done => (state.downloadMbps, 'Mbps'),
      _ => (null, 'Mbps'),
    };
    final tunnelMbps =
        state.isRunning && state.status != SpeedTestStatus.testingLatency
            ? state.liveMbps
            : state.status == SpeedTestStatus.done
                ? (state.downloadMbps ?? 0) * 0.25
                : 0.0;
    final (place, _) = splitPlaceAndProtocol(location.city);
    final proto = protocolLabel(location);

    return OceanBackground(
      illuminate: true,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              20, 12, 20, kMobileBottomBarReserve + 16),
          children: [
            Text(s.speedTest,
                style: const TextStyle(fontFamily: 'serif', fontSize: 30)),
            const SizedBox(height: 4),
            Row(
              children: [
                if (!location.isAuto && location.countryCode.isNotEmpty) ...[
                  FlagIcon(countryCode: location.countryCode, width: 20),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    [
                      if (place.isNotEmpty) place else location.country,
                      if (proto != null) proto,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Ic.textMuted, fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, c) {
                final side = c.maxWidth.clamp(220.0, 360.0);
                return Center(
                  child: SizedBox(
                    width: side,
                    height: side,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: ExcludeSemantics(
                            child: RepaintBoundary(
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(end: tunnelMbps),
                                duration: const Duration(milliseconds: 700),
                                curve: Curves.easeOutCubic,
                                builder: (context, mbps, _) => CustomPaint(
                                  painter: WaveTunnelPainter(
                                    time: ImmersiveClock.of(context),
                                    phase: tunnelPhase,
                                    mbps: mbps,
                                    progress: state.progress,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        _CentreReadout(
                          value: centreValue,
                          unit: centreUnit,
                          label: phaseLabel,
                          done: state.status == SpeedTestStatus.done,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              switch (state.status) {
                SpeedTestStatus.idle => s.speedTestIdleHint,
                SpeedTestStatus.done => s.speedTestDoneHint,
                SpeedTestStatus.failed => s.speedTestFailedHint,
                _ => ' ',
              },
              textAlign: TextAlign.center,
              style: const TextStyle(color: Ic.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            _Stepper(state: state, s: s),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _Result(
                    icon: Icons.speed_rounded,
                    label: s.speedTestLatency,
                    text:
                        state.latencyMs != null ? '${state.latencyMs} ms' : '–',
                    active: state.status == SpeedTestStatus.testingLatency,
                    color: const Color(0xFFBFEFEA),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Result(
                    icon: Icons.arrow_downward_rounded,
                    label: s.speedTestDownload,
                    text: '${_formatMbps(state.downloadMbps)} Mbps',
                    active: state.status == SpeedTestStatus.testingDownload,
                    color: Ic.arctic,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Result(
                    icon: Icons.arrow_upward_rounded,
                    label: s.speedTestUpload,
                    text: '${_formatMbps(state.uploadMbps)} Mbps',
                    active: state.status == SpeedTestStatus.testingUpload,
                    color: Ic.crimson,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: state.isRunning ? null : notifier.run,
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                child: Text(
                  state.isRunning
                      ? phaseLabel
                      : state.status == SpeedTestStatus.idle
                          ? s.speedTestStart
                          : s.speedTestRetest,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CentreReadout extends StatelessWidget {
  const _CentreReadout({
    required this.value,
    required this.unit,
    required this.label,
    required this.done,
  });

  final double? value;
  final String unit;
  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    const numberStyle = TextStyle(
      color: Ic.text,
      fontSize: 44,
      height: 1.1,
      fontWeight: FontWeight.w600,
      fontFeatures: _tabular,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 52,
          child: value == null
              ? const Text('—', style: numberStyle)
              : TweenAnimationBuilder<double>(
                  tween: Tween(end: value),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => Text(
                    unit == 'ms' ? v.round().toString() : _formatMbps(v),
                    style: numberStyle,
                  ),
                ),
        ),
        Text(unit,
            style: const TextStyle(color: Ic.textSecondary, fontSize: 13)),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (done) ...[
              const Icon(Icons.check_rounded, color: Ic.arctic, size: 16),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(
                    color: done ? Ic.arctic : Ic.textMuted, fontSize: 13)),
          ],
        ),
      ],
    );
  }
}

/// latency → download → upload, with done (check) / failed (cross) marks.
class _Stepper extends StatelessWidget {
  const _Stepper({required this.state, required this.s});

  final SpeedTestState state;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final status = state.status;
    int order(SpeedTestStatus st) => switch (st) {
          SpeedTestStatus.testingLatency => 0,
          SpeedTestStatus.testingDownload => 1,
          SpeedTestStatus.testingUpload => 2,
          SpeedTestStatus.done => 3,
          _ => -1,
        };
    final current = order(status);
    final results = [
      state.latencyMs != null,
      state.downloadMbps != null,
      state.uploadMbps != null,
    ];
    final labels = [s.speedTestLatency, s.speedTestDownload, s.speedTestUpload];
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0)
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 1.5,
                color: current >= i || results[i - 1]
                    ? Ic.arctic.withValues(alpha: 0.6)
                    : Ic.glassBorder,
              ),
            ),
          _StepDot(
            label: labels[i],
            active: current == i,
            done: results[i] && (current > i || status == SpeedTestStatus.done),
            failed: status == SpeedTestStatus.failed && !results[i],
          ),
        ],
      ],
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
        ? Ic.amber
        : done || active
            ? Ic.arctic
            : Ic.textMuted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? Ic.arctic.withValues(alpha: 0.16) : null,
            border: Border.all(color: color.withValues(alpha: 0.8), width: 1.5),
          ),
          child: Icon(
            failed
                ? Icons.close_rounded
                : done
                    ? Icons.check_rounded
                    : Icons.circle,
            size: done || failed ? 16 : 6,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: color, fontSize: 11)),
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.icon,
    required this.label,
    required this.text,
    required this.active,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String text;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TintedGlass(
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      tint: active ? color : null,
      strength: active ? 1.4 : 1.0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyle(
                        color: active ? color : WbColors.muted, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            style: const TextStyle(
              color: Ic.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFeatures: _tabular,
            ),
          ),
        ],
      ),
    );
  }
}
