import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/personalization_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../core/theme/wb_theme.dart';
import '../immersive/effects_quality.dart';
import '../shared/wave_params.dart';
import 'settings_ui.dart';

/// Settings > Appearance: language, accent, text size, motion, effects.
class PersonalizationScreen extends ConsumerWidget {
  const PersonalizationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final language = ref.watch(languageProvider);
    final personalization = ref.watch(personalizationProvider);
    final notifier = ref.read(personalizationProvider.notifier);

    return SettingsPage(
      title: s.appearance,
      children: [
        SettingsGroup(children: [
          SettingsRow(
            icon: Icons.language_rounded,
            title: s.language,
            value: stringsFor(language).languageName,
            onTap: () => _pickLanguage(context, ref, language),
          ),
        ]),
        SettingsGroup(
          title: s.accentColor,
          footer: s.accentColorHint,
          children: [
            SettingsBlock(
              child: Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final preset in AccentPreset.values)
                    _AccentSwatch(
                      preset: preset,
                      selected: personalization.accent == preset,
                      label: preset == AccentPreset.auto ? s.automatic : null,
                      onTap: () => notifier.setAccent(preset),
                    ),
                ],
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: s.groupInterface,
          children: [
            SettingsBlock(
              title: s.textSize,
              child: Row(
                children: [
                  for (final preset in TextScalePreset.values)
                    Expanded(
                      child: _TextSizeOption(
                        preset: preset,
                        selected: personalization.textScale == preset,
                        onTap: () => notifier.setTextScale(preset),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: s.groupMotion,
          children: [
            SettingsSwitchRow(
              icon: Icons.motion_photos_off_outlined,
              title: s.reduceMotion,
              subtitle: s.reduceMotionHint,
              value: personalization.reduceMotion,
              onChanged: notifier.setReduceMotion,
            ),
            SettingsBlock(
              title: s.effectsQuality,
              subtitle: s.effectsQualityHint,
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<EffectsQuality>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                        value: EffectsQuality.auto,
                        label: _OneLine(s.effectsAuto)),
                    ButtonSegment(
                        value: EffectsQuality.high,
                        label: _OneLine(s.effectsHigh)),
                    ButtonSegment(
                        value: EffectsQuality.economy,
                        label: _OneLine(s.effectsEconomy)),
                  ],
                  selected: {ref.watch(effectsQualityProvider)},
                  onSelectionChanged: (v) =>
                      ref.read(effectsQualityProvider.notifier).set(v.first),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickLanguage(
    BuildContext context,
    WidgetRef ref,
    AppLanguage current,
  ) async {
    final tint = ref.read(appWaveParamsProvider).tint;
    final picked = await showModalBottomSheet<AppLanguage>(
      context: context,
      // The floating bottom nav pill lives above the branch's nested
      // Navigator: on the root one the sheet isn't painted over by it.
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: wbBlend(WbColors.card, tint, WbColors.sheetLean),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _LanguageSheet(current: current),
    );
    if (picked != null) {
      await ref.read(languageProvider.notifier).setLanguage(picked);
    }
  }
}

class _LanguageSheet extends StatelessWidget {
  const _LanguageSheet({required this.current});

  final AppLanguage current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          // More languages than always fit: capped, scrolls.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: WbColors.ice08,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final lang in AppLanguage.values)
                      ListTile(
                        title: Text(stringsFor(lang).languageName),
                        trailing: lang == current
                            ? Icon(Icons.check_circle, color: context.accent)
                            : null,
                        onTap: () => Navigator.pop(context, lang),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.preset,
    required this.selected,
    required this.onTap,
    this.label,
  });

  final AccentPreset preset;
  final bool selected;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final color = preset.color ?? context.accent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // Automatic shows as a ring of the brand color with no
                  // fill, so it visually reads as "no fixed color" rather
                  // than as just another swatch.
                  color: preset == AccentPreset.auto ? Colors.transparent : color,
                  gradient: preset == AccentPreset.auto
                      ? const SweepGradient(colors: [
                          Color(0xFFE30A17),
                          Color(0xFFFFCE00),
                          Color(0xFF00D6FF),
                          Color(0xFF9B6BFF),
                          Color(0xFFE30A17),
                        ])
                      : null,
                  border: Border.all(
                    color: selected ? WbColors.ice : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: preset == AccentPreset.auto
                    ? Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: WbColors.card,
                        ),
                        // Unlike the flat-color swatches, this ring's fill
                        // is always the same dark card color whether
                        // selected or not — with nothing else in it, the
                        // whole swatch nearly disappears against the dark
                        // background until you happen to select it. An
                        // icon that's always present (swapping for a
                        // checkmark only once selected) keeps it legible
                        // as its own option at rest, not just once active.
                        child: Icon(
                          selected ? Icons.check_rounded : Icons.brightness_auto_rounded,
                          size: 18,
                          color: WbColors.ice,
                        ),
                      )
                    : (selected
                        ? const Icon(Icons.check_rounded, size: 20, color: Colors.white)
                        : null),
              ),
              if (label != null) ...[
                const SizedBox(height: 6),
                Text(label!, style: const TextStyle(fontSize: 11, color: WbColors.ice60)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TextSizeOption extends StatelessWidget {
  const _TextSizeOption({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final TextScalePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: selected ? context.accent.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? context.accent.withValues(alpha: 0.4) : WbColors.ice08,
            ),
          ),
          child: Text(
            'A',
            style: TextStyle(
              fontSize: 14 * preset.scale,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? context.accent : WbColors.ice60,
            ),
          ),
        ),
      ),
    );
  }
}

/// Segment label that shrinks instead of wrapping ("Экономны-й").
class _OneLine extends StatelessWidget {
  const _OneLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text, maxLines: 1, softWrap: false),
      );
}
