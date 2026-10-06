import '../env/app_env.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'wb_colors.dart';

class WbTheme {
  const WbTheme._();

  /// [tint] = the selected location's flag accent (null = the V5 defaults:
  /// arctic controls, crimson brand). Controls get a readable light
  /// version of it as `primary`; the raw accent is `tertiary` ([WbAccent]).
  static ThemeData dark({Color? tint}) {
    final accent = tint == null ? WbColors.waveCyan : controlAccent(tint);
    final brand = tint ?? WbColors.crimson;
    final text = GoogleFonts.interTextTheme(
      ThemeData.dark().textTheme,
    ).apply(
      bodyColor: WbColors.ice,
      displayColor: WbColors.ice,
    );

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: WbColors.midnight,
      colorScheme: ColorScheme.dark(
        primary: accent,
        tertiary: brand,
        secondary: accent,
        surface: WbColors.card,
        error: WbColors.error,
        onPrimary: WbColors.midnight,
        onSurface: WbColors.ice,
      ),
      textTheme: text.copyWith(
        headlineLarge: text.headlineLarge?.copyWith(
          fontSize: 30,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
        headlineMedium: text.headlineMedium?.copyWith(
          fontSize: 23,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: text.titleMedium?.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w500,
        ),
        bodyMedium: text.bodyMedium?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: text.bodySmall?.copyWith(
          fontSize: 13,
          color: WbColors.ice60,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: text.headlineMedium?.copyWith(fontSize: 22),
        iconTheme: const IconThemeData(color: WbColors.ice),
      ),
      dividerColor: WbColors.ice08,
      // Material's calculated defaults land on a washed-out light-grey
      // overlay that reads as a mistake against this dark, cyan-accented
      // theme — every InkWell (including the share icon's) gets a
      // brand-tinted hover/press state instead.
      hoverColor: accent.withValues(alpha: 0.07),
      splashColor: accent.withValues(alpha: 0.12),
      highlightColor: accent.withValues(alpha: 0.06),
      // A TV is watched from the sofa: the remote focus must be obvious.
      focusColor: accent.withValues(alpha: AppEnv.isTv ? 0.42 : 0.16),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xF20C1418),
        contentTextStyle: text.bodyMedium,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: WbColors.hairline),
        ),
      ),
      // V5 controls: light primary CTA (as the mockup's "Войти"), quiet
      // outlined secondary, arctic accents, 12 px fields, dark-glass
      // dialogs and sheets. Minimum 44 px tap height everywhere.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: WbColors.ice,
          foregroundColor: WbColors.midnight,
          disabledBackgroundColor: WbColors.ice08,
          minimumSize: const Size(44, 48),
          // The app font (a bare TextStyle here fell back to the system one).
          textStyle: text.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: WbColors.ice,
          minimumSize: const Size(44, 48),
          side: const BorderSide(color: WbColors.hairline),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          minimumSize: const Size(44, 44),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? WbColors.ice : WbColors.ice60),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? accent.withValues(alpha: 0.55)
                : WbColors.ice08),
        trackOutlineColor: const WidgetStatePropertyAll(WbColors.hairline),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xF20A1013),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: WbColors.hairline),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xF20A1013),
        modalBackgroundColor: Color(0xF20A1013),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          side: BorderSide(color: WbColors.hairline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xCC0A1013),
        hintStyle: const TextStyle(color: WbColors.muted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: WbColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: WbColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: WbColors.error),
        ),
      ),
    );
  }
}

/// A flag accent made readable as a control color on the dark background:
/// dark flag colors (navy, deep green) are lifted, neon ones calmed.
Color controlAccent(Color tint) {
  final hsl = HSLColor.fromColor(tint);
  return hsl
      .withLightness(hsl.lightness.clamp(0.62, 0.78))
      .withSaturation(hsl.saturation.clamp(0.0, 0.85))
      .toColor();
}

/// The current accent colors from the theme (they follow the selected
/// location's flag): [accent] for controls, icons and highlights,
/// [brand] for the brand-crimson parts (selected segments, nav pill).
extension WbAccent on BuildContext {
  Color get accent => Theme.of(this).colorScheme.primary;
  Color get brand => Theme.of(this).colorScheme.tertiary;
}
