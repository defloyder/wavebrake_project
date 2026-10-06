import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/flag_colors.dart';

/// A location's flag. On Android it is the system's own flag emoji — every
/// country, real geometry (owner, 06.10: Germany and other countries
/// without a hand-painted flag showed a smear of their colors). Elsewhere
/// (Windows' fonts don't draw flag emoji, tests) a hand-painted flag.
class FlagIcon extends StatelessWidget {
  const FlagIcon({super.key, required this.countryCode, this.width = 24});

  final String countryCode;
  final double width;

  static final _iso = RegExp(r'^[A-Z]{2}$');

  @override
  Widget build(BuildContext context) {
    final height = width * 0.72;
    final code = countryCode.toUpperCase();
    final emoji = defaultTargetPlatform == TargetPlatform.android &&
            _iso.hasMatch(code)
        ? flagEmoji(code)
        : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(width * 0.14),
      child: SizedBox(
        width: width,
        height: height,
        child: emoji != null
            // The glyph is square with the flag in its middle: cover
            // crops the empty top and bottom so the flag fills the box.
            ? FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: Text(emoji,
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(fontSize: 64, height: 1)),
              )
            : CustomPaint(painter: _FlagPainter(code)),
      ),
    );
  }
}

class _FlagPainter extends CustomPainter {
  _FlagPainter(this.code);

  final String code;

  @override
  void paint(Canvas canvas, Size size) {
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
      case 'RU':
        _stripesHorizontal(canvas, size, [
          Colors.white,
          const Color(0xFF0039A6),
          const Color(0xFFD52B1E),
        ]);
        return;
      case 'TR':
        _turkey(canvas, size);
        return;
      default:
        // No hand-painted geometry: the flag's colors as stripes — closer
        // to a flag than the diagonal smear this used to be.
        _stripesHorizontal(canvas, size, flagColorsFor(code));
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
