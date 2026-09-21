import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../shared/ocean_background.dart';
import '../shared/wave_params.dart';
import '../shared/wavebreak_mark.dart';
import '../shared/wb_card.dart';
import '../shell/app_shell.dart';

/// Public one-off bandwidth-probe endpoints. Core has no throughput
/// endpoint of its own — only a per-node *reachability* recipe (see
/// `services/vpn/connection_test_service.dart`'s own comment on that same
/// gap) — so, same as that file did for latency, this reaches for an
/// honest, widely-used public benchmarking target instead of inventing
/// numbers. Cloudflare's speed-test backend is free, requires no key, and
/// is what Cloudflare's own public speed-test page uses. Whatever tunnel
/// is currently active (if any) carries this traffic exactly like any
/// other request from the app, so a connected run genuinely measures the
/// VPN path, not a bypass of it.
const _kDownloadUrl = 'https://speed.cloudflare.com/__down?bytes=';
const _kUploadUrl = 'https://speed.cloudflare.com/__up';

/// Large enough that a fast connection is still mid-transfer when the
/// download phase's own time budget cuts it off — a payload that finishes
/// on its own before the deadline would stop sampling early and read as a
/// premature, too-low number instead of whatever the deadline actually
/// captured.
const _kDownloadBytes = 200 * 1000 * 1000;
const _kUploadBytes = 24 * 1000 * 1000;

const _kPhaseBudget = Duration(milliseconds: 3000);
const _kPingProbes = 3;
const _kUploadChunkSize = 256 * 1024;

/// Generates [totalBytes] worth of filler data a chunk at a time — only
/// throughput is being measured, so the content is never inspected, but a
/// single [totalBytes]-sized buffer held in memory just to hand it to
/// dio's request body would be a needlessly large one-shot allocation
/// (multiple MB) on a phone. Reusing one small chunk buffer across every
/// yield keeps this generator's own footprint constant regardless of how
/// large [totalBytes] is.
Stream<Uint8List> _uploadChunks(int totalBytes, [int chunkSize = _kUploadChunkSize]) async* {
  final chunk = Uint8List(chunkSize);
  var sent = 0;
  while (sent < totalBytes) {
    final n = math.min(chunkSize, totalBytes - sent);
    yield n == chunkSize ? chunk : chunk.sublist(0, n);
    sent += n;
  }
}

enum _Phase { idle, ping, download, upload, done }

class SpeedtestScreen extends ConsumerStatefulWidget {
  const SpeedtestScreen({super.key});

  @override
  ConsumerState<SpeedtestScreen> createState() => _SpeedtestScreenState();
}

class _SpeedtestScreenState extends ConsumerState<SpeedtestScreen> {
  _Phase _phase = _Phase.idle;
  int? _pingMs;
  double? _downMbps;
  double? _upMbps;
  double _liveMbps = 0;
  double _maxScale = 100;

  /// Bumped on every [_runTest] call and checked after each await — the
  /// same stale-attempt guard `ConnectionManager` uses for `connect()`
  /// (see `_connectGeneration` there): tapping the button again mid-run
  /// should restart cleanly, not have the abandoned run's late samples
  /// keep landing on top of the new one.
  int _runId = 0;

  @override
  void dispose() {
    _runId++;
    super.dispose();
  }

  Future<void> _runTest() async {
    final runId = ++_runId;
    unawaited(HapticFeedback.lightImpact());
    setState(() {
      _phase = _Phase.ping;
      _pingMs = null;
      _downMbps = null;
      _upMbps = null;
      _liveMbps = 0;
      _maxScale = 100;
    });

    final ping = await _measurePing();
    if (runId != _runId || !mounted) return;
    setState(() {
      _pingMs = ping;
      _phase = _Phase.download;
      _liveMbps = 0;
    });

    final down = await _measureTransfer(upload: false, runId: runId);
    if (runId != _runId || !mounted) return;
    setState(() {
      _downMbps = down;
      _phase = _Phase.upload;
      _liveMbps = 0;
    });

    final up = await _measureTransfer(upload: true, runId: runId);
    if (runId != _runId || !mounted) return;
    setState(() {
      _upMbps = up;
      _phase = _Phase.done;
    });
    unawaited(HapticFeedback.mediumImpact());
  }

  /// Three quick round trips against the same host the transfer phases
  /// use, taking the minimum — one honest ping number, not three
  /// contradictory ones. The minimum (not the average) is deliberate: a
  /// single queued/slow probe should never drag the reading up, since the
  /// fastest observed round trip is the one that best reflects the actual
  /// path latency rather than momentary server-side jitter.
  Future<int?> _measurePing() async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(milliseconds: 1500),
      receiveTimeout: const Duration(milliseconds: 1500),
      sendTimeout: const Duration(milliseconds: 1500),
    ));
    var best = 1 << 30;
    var any = false;
    for (var i = 0; i < _kPingProbes; i++) {
      final stopwatch = Stopwatch()..start();
      try {
        await dio.get<List<int>>(
          '${_kDownloadUrl}0',
          options: Options(responseType: ResponseType.bytes),
        );
        stopwatch.stop();
        any = true;
        if (stopwatch.elapsedMilliseconds < best) best = stopwatch.elapsedMilliseconds;
      } catch (_) {
        // One bad probe out of three shouldn't sink the whole reading —
        // the other attempts still get a chance.
      }
    }
    dio.close();
    return any ? best : null;
  }

  /// Runs one direction (download or upload) for [_kPhaseBudget], sampling
  /// throughput as bytes actually move rather than waiting for the whole
  /// transfer to finish — [_liveMbps] (and therefore the gauge) updates
  /// continuously from the first samples, seconds before this returns.
  /// Cut off by a deadline, not by the payload finishing on its own: a
  /// bounded probe, not a real download/upload, so the app is never stuck
  /// waiting on a slow link to exhaust a huge payload by itself.
  Future<double?> _measureTransfer({required bool upload, required int runId}) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 12),
      sendTimeout: const Duration(seconds: 12),
    ));
    final cancelToken = CancelToken();
    final deadline = Timer(_kPhaseBudget, () {
      if (!cancelToken.isCancelled) cancelToken.cancel('deadline');
    });
    var lastBytes = 0;
    var lastTime = DateTime.now();
    final samples = <double>[];

    void sample(int done) {
      if (runId != _runId) return;
      final now = DateTime.now();
      final dt = now.difference(lastTime).inMicroseconds / 1e6;
      final dBytes = done - lastBytes;
      // Too soon since the last sample to trust the rate it'd imply — lets
      // more bytes accumulate first instead of a near-zero denominator
      // producing a wildly noisy spike.
      if (dt < 0.09) return;
      lastBytes = done;
      lastTime = now;
      if (dBytes <= 0) return;
      final mbps = (dBytes * 8) / dt / 1e6;
      samples.add(mbps);
      if (!mounted) return;
      setState(() {
        _liveMbps = mbps;
        _maxScale = math.max(_maxScale, _scaleFor(mbps));
      });
    }

    try {
      if (upload) {
        await dio.post<void>(
          _kUploadUrl,
          data: _uploadChunks(_kUploadBytes),
          options: Options(
            headers: {
              Headers.contentLengthHeader: _kUploadBytes,
              Headers.contentTypeHeader: 'application/octet-stream',
            },
          ),
          cancelToken: cancelToken,
          onSendProgress: (done, total) => sample(done),
        );
      } else {
        // Streamed and counted by hand rather than ResponseType.bytes +
        // onReceiveProgress: the deadline below caps *time*, not bytes, so
        // on a genuinely fast link letting dio accumulate everything it
        // receives into one in-memory buffer could mean hundreds of MB
        // held on a phone before the cancel ever lands. Counting each
        // chunk's length and discarding it keeps memory flat no matter how
        // fast the link turns out to be.
        final response = await dio.get<ResponseBody>(
          '$_kDownloadUrl$_kDownloadBytes',
          options: Options(responseType: ResponseType.stream),
          cancelToken: cancelToken,
        );
        var total = 0;
        await for (final chunk in response.data!.stream) {
          total += chunk.length;
          sample(total);
        }
      }
    } catch (_) {
      // Either the deadline firing above (the expected, normal way this
      // ends) or a genuine network failure — either way, whatever got
      // sampled before that is still a real measurement, not a mistake to
      // recover from.
    } finally {
      deadline.cancel();
      dio.close(force: true);
    }

    if (samples.isEmpty) return null;
    // The back half of the samples, not the whole run: the first moment or
    // two of any transfer is still ramping up (TCP slow start, the far end
    // spinning up), and averaging that in with the rest would read as
    // slower than the connection actually sustained once warmed up.
    final settled = samples.length >= 4 ? samples.sublist(samples.length ~/ 2) : samples;
    return settled.reduce((a, b) => a + b) / settled.length;
  }

  static double _scaleFor(double mbps) {
    const steps = [20.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0];
    for (final step in steps) {
      if (mbps <= step * 0.92) return step;
    }
    return (mbps / 500).ceil() * 500.0;
  }

  String _phaseLabel(AppStrings s) => switch (_phase) {
        _Phase.idle => s.navSpeedtest,
        _Phase.ping => s.speedtestPing,
        _Phase.download => s.speedtestDownload,
        _Phase.upload => s.speedtestUpload,
        _Phase.done => s.navSpeedtest,
      };

  String _hintLabel(AppStrings s) => switch (_phase) {
        _Phase.idle => s.speedtestTap,
        _Phase.done => s.speedtestRetest,
        _ => s.speedtestTesting,
      };

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final waves = ref.watch(appWaveParamsProvider);
    final tint = waves.tint ?? WbColors.waveCyan;
    final running = _phase != _Phase.idle && _phase != _Phase.done;

    final displayMbps = switch (_phase) {
      _Phase.download || _Phase.upload => _liveMbps,
      _Phase.done => _upMbps ?? _downMbps ?? 0,
      _ => 0.0,
    };

    return OceanBackground(
      illuminate: true,
      tint: tint,
      waveSpeed: waves.speed,
      waveAmplitude: waves.amplitude,
      waveLineCount: 5,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 0, 20, kMobileBottomBarReserve + 20),
              child: Column(
                children: [
                  SizedBox(height: (constraints.maxHeight * 0.03).clamp(8.0, 20.0)),
                  const SizedBox(
                    height: 46,
                    child: Center(child: WavebreakWordmarkText(size: 14)),
                  ),
                  SizedBox(height: (constraints.maxHeight * 0.04).clamp(12.0, 32.0)),
                  Text(
                    _phaseLabel(s).toUpperCase(),
                    style: const TextStyle(
                      fontSize: 15,
                      letterSpacing: 3,
                      color: WbColors.ice60,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 18),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: _SpeedGauge(
                      mbps: displayMbps,
                      maxScale: _maxScale,
                      tint: tint,
                      active: running,
                    ),
                  ),
                  const SizedBox(height: 4),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Row(
                      key: ValueKey('${_phase.name}-${displayMbps.toStringAsFixed(0)}'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          displayMbps < 10
                              ? displayMbps.toStringAsFixed(1)
                              : displayMbps.toStringAsFixed(0),
                          style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            s.mbpsUnit,
                            style: const TextStyle(
                              fontSize: 16,
                              color: WbColors.ice60,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _hintLabel(s),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: WbColors.ice60, fontSize: 14),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          label: s.speedtestPing,
                          value: _pingMs == null ? '—' : '$_pingMs',
                          unit: _pingMs == null ? '' : 'ms',
                          tint: tint,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatTile(
                          label: s.speedtestDownload,
                          value: _downMbps == null ? '—' : _downMbps!.toStringAsFixed(1),
                          unit: _downMbps == null ? '' : s.mbpsUnit,
                          tint: tint,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatTile(
                          label: s.speedtestUpload,
                          value: _upMbps == null ? '—' : _upMbps!.toStringAsFixed(1),
                          unit: _upMbps == null ? '' : s.mbpsUnit,
                          tint: tint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _runTest,
                      style: FilledButton.styleFrom(
                        backgroundColor: WbColors.waveCyan,
                        foregroundColor: WbColors.midnight,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        running
                            ? s.speedtestTesting
                            : (_phase == _Phase.done ? s.speedtestRetest : s.navSpeedtest),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.unit,
    this.tint,
  });

  final String label;
  final String value;
  final String unit;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return WbCard(
      tint: tint,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      child: Column(
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              letterSpacing: 1.2,
              color: WbColors.ice60,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              text: value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              children: unit.isEmpty
                  ? const []
                  : [
                      TextSpan(
                        text: ' $unit',
                        style: const TextStyle(
                          fontSize: 11,
                          color: WbColors.ice60,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// A half-circle "vessel" that fills like water as [mbps] rises toward
/// [maxScale] — the same living-wave motif as [AnimatedWaves] elsewhere in
/// the app (a wall-clock-driven sine, so it never jumps or drifts out of
/// sync with anything else on screen), closed into a filled body instead
/// of bare drifting lines.
class _SpeedGauge extends StatefulWidget {
  const _SpeedGauge({
    required this.mbps,
    required this.maxScale,
    required this.tint,
    required this.active,
  });

  final double mbps;
  final double maxScale;
  final Color tint;
  final bool active;

  @override
  State<_SpeedGauge> createState() => _SpeedGaugeState();
}

class _SpeedGaugeState extends State<_SpeedGauge> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fraction = widget.maxScale <= 0 ? 0.0 : (widget.mbps / widget.maxScale).clamp(0.0, 1.0);
    return AspectRatio(
      aspectRatio: 2,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final now = DateTime.now().millisecondsSinceEpoch / 1000;
            return CustomPaint(
              painter: _GaugePainter(
                fraction: fraction,
                time: now,
                tint: widget.tint,
                active: widget.active,
              ),
              size: Size.infinite,
            );
          },
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({
    required this.fraction,
    required this.time,
    required this.tint,
    required this.active,
  });

  /// 0..1 — current value against the gauge's current scale ceiling.
  final double fraction;
  final double time;
  final Color tint;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    // The flat base sits at the very bottom of the painted area, so the
    // whole dome (arc bulging upward) fits within `size` with nothing
    // clipped off the top.
    final center = Offset(radius, size.height);
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Left -> top -> right, closed back along the flat base: a solid
    // half-disc silhouette, not just an open arc.
    final domePath = Path()
      ..moveTo(center.dx - radius, center.dy)
      ..arcTo(rect, math.pi, math.pi, false)
      ..close();

    canvas.drawPath(domePath, Paint()..color = WbColors.ice.withValues(alpha: 0.05));

    canvas.save();
    canvas.clipPath(domePath);

    final clamped = fraction.clamp(0.0, 1.0);
    final waterTopY = size.height - clamped * size.height;
    final amplitude = active ? 6.0 : 1.5;

    Path surfacePath() {
      final path = Path();
      const steps = 48;
      for (var i = 0; i <= steps; i++) {
        final t = i / steps;
        final x = size.width * t;
        // Two overlapping sines (different wavelength/speed) read as real
        // water chop rather than one mechanically perfect ripple.
        final y = waterTopY +
            math.sin(t * math.pi * 4 + time * 2.6) * amplitude * 0.7 +
            math.sin(t * math.pi * 2.2 - time * 1.7) * amplitude * 0.3;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      return path;
    }

    final body = surfacePath()
      ..lineTo(size.width, size.height + 4)
      ..lineTo(0, size.height + 4)
      ..close();

    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tint.withValues(alpha: 0.75), tint.withValues(alpha: 0.28)],
        ).createShader(Rect.fromLTWH(0, waterTopY - 30, size.width, size.height - waterTopY + 30)),
    );
    canvas.drawPath(
      surfacePath(),
      Paint()
        ..color = Color.lerp(tint, Colors.white, 0.35)!.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    canvas.restore();

    canvas.drawPath(
      domePath,
      Paint()
        ..color = WbColors.ice08
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.time != time ||
      oldDelegate.tint != tint ||
      oldDelegate.active != active;
}
