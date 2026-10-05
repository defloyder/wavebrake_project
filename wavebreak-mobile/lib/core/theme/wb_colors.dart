import 'package:flutter/material.dart';

// Palette ported from wavebreak-web's design tokens
// (wavebreak-web/public/css/wavebreak-site.css :root — --paper, --muted,
// --cyan, --line, and the body/section backgrounds) so the app reads as
// the same product as the public site: a near-black background rather
// than the app's previous navy-blue, and the site's softer cyan
// (`#80edf0`) instead of a saturated neon one. Kept as the same named
// constants the rest of the app already references (WbColors.waveCyan,
// .midnight, .card, ...) so this is a palette retune, not a rewrite —
// every screen picks the new colors up automatically.
class WbColors {
  const WbColors._();

  // Reverted from wavebreak-web's near-black/soft-cyan retune back to the
  // app's own original palette (dark navy, saturated cyan) — the site and
  // the app are allowed to look like different surfaces of the same
  // brand; explicit product decision, not an oversight.
  // V5 (immersive) palette — same names, so every screen follows.
  static const midnight = Color(0xFF050305);
  static const deepOcean = Color(0xFF0C0709);
  static const waveCyan = Color(0xFF7CEEE8); // arctic: quality, protection
  static const oceanTeal = Color(0xFF57CFC8);
  static const crimson = Color(0xFFFF344E); // brand: waves, sphere
  static const ice = Color(0xFFF5F2F0);
  static const background = Color(0xFF050305);
  static const card = Color(0xFF0C1418);
  static const oceanBlue = Color(0xFF0876C9);

  /// Site's `--muted` (#93a4aa) — secondary/dimmed text. New token; the
  /// app's existing screens mostly use [ice60] for this role already, so
  /// this is additive rather than a replacement everywhere.
  static const muted = Color(0xFF8E929E);

  /// Site's `--line` (#1b2b30) — hairline borders/dividers on dark
  /// surfaces. New token, same reasoning as [muted].
  static const hairline = Color(0x65506572);

  static const ice60 = Color(0xA6F5F2F0);
  static const ice08 = Color(0x18F5F2F0);

  static const warning = Color(0xFFFFB23F);
  static const error = Color(0xFFFF5C6C);

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
