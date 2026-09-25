import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/language_controller.dart';
import '../../core/theme/personalization_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../shared/detail_scaffold.dart';
import '../shared/nav_utils.dart';
import '../shared/wb_card.dart';

class PersonalizationScreen extends ConsumerWidget {
  const PersonalizationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final personalization = ref.watch(personalizationProvider);
    final notifier = ref.read(personalizationProvider.notifier);

    return DetailScaffold(
      title: s.personalization,
      onBack: () => safePop(context, fallback: '/settings'),
      child: ListView(
        children: [
          Text(
            s.accentColor,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            s.accentColorHint,
            style: const TextStyle(color: WbColors.ice60, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          WbCard(
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
          const SizedBox(height: 24),
          Text(
            s.textSize,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          WbCard(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
          const SizedBox(height: 24),
          WbCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.reduceMotion,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.reduceMotionHint,
                        style: const TextStyle(color: WbColors.ice60, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: personalization.reduceMotion,
                  activeTrackColor: WbColors.waveCyan,
                  onChanged: notifier.setReduceMotion,
                ),
              ],
            ),
          ),
        ],
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
    final color = preset.color ?? WbColors.waveCyan;
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
            color: selected ? WbColors.waveCyan.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? WbColors.waveCyan.withValues(alpha: 0.4) : WbColors.ice08,
            ),
          ),
          child: Text(
            'A',
            style: TextStyle(
              fontSize: 14 * preset.scale,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? WbColors.waveCyan : WbColors.ice60,
            ),
          ),
        ),
      ),
    );
  }
}
