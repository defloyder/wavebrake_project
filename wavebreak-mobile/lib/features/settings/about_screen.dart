import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/session_controller.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../shared/wavebreak_mark.dart';
import 'settings_ui.dart';

/// About (P15): the mark, the version, the documents. Nothing else —
/// updates have their own page next to this one (Help).
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(sessionControllerProvider).config;
    final s = ref.watch(stringsProvider);
    final language = ref.watch(languageProvider);

    return SettingsPage(
      title: s.about,
      fallback: '/settings/help',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
          child: Column(
            children: [
              const WavebreakMark(size: 56, glow: true),
              const SizedBox(height: 14),
              const WavebreakWordmark(),
              const SizedBox(height: 8),
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  final info = snapshot.data;
                  return Text(
                    info == null
                        ? s.version
                        : '${s.version} ${info.version} (${info.buildNumber})',
                    style: const TextStyle(color: WbColors.muted),
                  );
                },
              ),
            ],
          ),
        ),
        SettingsGroup(
          title: s.groupLegal,
          children: [
            // The legal pages the site publishes, in the app's language
            // where the site has it.
            SettingsRow(
              icon: Icons.privacy_tip_outlined,
              title: s.privacyPolicy,
              onTap: () =>
                  launchUrl(Uri.parse(legalPageUrl('privacy', language))),
            ),
            SettingsRow(
              icon: Icons.description_outlined,
              title: s.termsOfService,
              onTap: () =>
                  launchUrl(Uri.parse(legalPageUrl('terms', language))),
            ),
            if (config.websiteUrl != null)
              SettingsRow(
                icon: Icons.language_rounded,
                title: s.website,
                onTap: () => launchUrl(Uri.parse(config.websiteUrl!)),
              ),
          ],
        ),
      ],
    );
  }
}

/// A legal page on the site (`privacy` — privacy policy and personal data
/// processing, `terms` — terms of use) in [language] where the site has
/// it: Russian at the root, Turkish under /tr, English for the rest.
String legalPageUrl(String page, AppLanguage language) {
  const site = 'https://wavebreak.com.tr';
  final prefix = switch (language) {
    AppLanguage.ru => '',
    AppLanguage.tr => '/tr',
    _ => '/en',
  };
  return '$site$prefix/$page';
}
