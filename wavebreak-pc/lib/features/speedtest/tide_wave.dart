import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// What the tide is showing — one per speed-test state.
enum TidePhase { idle, ping, download, upload, done, failed }

/// Download turquoise and upload red-pink (owner's «Прилив» design, 14.10).
const tideDownload = Color.fromARGB(255, 102, 225, 231);
const tideUpload = Color.fromARGB(255, 255, 75, 115);
const _failedTone = Color.fromARGB(255, 138, 146, 160);
const _particle = Color.fromARGB(255, 213, 250, 250);
const _reflection = Color.fromARGB(255, 225, 46, 84);

/// Throughput on a log scale, 0..1 (500 Mbps and up is full), so 5 and
/// 500 Mbps both move the surface visibly.
double tideLevel(double mbps) =>
    mbps <= 0 ? 0 : (math.log(1 + mbps) / math.log(501)).clamp(0.0, 1.0);

/// The target the surface eases towards, from the test's real state.
/// Nothing here is simulated: [mbps] is the controller's smoothed live
/// reading during a leg and the finished download once done.
class TideTarget {
  const TideTarget(this.energy, this.flow, this.direction, this.color);

  final double energy;
  final double flow;
  final double direction;
  final Color color;

  factory TideTarget.of(TidePhase phase, double mbps) {
    final level = tideLevel(mbps);
    return switch (phase) {
      TidePhase.idle => const TideTarget(0.34, 0.6, 1, tideDownload),
      TidePhase.ping => const TideTarget(0.40, 0.8, 1, tideDownload),
      TidePhase.download =>
        TideTarget(0.38 + 0.62 * level, 0.75 + 0.6 * level, 1, tideDownload),
      TidePhase.upload =>
        TideTarget(0.38 + 0.62 * level, 0.75 + 0.6 * level, -1, tideUpload),
      TidePhase.done => TideTarget(0.40 + 0.25 * level, 0.6, 1, tideDownload),
      TidePhase.failed => const TideTarget(0.20, 0.3, 1, _failedTone),
    };
  }
}

/// The «Прилив» scene: a multi-layer perspective wave surface with a grid,
/// light particles riding it and a faint reflection below. Height and
/// tempo follow the real speed, direction and colour follow the leg
/// (download flows forward in turquoise, upload backwards in red-pink);
/// every change eases over ~300 ms.
///
/// Normal profile ~30 fps, 29×92 grid, 64 particles; [economy] ~15 fps,
/// 17×64, 28 particles, no glow. [still] (reduced motion) draws one static
/// frame per state change and runs no ticker. The ticker stops with the
/// app in the background and with TickerMode (an inactive tab).
class TideWave extends StatefulWidget {
  const TideWave({
    super.key,
    required this.phase,
    required this.mbps,
    this.economy = false,
    this.still = false,
  });

  final TidePhase phase;
  final double mbps;
  final bool economy;
  final bool still;

  @override
  State<TideWave> createState() => _TideWaveState();
}

class _TideWaveState extends State<TideWave>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker = createTicker(_onTick);
  final _frame = _TideFrame();
  Duration _last = Duration.zero;
  Duration _lastPaint = Duration.zero;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _frame.snapTo(TideTarget.of(widget.phase, widget.mbps));
    _apply();
  }

  @override
  void didUpdateWidget(TideWave old) {
    super.didUpdateWidget(old);
    if (widget.still) {
      _frame.snapTo(TideTarget.of(widget.phase, widget.mbps));
      _frame.bump();
    }
    _apply();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    _apply();
  }

  void _apply() {
    final run = !widget.still && _foreground;
    if (run && !_ticker.isActive) {
      _last = Duration.zero;
      _lastPaint = Duration.zero;
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    final budget = Duration(milliseconds: widget.economy ? 66 : 33);
    if (_lastPaint != Duration.zero && elapsed - _lastPaint < budget) return;
    final dt = _last == Duration.zero
        ? 0.0
        : ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.25);
    _last = elapsed;
    _lastPaint = elapsed;
    _frame.step(dt, TideTarget.of(widget.phase, widget.mbps));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _TidePainter(_frame, economy: widget.economy),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// The eased surface parameters and the integrated wave phase. The phase
/// is integrated (not time × direction), so reversing for upload slows
/// the wave, stops it and runs it back instead of jumping.
class _TideFrame extends ChangeNotifier {
  double energy = 0.34;
  double flow = 0.6;
  double direction = 1;
  Color color = tideDownload;
  double t = 0;

  /// ~300 ms to settle 95% of a change.
  static const _tau = 0.1;

  void snapTo(TideTarget target) {
    energy = target.energy;
    flow = target.flow;
    direction = target.direction;
    color = target.color;
  }

  void bump() => notifyListeners();

  void step(double dt, TideTarget target) {
    final k = 1 - math.exp(-dt / _tau);
    energy += (target.energy - energy) * k;
    flow += (target.flow - flow) * k;
    direction += (target.direction - direction) * k;
    color = Color.lerp(color, target.color, k)!;
    t += dt * flow * direction;
    notifyListeners();
  }
}

class _TidePainter extends CustomPainter {
  _TidePainter(this._frame, {required this.economy}) : super(repaint: _frame);

  final _TideFrame _frame;
  final bool economy;

  static Offset _project(double x, double z, double y, double w, double h) {
    final s = 1 / (0.84 + z * 0.53);
    return Offset(
        w * 0.5 + x * w * 0.40 * s, h * 0.89 - z * h * 0.22 - y * h * 0.22 * s);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w < 2 || h < 2) return;
    final f = _frame;
    final t = f.t, energy = f.energy, rgb = f.color;
    Color c(double a) => rgb.withValues(alpha: a.clamp(0.0, 1.0));

    // Ambient glow under the crest.
    final centre = Offset(w * 0.54, h * 0.69);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
            centre, w * 0.65, [c(0.065), c(0.02), c(0)], const [0, 0.62, 1]),
    );

    final rows = economy ? 17 : 29, cols = economy ? 64 : 92;
    final grid = List<List<Offset>>.filled(rows + 1, const []);
    final fillShader = ui.Gradient.linear(Offset(0, h * 0.3),
        Offset(0, h * 0.94), [c(0.033), c(0.019), c(0)], const [0, 0.6, 1]);
    final fill = Paint()..shader = fillShader;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    for (var j = rows; j >= 0; j--) {
      final z = j / rows;
      final crest = 0.12 + math.sin(t * 0.62 - z * 2.2) * 0.24;
      final width = 0.28 + z * 0.075;
      final shoulderAt = -0.61 + math.sin(t * 0.36 - z) * 0.13;
      final line = List<Offset>.filled(cols + 1, Offset.zero);
      for (var i = 0; i <= cols; i++) {
        final x = (i / cols - 0.5) * 2.5;
        final p = (x - crest) / width;
        final q = (x - shoulderAt) / 0.4;
        final y = energy * (math.exp(-p * p) * 0.98 + math.exp(-q * q) * 0.40) +
            math.sin(x * 7 - t * 2.4 - z * 3.3) * 0.027;
        line[i] = _project(x, z, y, w, h);
      }
      grid[j] = line;

      final path = Path()..addPolygon(line, false);
      final base = h * 0.9 - z * h * 0.31;
      final area = Path.from(path)
        ..lineTo(line.last.dx, base)
        ..lineTo(line.first.dx, base)
        ..close();
      canvas.drawPath(area, fill);

      stroke
        ..color = c(0.14 + (1 - z) * 0.28)
        ..strokeWidth = j == 0 ? 1.5 : 0.6
        ..maskFilter = null;
      if (j == 0 && !economy) {
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..color = c(0.45)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5));
      }
      canvas.drawPath(path, stroke);
    }

    // Cross lines through the depth.
    final cross = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = c(0.08);
    for (var i = 0; i <= cols; i += economy ? 5 : 3) {
      final pts = [for (var j = 0; j <= rows; j++) grid[j][i]];
      canvas.drawPath(Path()..addPolygon(pts, false), cross);
    }

    // Light parcels on the same surface and perspective: smaller and
    // fainter with depth.
    final n = economy ? 28 : 64;
    final dot = Paint();
    final glow = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);
    for (var i = 0; i < n; i++) {
      final z = ((i * 0.173 + t * 0.10) % 1 + 1) % 1;
      final x = 0.12 +
          math.sin(t * 0.62 - z * 2.2) * 0.24 +
          math.sin(i * 2.39) * 0.095;
      final y = energy * 0.98 + math.sin(i * 0.53 + t * 1.7) * 0.036;
      final p = _project(x, z, y, w, h);
      final s = 1 / (0.84 + z * 0.53);
      final big = i % 9 == 0;
      final r = (big ? 1.3 : 0.65) * s * 1.1;
      if (big && !economy) {
        canvas.drawCircle(p, r + 2, glow..color = c(0.6 * (1 - z) + 0.15));
      }
      canvas.drawCircle(p, r,
          dot..color = _particle.withValues(alpha: (1 - z) * 0.46 + 0.10));
    }

    // A reflected wave below the near crest, clear of the numbers.
    final reflection = <Offset>[
      for (var i = 0; i <= 80; i++)
        Offset(i / 80 * w, h * 0.92 + math.sin(i * 0.085 - t * 0.6) * 5)
    ];
    canvas.drawPath(
        Path()..addPolygon(reflection, false),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..color = _reflection.withValues(alpha: 0.14));
  }

  @override
  bool shouldRepaint(_TidePainter old) =>
      old._frame != _frame || old.economy != economy;
}
