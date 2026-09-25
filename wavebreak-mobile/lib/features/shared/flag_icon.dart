import 'package:flutter/material.dart';

import '../../core/theme/flag_colors.dart';

/// A small, hand-painted flag glyph — not an emoji. Windows' default font
/// stack doesn't reliably render regional-indicator flag emoji (they show
/// up as bare letter pairs like "TR"/"NL"), so real flags are drawn instead
/// for a look that's consistent everywhere the app runs.
class FlagIcon extends StatelessWidget {
  const FlagIcon({super.key, required this.countryCode, this.width = 24});

  final String countryCode;
  final double width;

  @override
  Widget build(BuildContext context) {
    final height = width * 0.72;
    return ClipRRect(
      borderRadius: BorderRadius.circular(width * 0.14),
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _FlagPainter(countryCode.toUpperCase()),
        ),
      ),
    );
  }
}

class _FlagPainter extends CustomPainter {
  _FlagPainter(this.code);

  final String code;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    switch (code) {
      case 'NL':
        _stripesHorizontal(canvas, size, [
          const Color(0xFFAE1C28),
          Colors.white,
          const Color(0xFF21468B),
        ]);
        return;
      case 'FI':
        _nordicCross(canvas, size, Colors.white, const Color(0xFF002F6C));
        return;
      case 'TR':
        _turkey(canvas, size);
        return;
      default:
        // Any location we haven't hand-painted the real geometry for still
        // gets a diagonal gradient through ALL of its real flag colors (not
        // just the first and last — a flag's middle color, e.g. white on a
        // tricolor, is still part of what makes it recognizable).
        final colors = flagColorsFor(code);
        final paint = Paint()
          ..shader = LinearGradient(colors: colors).createShader(rect);
        canvas.drawRect(rect, paint);
    }
  }

  void _stripesHorizontal(Canvas canvas, Size size, List<Color> colors) {
    final stripeHeight = size.height / colors.length;
    for (var i = 0; i < colors.length; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, stripeHeight * i, size.width, stripeHeight + 0.5),
        Paint()..color = colors[i],
      );
    }
  }

  void _nordicCross(Canvas canvas, Size size, Color field, Color cross) {
    canvas.drawRect(Offset.zero & size, Paint()..color = field);
    final crossThickness = size.height * 0.22;
    final crossX = size.width * 0.34;
    canvas.drawRect(
      Rect.fromLTWH(0, size.height / 2 - crossThickness / 2, size.width, crossThickness),
      Paint()..color = cross,
    );
    canvas.drawRect(
      Rect.fromLTWH(crossX - crossThickness / 2, 0, crossThickness, size.height),
      Paint()..color = cross,
    );
  }

  void _turkey(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFE30A17));
    final center = Offset(size.width * 0.42, size.height * 0.5);
    final r = size.height * 0.26;
    canvas.drawCircle(center, r, Paint()..color = Colors.white);
    canvas.drawCircle(
      Offset(center.dx + r * 0.35, center.dy),
      r * 0.82,
      Paint()..color = const Color(0xFFE30A17),
    );
    // A tiny star, simplified to a dot at this size.
    canvas.drawCircle(
      Offset(size.width * 0.58, size.height * 0.5),
      size.height * 0.06,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _FlagPainter oldDelegate) => oldDelegate.code != code;
}
