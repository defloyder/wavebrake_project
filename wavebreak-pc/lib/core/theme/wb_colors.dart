import 'package:flutter/material.dart';

class WbColors {
  const WbColors._();

  static const midnight = Color(0xFF0B1020);
  static const deepOcean = Color(0xFF0F1E2E);
  static const waveCyan = Color(0xFF00D6FF);
  static const oceanTeal = Color(0xFF00B4C8);
  static const ice = Color(0xFFE6F2F7);
  static const background = Color(0xFF080D18);
  static const card = Color(0xFF111A2B);
  static const oceanBlue = Color(0xFF0876C9);

  static const ice60 = Color(0x99E6F2F7);
  static const ice08 = Color(0x14E6F2F7);

  static const warning = Color(0xFFE8B84A);
  static const error = Color(0xFFE57373);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [waveCyan, oceanTeal, oceanBlue],
  );
}

/// Blends [base] a little toward [tint] (the current location's flag
/// accent, or null for "no server selected") — the one shared recipe every
/// surface (cards, sheets, popups, nav) uses so the whole app leans toward
/// the same color at the same gentle strength instead of each screen
/// inventing its own amount.
Color wbBlend(Color base, Color? tint, [double amount = 0.28]) =>
    tint == null ? base : Color.lerp(base, tint, amount) ?? base;
