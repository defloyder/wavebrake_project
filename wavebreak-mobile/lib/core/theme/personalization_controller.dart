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

class PersonalizationState {
  const PersonalizationState({
    this.accent = AccentPreset.auto,
    this.textScale = TextScalePreset.standard,
    this.reduceMotion = false,
  });

  final AccentPreset accent;
  final TextScalePreset textScale;
  final bool reduceMotion;

  PersonalizationState copyWith({
    AccentPreset? accent,
    TextScalePreset? textScale,
    bool? reduceMotion,
  }) {
    return PersonalizationState(
      accent: accent ?? this.accent,
      textScale: textScale ?? this.textScale,
      reduceMotion: reduceMotion ?? this.reduceMotion,
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
    return PersonalizationState(
      accent: accent,
      textScale: textScale,
      reduceMotion: reduceMotion,
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
}
