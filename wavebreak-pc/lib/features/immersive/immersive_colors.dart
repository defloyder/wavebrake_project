import 'package:flutter/painting.dart';

/// Design tokens of the immersive (V5) look. Kept apart from [WbColors] so
/// screens not yet moved to the new look keep their palette.
class Ic {
  const Ic._();

  static const background = Color(0xFF050305);
  static const backgroundAlt = Color(0xFF060305);
  static const text = Color(0xFFF5F2F0);
  static const textSecondary = Color(0xFFB3AFB6);
  static const textMuted = Color(0xFF8E929E);
  static const crimson = Color(0xFFFF344E);
  static const burgundy = Color(0xFF5A0A18);
  static const arctic = Color(0xFF7CEEE8);
  static const amber = Color(0xFFFFB23F);

  /// Dark glass surface.
  static const glassTop = Color(0xC9111D23);
  static const glassMid = Color(0xE8070D11);
  static const glassBottom = Color(0xE003070A);
  static const glassBorder = Color(0x65506572);
  static const glassReflex = Color(0x10D4F7F0);

  static const glass = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [glassTop, glassMid, glassBottom],
  );

  static const fontSerif = 'serif';
}
