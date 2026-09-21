import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/wb_colors.dart';
import '../../services/vpn/connection_manager.dart';
import 'wavebreak_mark.dart';

class ConnectButton extends StatefulWidget {
  const ConnectButton({
    super.key,
    required this.status,
    required this.enabled,
    required this.onPressed,
    this.accentColors,
  });

  final ConnectionStatus status;
  final bool enabled;
  final VoidCallback onPressed;

  /// Optional flag-derived colors for the selected location; the bubble's
  /// glow/rim/shimmer picks these up once connected. The W mark itself
  /// always stays brand cyan/teal so it never loses legibility.
  final List<Color>? accentColors;

  @override
  State<ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<ConnectButton>
    with TickerProviderStateMixin {
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 6000),
  )..repeat();
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
  );
  // Very slow — the globe should read as barely-moving background texture,
  // not an animation anyone consciously notices.
  late final AnimationController _globeSpin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 34000),
  )..repeat();

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant ConnectButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) _sync();
  }

  void _sync() {
    final connecting = widget.status == ConnectionStatus.connecting ||
        widget.status == ConnectionStatus.requestingProfile ||
        widget.status == ConnectionStatus.disconnecting;
    if (connecting) {
      _spin.repeat();
    } else {
      _spin.stop();
      _spin.reset();
    }
    if (widget.status == ConnectionStatus.connected) {
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _breathe.dispose();
    _shimmer.dispose();
    _spin.dispose();
    _pop.dispose();
    _press.dispose();
    _globeSpin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.status == ConnectionStatus.connected;
    final connecting = widget.status == ConnectionStatus.connecting ||
        widget.status == ConnectionStatus.requestingProfile;
    final accent = widget.accentColors ?? const [WbColors.waveCyan, WbColors.oceanTeal];
    const diameter = 172.0;

    return AnimatedBuilder(
      animation: Listenable.merge([_breathe, _shimmer, _spin, _pop, _press, _globeSpin]),
      builder: (context, _) {
        final breathe = _breathe.value;
        final glow = connected ? 0.22 + breathe * 0.12 : 0.14 + breathe * 0.10;
        final pop = Curves.elasticOut.transform(_pop.value.clamp(0.0, 1.0));
        final popScale = connected ? 1.0 + (pop < 1 ? (1 - pop) * -0.02 : 0) : 1.0;
        final pressScale = 1.0 - (_press.value * 0.045);
        final breatheScale = connected ? 1.0 + breathe * 0.012 : 1.0;

        return GestureDetector(
          onTapDown: widget.enabled ? (_) => _press.forward() : null,
          onTapUp: widget.enabled ? (_) => _press.reverse() : null,
          onTapCancel: widget.enabled ? () => _press.reverse() : null,
          onTap: widget.enabled ? widget.onPressed : null,
          child: Transform.scale(
            scale: pressScale * popScale * breatheScale,
            child: SizedBox(
              width: diameter + 24,
              height: diameter + 24,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Ambient glow, tinted by the active location's colors.
                  Container(
                    width: diameter + 24,
                    height: diameter + 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: accent.first.withValues(alpha: widget.enabled ? glow : 0.05),
                          blurRadius: connected ? 46 : 28,
                          spreadRadius: connected ? 4 : 0,
                        ),
                        // The flag's second color used to only appear once
                        // connected, so at rest the button only ever showed
                        // one of the location's colors. Keeping it present
                        // (just dimmer) at every state means both real flag
                        // colors read immediately, not only after tapping.
                        BoxShadow(
                          color: accent.last.withValues(
                            alpha: widget.enabled ? (connected ? glow * 0.7 : glow * 0.32) : 0.03,
                          ),
                          blurRadius: connected ? 60 : 32,
                          spreadRadius: connected ? 2 : 0,
                        ),
                      ],
                    ),
                  ),
                  if (connecting)
                    Transform.rotate(
                      angle: _spin.value * math.pi * 2,
                      child: CustomPaint(
                        size: const Size(diameter, diameter),
                        painter: _RipplePainter(colors: accent),
                      ),
                    ),
                  if (connected)
                    Transform.rotate(
                      angle: _shimmer.value * math.pi * 2,
                      child: Container(
                        width: diameter + 6,
                        height: diameter + 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: SweepGradient(colors: [
                            for (final c in accent) c.withValues(alpha: 0.5),
                            accent.first.withValues(alpha: 0.5),
                          ]),
                        ),
                      ),
                    ),
                  // The liquid-glass bubble itself.
                  ClipOval(
                    child: SizedBox(
                      width: diameter,
                      height: diameter,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: const Alignment(-0.3, -0.4),
                                radius: 1.1,
                                colors: [
                                  accent.first.withValues(alpha: connected ? 0.20 : 0.09),
                                  WbColors.deepOcean.withValues(alpha: 0.30),
                                  WbColors.midnight.withValues(alpha: 0.42),
                                ],
                                stops: const [0.0, 0.55, 1.0],
                              ),
                            ),
                          ),
                          BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.02),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  width: 1,
                                ),
                              ),
                            ),
                          ),
                          // A faint wireframe globe — meridians + parallels,
                          // like a planet or a network map — drifting very
                          // slowly. Meant to be felt more than seen.
                          Opacity(
                            opacity: connected ? 0.62 : 0.40,
                            child: CustomPaint(
                              size: const Size(diameter, diameter),
                              painter: _GlobeNetworkPainter(
                                color: accent.first,
                                phase: _globeSpin.value,
                              ),
                            ),
                          ),
                          // A soft circular specular glint, like light on
                          // glass — not a geometric shape.
                          Positioned(
                            top: diameter * 0.16,
                            left: diameter * 0.20,
                            child: Container(
                              width: diameter * 0.34,
                              height: diameter * 0.34,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    Colors.white.withValues(alpha: 0.20),
                                    Colors.white.withValues(alpha: 0.0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: accent.first.withValues(
                                  alpha: connected ? 0.55 : 0.30,
                                ),
                                width: connected ? 2.2 : 1.2,
                              ),
                            ),
                          ),
                          Opacity(
                            opacity: widget.enabled ? 1 : 0.35,
                            child: WavebreakMark(
                              size: diameter * 0.44,
                              glow: connected,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RipplePainter extends CustomPainter {
  const _RipplePainter({required this.colors});

  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [
          colors.first.withValues(alpha: 0),
          colors.first.withValues(alpha: 0.8),
          colors.last.withValues(alpha: 0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawCircle(size.center(Offset.zero), size.width / 2 - 4, paint);
  }

  @override
  bool shouldRepaint(covariant _RipplePainter oldDelegate) => false;
}

/// A simple orthographic wireframe globe — a handful of meridian and
/// parallel rings plus a few "network node" points joined by thin lines —
/// standing in for a planet / information-network motif. Everything is
/// drawn at low opacity so it reads as ambient texture inside the glass
/// bubble rather than a distinct graphic.
class _GlobeNetworkPainter extends CustomPainter {
  const _GlobeNetworkPainter({required this.color, required this.phase});

  final Color color;

  /// 0..1 — one full slow rotation of the meridians around the vertical axis.
  final double phase;

  static const _nodeLatitudes = [-0.5, 0.05, 0.55];
  static const _nodeLongitudes = [0.15, 0.62, 0.85];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2 * 0.92;
    final rotation = phase * math.pi;

    // Lifted toward white rather than used at full saturation: a dark
    // accent (e.g. Finland's navy) would otherwise vanish against the
    // glass, while a bright one (cyan) would blow out — lightening keeps
    // every location's lines readable at roughly the same strength.
    final lit = Color.lerp(color, Colors.white, 0.32) ?? color;

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = lit.withValues(alpha: 0.62);

    // Meridians: upright ellipses whose width shrinks to 0 edge-on and
    // grows to the full diameter face-on as they sweep around the sphere.
    for (var i = 0; i < 4; i++) {
      final angle = rotation + i * math.pi / 4;
      final width = (r * 2 * math.cos(angle)).abs();
      if (width < 2) continue;
      canvas.drawOval(
        Rect.fromCenter(center: center, width: width, height: r * 2),
        linePaint,
      );
    }

    // Parallels: horizontal rings, foreshortened vertically for perspective.
    for (final t in const [-0.62, 0.0, 0.62]) {
      final ringR = r * math.sqrt((1 - t * t).clamp(0.0, 1.0));
      canvas.drawOval(
        Rect.fromCenter(
          center: center + Offset(0, t * r),
          width: ringR * 2,
          height: ringR * 0.62,
        ),
        linePaint,
      );
    }

    // A few faint "network" points and the connections between them —
    // the sphere doubling as an information-network glyph, not just a
    // planet.
    final nodes = <Offset>[
      for (final lat in _nodeLatitudes)
        for (final lon in _nodeLongitudes)
          _spherePoint(center, r, lat, lon + phase),
    ]..shuffle(math.Random(7));
    final picked = nodes.take(4).toList();

    final nodePaint = Paint()..color = lit.withValues(alpha: 0.9);
    final linkPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = lit.withValues(alpha: 0.38);

    for (var i = 0; i < picked.length; i++) {
      final next = picked[(i + 1) % picked.length];
      canvas.drawLine(picked[i], next, linkPaint);
    }
    for (final p in picked) {
      canvas.drawCircle(p, 1.6, nodePaint);
    }
  }

  /// Projects a (latitude, longitude) pair on the unit sphere to a 2D point
  /// via simple orthographic projection, for placing "network" nodes on
  /// the visible hemisphere.
  Offset _spherePoint(Offset center, double r, double lat, double lonTurns) {
    final lon = lonTurns * math.pi * 2;
    final x = math.cos(lat) * math.sin(lon);
    final y = math.sin(lat);
    return center + Offset(x * r, y * r);
  }

  @override
  bool shouldRepaint(covariant _GlobeNetworkPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.color != color;
}
