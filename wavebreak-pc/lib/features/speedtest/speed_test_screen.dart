import 'dart:ui' show DisplayFeatureType;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/personalization_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/vpn/connection_manager.dart';
import '../../services/vpn/speed_test_controller.dart';
import '../home/location_bar.dart';
import '../immersive/effects_quality.dart';
import '../shared/ocean_background.dart';
import '../shared/wave_params.dart';
import '../shell/app_shell.dart';
import 'tide_wave.dart';

String _formatMbps(double? value) {
  if (value == null) return '–';
  return value.toStringAsFixed(value >= 100 ? 0 : 1);
}

const _ink = Color(0xFFF6F0F2);
const _edge = Color(0xFF593344);
const _rule = Color(0xFF343844);

/// The unit symbol, the same in every language.
const _mbps = 'Mbps';

/// The speed test: the «Прилив» scene (owner's choice, 14.10) — a large
/// still reading above a perspective wave surface, compact results, an
/// explicit start button. Everything shown comes from
/// [speedTestControllerProvider]; starting a test never touches the VPN
/// or the chosen server.
class SpeedTestScreen extends ConsumerWidget {
  const SpeedTestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final state = ref.watch(speedTestControllerProvider);
    final notifier = ref.read(speedTestControllerProvider.notifier);
    final economy = ref.watch(effectsEconomyProvider);
    final still = ref.watch(personalizationProvider).reduceMotion ||
        MediaQuery.of(context).disableAnimations;

    final phase = switch (state.status) {
      SpeedTestStatus.idle => TidePhase.idle,
      SpeedTestStatus.testingLatency => TidePhase.ping,
      SpeedTestStatus.testingDownload => TidePhase.download,
      SpeedTestStatus.testingUpload => TidePhase.upload,
      SpeedTestStatus.done => TidePhase.done,
      SpeedTestStatus.failed => TidePhase.failed,
    };
    // The surface follows the controller's smoothed live reading during a
    // leg; once done it settles on the download result. The big number
    // is the same reading — never a simulated one.
    final double? reading = switch (state.status) {
      SpeedTestStatus.testingDownload ||
      SpeedTestStatus.testingUpload =>
        state.liveMbps,
      SpeedTestStatus.done => state.downloadMbps ?? state.uploadMbps,
      _ => null,
    };
    final phaseText = switch (state.status) {
      SpeedTestStatus.idle => s.speedTestIdleHint,
      SpeedTestStatus.testingLatency => s.speedTestTestingLatency,
      SpeedTestStatus.testingDownload => s.speedTestDownloading,
      SpeedTestStatus.testingUpload => s.speedTestUploading,
      SpeedTestStatus.done => s.speedTestDoneHint,
      SpeedTestStatus.failed => s.speedTestFailedHint,
    };
    // A screen reader hears the phase and, at the end, the result — not
    // every live sample.
    final announcement = state.status == SpeedTestStatus.done
        ? [
            phaseText,
            if (state.downloadMbps != null)
              '${s.speedTestDownload} ${_formatMbps(state.downloadMbps)} Mbps',
            if (state.uploadMbps != null)
              '${s.speedTestUpload} ${_formatMbps(state.uploadMbps)} Mbps',
            if (state.latencyMs != null)
              '${s.speedTestLatency} ${state.latencyMs} ${s.unitMs}',
          ].join(', ')
        : phaseText;

    final waves = ref.watch(appWaveParamsProvider);
    final loc = ref.watch(connectionManagerProvider).location;
    final (place, _) = splitPlaceAndProtocol(loc.city);
    final serverLine = [
      if (place.isNotEmpty) place else loc.country,
      if (protocolLabel(loc) case final p?) p,
    ].join(' · ');

    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.speedTest,
            style: const TextStyle(fontFamily: 'serif', fontSize: 30)),
        // Which server is being measured (V5 header line).
        Text(
          serverLine,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: WbColors.muted, fontSize: 14),
        ),
      ],
    );

    Widget scene({required bool compact}) => _Scene(
          phase: phase,
          wave: TideWave(
            phase: phase,
            mbps: reading ?? 0,
            economy: economy,
            still: still,
          ),
          reading: reading,
          phaseText: phaseText,
          announcement: announcement,
          compact: compact,
          s: s,
        );
    final progress = _Progress(status: state.status, progress: state.progress);
    final button = _StartButton(
      running: state.isRunning,
      label: state.isRunning
          ? s.cancel
          : state.status == SpeedTestStatus.idle
              ? s.speedTestStart
              : s.speedTestRetest,
      onPressed: state.isRunning ? notifier.cancel : notifier.run,
    );

    return LayoutBuilder(
      builder: (context, outer) {
        final fold = _verticalFold(context);
        // Side by side on a tablet, PC or TV, and on an unfolded phone
        // with a fold down the middle (nothing important on the fold).
        if (outer.maxWidth >= 820 || (fold != null && outer.maxWidth >= 560)) {
          return OceanBackground(
            illuminate: true,
            tint: waves.tint,
            waveSpeed: waves.speed,
            waveAmplitude: waves.amplitude,
            maxContentWidth: fold != null ? outer.maxWidth : 1040,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    title,
                    const SizedBox(height: 16),
                    Expanded(
                      // Not stretched down a tall window: the scene keeps
                      // roughly its designed proportions.
                      child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 580),
                              child: _FoldSplit(
                                fold: fold,
                                left: _Window(child: scene(compact: false)),
                                right: _Window(
                                  padding:
                                      const EdgeInsets.fromLTRB(22, 20, 22, 20),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Flexible(
                                        child: SingleChildScrollView(
                                          child: _Results(
                                              state: state,
                                              s: s,
                                              vertical: true),
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      progress,
                                      const SizedBox(height: 18),
                                      button,
                                    ],
                                  ),
                                ),
                              ))),
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
              // One screen, no scrolling (owner, 12.10). Only a very short
              // window (landscape, split screen) scrolls, at a fixed height.
              child: LayoutBuilder(builder: (context, box) {
                final narrow = box.maxWidth < 400;
                final page = Padding(
                  // The start button sits low, within thumb reach, clear of
                  // the nav bar (owner, 06.10).
                  padding: EdgeInsets.fromLTRB(narrow ? 16 : 20, 12,
                      narrow ? 16 : 20, kMobileBottomBarReserve + 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      title,
                      const SizedBox(height: 12),
                      Expanded(
                        child: _Window(
                          radius: narrow ? 20 : 24,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: scene(compact: narrow)),
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                    narrow ? 14 : 18, 0, narrow ? 14 : 18, 14),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _Results(
                                        state: state, s: s, vertical: false),
                                    const SizedBox(height: 4),
                                    progress,
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      button,
                    ],
                  ),
                );
                const minHeight = 560.0;
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

/// A vertical fold or hinge (an unfolded book-style phone), in global
/// coordinates — or null.
Rect? _verticalFold(BuildContext context) {
  for (final f in MediaQuery.of(context).displayFeatures) {
    if (f.type == DisplayFeatureType.cutout) continue;
    final b = f.bounds;
    if (b.height > b.width && b.left > 0) return b;
  }
  return null;
}

/// Two panes side by side. With a [fold], the gap between them is laid
/// over the fold (measured against this widget's own position on
/// screen); otherwise the scene takes the larger share.
class _FoldSplit extends StatefulWidget {
  const _FoldSplit(
      {required this.fold, required this.left, required this.right});

  final Rect? fold;
  final Widget left;
  final Widget right;

  @override
  State<_FoldSplit> createState() => _FoldSplitState();
}

class _FoldSplitState extends State<_FoldSplit> {
  double _originX = 0;

  void _measure() {
    if (!mounted || widget.fold == null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final x = box.localToGlobal(Offset.zero).dx;
    if ((x - _originX).abs() > 0.5) setState(() => _originX = x);
  }

  @override
  Widget build(BuildContext context) {
    final fold = widget.fold;
    return LayoutBuilder(builder: (context, box) {
      if (fold == null) {
        final side = (box.maxWidth * 0.36).clamp(280.0, 360.0);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: widget.left),
            const SizedBox(width: 16),
            SizedBox(width: side, child: widget.right),
          ],
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
      final start =
          (fold.left - _originX - 12).clamp(160.0, box.maxWidth - 200);
      final gap = fold.width + 24;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: start, child: widget.left),
          SizedBox(width: gap),
          Expanded(child: widget.right),
        ],
      );
    });
  }
}

/// The «Прилив» window: dark gradient with a burgundy glow in the corner,
/// a thin wine-coloured frame.
class _Window extends StatelessWidget {
  const _Window({required this.child, this.radius = 24, this.padding});

  final Widget child;
  final double radius;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        border: Border.all(color: _edge),
        gradient: const LinearGradient(
          begin: Alignment(-1, -0.6),
          end: Alignment(1, 0.6),
          colors: [Color(0xFF100B14), Color(0xFF070B11), Color(0xFF070609)],
          stops: [0, 0.6, 1],
        ),
        boxShadow: const [
          BoxShadow(
              color: Color(0x55000000), blurRadius: 55, offset: Offset(0, 18)),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.76, -1),
              radius: 0.9,
              colors: [Color(0xFF30101C), Color(0x0030101C)],
            ),
          ),
          child: padding == null
              ? child
              : Padding(padding: padding!, child: child),
        ),
      ),
    );
  }
}

/// The wave with the reading above it: the number (still, tabular), the
/// phase, and the direction in words and arrows — not only by colour.
class _Scene extends StatelessWidget {
  const _Scene({
    required this.phase,
    required this.wave,
    required this.reading,
    required this.phaseText,
    required this.announcement,
    required this.compact,
    required this.s,
  });

  final TidePhase phase;
  final Widget wave;
  final double? reading;
  final String phaseText;
  final String announcement;
  final bool compact;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final direction = switch (phase) {
      TidePhase.download => '↓ ${s.speedTestDownload}',
      TidePhase.upload => '↑ ${s.speedTestUpload}',
      TidePhase.failed => '',
      _ => '↓ ${s.speedTestDownload} · ↑ ${s.speedTestUpload}',
    };
    const shadow = [
      Shadow(color: Color(0xFF020609), blurRadius: 18, offset: Offset(0, 2))
    ];
    return LayoutBuilder(builder: (context, box) {
      final big = (box.maxHeight * 0.2).clamp(40.0, compact ? 50.0 : 64.0);
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(top: box.maxHeight * 0.18, child: wave),
          Positioned(
            top: 8,
            left: 16,
            right: 16,
            // The reading centred in the calm water above the crest.
            height: math.max(box.maxHeight * 0.5, 124),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ExcludeSemantics(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        reading == null ? '—' : _formatMbps(reading),
                        style: TextStyle(
                          color: _ink,
                          fontSize: big,
                          height: 1.18,
                          fontWeight: FontWeight.w400,
                          letterSpacing: -2,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          shadows: shadow,
                        ),
                      ),
                      const SizedBox(width: 7),
                      const Text(_mbps,
                          style: TextStyle(
                              color: Color(0xFFB5C9D1),
                              fontSize: 12,
                              shadows: shadow)),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Semantics(
                  liveRegion: true,
                  label: announcement,
                  child: ExcludeSemantics(
                    child: Text(
                      phaseText,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFFBBC4CC),
                          fontSize: 13,
                          shadows: shadow),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (direction.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 8,
              child: ExcludeSemantics(
                child: Text(
                  direction,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.6,
                    color: phase == TidePhase.upload
                        ? const Color(0xFFFFA3B6)
                        : const Color(0xFFC2D9DD),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// Download, upload and latency: three compact columns on a phone, rows
/// beside the scene on a wide screen. The leg being measured is lit in
/// its colour, a finished one gets a check, one that failed an ✕.
class _Results extends StatelessWidget {
  const _Results(
      {required this.state, required this.s, required this.vertical});

  final SpeedTestState state;
  final AppStrings s;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final failed = state.status == SpeedTestStatus.failed;
    final items = [
      _Result(
        label: '↓ ${s.speedTestDownload}',
        value: _formatMbps(state.downloadMbps),
        unit: 'Mbps',
        tone: tideDownload,
        active: state.status == SpeedTestStatus.testingDownload,
        done: state.downloadMbps != null,
        failed: failed && state.downloadMbps == null,
        vertical: vertical,
      ),
      _Result(
        label: '↑ ${s.speedTestUpload}',
        value: _formatMbps(state.uploadMbps),
        unit: 'Mbps',
        tone: tideUpload,
        active: state.status == SpeedTestStatus.testingUpload,
        done: state.uploadMbps != null,
        failed: failed && state.uploadMbps == null,
        vertical: vertical,
      ),
      _Result(
        label: s.speedTestLatency,
        value: state.latencyMs?.toString() ?? '–',
        unit: s.unitMs,
        tone: _ink,
        active: state.status == SpeedTestStatus.testingLatency,
        done: state.latencyMs != null,
        failed: false,
        vertical: vertical,
      ),
    ];
    if (vertical) {
      return Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1, color: _rule),
            items[i],
          ],
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration:
          const BoxDecoration(border: Border(top: BorderSide(color: _rule))),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: VerticalDivider(
                      width: 1, thickness: 1, color: Color(0xFF33333F)),
                ),
              Expanded(child: items[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.label,
    required this.value,
    required this.unit,
    required this.tone,
    required this.active,
    required this.done,
    required this.failed,
    required this.vertical,
  });

  final String label;
  final String value;
  final String unit;
  final Color tone;
  final bool active;
  final bool done;
  final bool failed;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      maxLines: 1,
      overflow: vertical ? TextOverflow.ellipsis : null,
      style: TextStyle(
        fontSize: vertical ? 13 : 11,
        color: active ? tone : const Color(0xFFC6B7C3),
        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
      ),
    );
    // Compact columns scale the label down (FittedBox) instead of cutting
    // it at 320 px.
    final labelRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (vertical) Flexible(child: text) else text,
        if (done && !active) ...[
          const SizedBox(width: 4),
          const Icon(Icons.check_rounded, size: 13, color: WbColors.oceanTeal),
        ],
      ],
    );
    final Widget reading = failed
        ? const Icon(Icons.close_rounded, size: 18, color: WbColors.error)
        : FittedBox(
            fit: BoxFit.scaleDown,
            alignment: vertical ? Alignment.centerRight : Alignment.centerLeft,
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: active ? '…' : value),
                TextSpan(
                  text: ' $unit',
                  style:
                      const TextStyle(fontSize: 10, color: Color(0xFFA9BAC8)),
                ),
              ]),
              maxLines: 1,
              style: TextStyle(
                fontSize: vertical ? 24 : 20,
                height: 1.2,
                color: active ? tone : const Color(0xFFF2EDF2),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          );
    if (vertical) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Expanded(
                child: Align(alignment: Alignment.centerLeft, child: labelRow)),
            const SizedBox(width: 12),
            Flexible(
                child: Align(alignment: Alignment.centerRight, child: reading)),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: labelRow),
        const SizedBox(height: 5),
        Align(alignment: Alignment.centerLeft, child: reading),
      ],
    );
  }
}

/// A thin bar for the leg under way (indeterminate for latency), in the
/// leg's colour; hidden when nothing runs.
class _Progress extends StatelessWidget {
  const _Progress({required this.status, required this.progress});

  final SpeedTestStatus status;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final visible = status == SpeedTestStatus.testingLatency ||
        status == SpeedTestStatus.testingDownload ||
        status == SpeedTestStatus.testingUpload;
    return ExcludeSemantics(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: visible ? 1 : 0,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: status == SpeedTestStatus.testingLatency ? null : progress,
            minHeight: 3,
            backgroundColor: const Color(0xFF253037),
            valueColor: AlwaysStoppedAnimation(
                status == SpeedTestStatus.testingUpload
                    ? tideUpload
                    : tideDownload),
          ),
        ),
      ),
    );
  }
}

/// Start / test again (light, with an arrow) or, while running, Cancel.
/// At least 48 px tall, with a turquoise focus ring for keyboard and the
/// TV remote.
class _StartButton extends StatelessWidget {
  const _StartButton(
      {required this.running, required this.label, required this.onPressed});

  final bool running;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(50)),
      shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      backgroundColor: WidgetStatePropertyAll(
          running ? const Color(0xFF101820) : const Color(0xFFF1F0F5)),
      foregroundColor: WidgetStatePropertyAll(
          running ? const Color(0xFFBEC8D1) : const Color(0xFF15141B)),
      side: WidgetStateProperty.resolveWith((states) => BorderSide(
            color: states.contains(WidgetState.focused)
                ? tideDownload
                : running
                    ? const Color(0xFF36414B)
                    : Colors.transparent,
            width: states.contains(WidgetState.focused) ? 2.5 : 1,
          )),
      textStyle: WidgetStatePropertyAll(Theme.of(context)
          .textTheme
          .labelLarge
          ?.copyWith(fontSize: 15, fontWeight: FontWeight.w600)),
    );
    return FilledButton(
      onPressed: onPressed,
      style: style,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (running) ...[
            const Icon(Icons.close_rounded, size: 20),
            const SizedBox(width: 8),
          ],
          Text(label),
          if (!running) ...[
            const SizedBox(width: 10),
            const ExcludeSemantics(child: Text('→')),
          ],
        ],
      ),
    );
  }
}
