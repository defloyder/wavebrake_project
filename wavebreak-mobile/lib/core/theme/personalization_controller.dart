import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/prefs_store.dart';
import 'wb_colors.dart';

/// Named accent presets a user can pin the whole app to instead of the
/// automatic per-server flag tint. Kept as a fixed small palette (rather
/// than a free color picker) so every preset is one that's actually been
/// checked to read well against [WbColors.midnight]/[WbColors.deepOcean].
enum AccentPreset {
  auto(null),
  cyan(WbColors.waveCyan),
  violet(Color(0xFF9B6BFF)),
  rose(Color(0xFFFF6B9B)),
  amber(Color(0xFFFFB84A)),
  emerald(Color(0xFF3ECF8E)),
  crimson(Color(0xFFE85D5D));

  const AccentPreset(this.color);

  /// Null only for [auto] — every other preset carries its fixed color.
  final Color? color;
}

enum TextScalePreset {
  compact(0.92),
  standard(1.0),
  large(1.15),
  xlarge(1.3);

  const TextScalePreset(this.scale);
  final double scale;
}

/// The connect sphere's look (P16). [earth] is the full V5 sphere (Earth
/// texture in the shader; on Economy it shows as [glass]), [glass] the
/// glass sphere without the texture, [minimal] a light ring around the mark.
enum SphereStyle { earth, glass, minimal }

/// How visible the wave background is (P16). Multiplies the waves'
/// brightness; [calm] also draws fewer lines (lighter on old phones).
enum BackgroundIntensity {
  calm(0.45, 0.6),
  normal(1.0, 1.0),
  vivid(1.5, 1.0);

  const BackgroundIntensity(this.strength, this.layerFactor);
  final double strength;
  final double layerFactor;
}

/// Spacing of lists and cards (P16): compact fits more on a screen.
enum UiDensity { normal, compact }

class PersonalizationState {
  const PersonalizationState({
    this.accent = AccentPreset.auto,
    this.textScale = TextScalePreset.standard,
    this.reduceMotion = false,
    this.sphereStyle = SphereStyle.earth,
    this.background = BackgroundIntensity.normal,
    this.density = UiDensity.normal,
  });

  final AccentPreset accent;
  final TextScalePreset textScale;
  final bool reduceMotion;
  final SphereStyle sphereStyle;
  final BackgroundIntensity background;
  final UiDensity density;

  PersonalizationState copyWith({
    AccentPreset? accent,
    TextScalePreset? textScale,
    bool? reduceMotion,
    SphereStyle? sphereStyle,
    BackgroundIntensity? background,
    UiDensity? density,
  }) {
    return PersonalizationState(
      accent: accent ?? this.accent,
      textScale: textScale ?? this.textScale,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      sphereStyle: sphereStyle ?? this.sphereStyle,
      background: background ?? this.background,
      density: density ?? this.density,
    );
  }
}

final personalizationProvider =
    NotifierProvider<PersonalizationController, PersonalizationState>(
  PersonalizationController.new,
);

class PersonalizationController extends Notifier<PersonalizationState> {
  @override
  PersonalizationState build() {
    final accentName = PrefsStore.getString(PrefsStore.accentOverride);
    final accent = AccentPreset.values.firstWhere(
      (a) => a.name == accentName,
      orElse: () => AccentPreset.auto,
    );
    final scaleValue = PrefsStore.getDouble(PrefsStore.textScale);
    final textScale = TextScalePreset.values.firstWhere(
      (t) => t.scale == scaleValue,
      orElse: () => TextScalePreset.standard,
    );
    final reduceMotion = PrefsStore.getBool(PrefsStore.reduceMotion);
    T pick<T extends Enum>(List<T> values, String key, T fallback) {
      final name = PrefsStore.getString(key);
      return values.firstWhere((v) => v.name == name, orElse: () => fallback);
    }

    return PersonalizationState(
      accent: accent,
      textScale: textScale,
      reduceMotion: reduceMotion,
      sphereStyle:
          pick(SphereStyle.values, PrefsStore.sphereStyle, SphereStyle.earth),
      background: pick(BackgroundIntensity.values,
          PrefsStore.backgroundIntensity, BackgroundIntensity.normal),
      density: pick(UiDensity.values, PrefsStore.uiDensity, UiDensity.normal),
    );
  }

  Future<void> setAccent(AccentPreset preset) async {
    state = state.copyWith(accent: preset);
    await PrefsStore.setString(PrefsStore.accentOverride, preset.name);
  }

  Future<void> setTextScale(TextScalePreset preset) async {
    state = state.copyWith(textScale: preset);
    await PrefsStore.setDouble(PrefsStore.textScale, preset.scale);
  }

  Future<void> setReduceMotion(bool value) async {
    state = state.copyWith(reduceMotion: value);
    await PrefsStore.setBool(PrefsStore.reduceMotion, value);
  }

  Future<void> setSphereStyle(SphereStyle value) async {
    state = state.copyWith(sphereStyle: value);
    await PrefsStore.setString(PrefsStore.sphereStyle, value.name);
  }

  Future<void> setBackground(BackgroundIntensity value) async {
    state = state.copyWith(background: value);
    await PrefsStore.setString(PrefsStore.backgroundIntensity, value.name);
  }

  Future<void> setDensity(UiDensity value) async {
    state = state.copyWith(density: value);
    await PrefsStore.setString(PrefsStore.uiDensity, value.name);
  }
}
