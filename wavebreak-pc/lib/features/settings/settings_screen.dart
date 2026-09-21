import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../shared/menu_button.dart';
import '../shared/ocean_background.dart';
import '../shared/wave_params.dart';
import '../shared/wb_card.dart';
import '../shell/app_shell.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final language = ref.watch(languageProvider);
    final waves = ref.watch(appWaveParamsProvider);

    // See LocationsScreen — same isDesktop-aware widening so this doesn't
    // stay a narrow mobile-width list adrift in a big dark window.
    return LayoutBuilder(
      builder: (context, outer) {
        final isDesktop = outer.maxWidth >= 820;
        return OceanBackground(
      illuminate: true,
      tint: waves.tint,
      waveSpeed: waves.speed,
      waveAmplitude: waves.amplitude,
      maxContentWidth: isDesktop ? 640 : 560,
      child: SafeArea(
        child: ListView(
          // Same reason as Home: the bottom nav pill floats over the body
          // now instead of reserving a Scaffold slot, so mobile needs the
          // extra bottom padding manually or the last row ends up under it.
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            isDesktop ? 12 : kMobileBottomBarReserve + 12,
          ),
          children: [
            Row(
              children: [
                // The side rail this toggles only exists on desktop — on
                // mobile there's nothing for it to expand, so it's omitted
                // rather than left as a dead tap target.
                if (isDesktop) ...[
                  const MenuButton(),
                  const SizedBox(width: 12),
                ],
                Text(
                  s.settings,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _row(context, s.account, Icons.person_outline, '/settings/account'),
            _row(context, s.connection, Icons.wifi_tethering, '/settings/connection'),
            _row(context, s.security, Icons.fingerprint, '/settings/security'),
            _row(context, s.notifications, Icons.notifications_none, '/settings/notifications'),
            _row(context, s.personalization, Icons.palette_outlined, '/settings/personalization'),
            _languageRow(context, ref, s, language),
            _row(context, s.support, Icons.chat_bubble_outline, '/settings/support'),
            _row(context, s.about, Icons.info_outline, '/settings/about'),
          ],
        ),
      ),
        );
      },
    );
  }

  Widget _row(BuildContext context, String title, IconData icon, String path) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: WbCard(
        onTap: () => context.push(path),
        child: Row(
          children: [
            Icon(icon, color: WbColors.waveCyan),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
            const Icon(Icons.chevron_right, color: WbColors.ice60),
          ],
        ),
      ),
    );
  }

  Widget _languageRow(
    BuildContext context,
    WidgetRef ref,
    AppStrings s,
    AppLanguage current,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: WbCard(
        onTap: () => _pickLanguage(context, ref, current),
        child: Row(
          children: [
            const Icon(Icons.language, color: WbColors.waveCyan),
            const SizedBox(width: 12),
            Expanded(child: Text(s.language, style: const TextStyle(fontSize: 16))),
            Text(
              stringsFor(current).languageName,
              style: const TextStyle(color: WbColors.ice60, fontSize: 14),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: WbColors.ice60),
          ],
        ),
      ),
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
      // See share_subscription_sheet.dart — without this the floating
      // bottom nav pill paints over the sheet's own bottom edge since it
      // lives above the branch's nested Navigator, not the root one.
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: wbBlend(WbColors.card, tint, 0.12),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              // The list of languages has grown past what always fits on
              // one screen — cap it and let it scroll rather than silently
              // clipping the last few entries off the bottom.
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
                                ? const Icon(Icons.check_circle, color: WbColors.waveCyan)
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
      },
    );
    if (picked != null) {
      await ref.read(languageProvider.notifier).setLanguage(picked);
    }
  }
}
