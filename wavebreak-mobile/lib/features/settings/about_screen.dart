import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/session_controller.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../shared/detail_scaffold.dart';
import '../shared/nav_utils.dart';
import '../shared/wavebreak_mark.dart';
import '../shared/wb_card.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(sessionControllerProvider).config;
    final s = ref.watch(stringsProvider);

    return DetailScaffold(
      title: s.about,
      onBack: () => safePop(context, fallback: '/settings'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const Center(child: WavebreakMark(size: 64, glow: true)),
          const SizedBox(height: 16),
          const Center(child: WavebreakWordmark()),
          const SizedBox(height: 8),
          Center(
            child: FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                final version = snapshot.data?.version ?? '1.0.0';
                return Text(
                  '${s.version} $version',
                  style: const TextStyle(color: WbColors.ice60),
                );
              },
            ),
          ),
          const SizedBox(height: 28),
          // Update checking/installing now lives in its own consolidated
          // Settings > Updates screen (see updates_screen.dart) — having
          // the same status live here too was the actual bug the header
          // bell's layout complaint traced back to, not just its position.
          if (config.privacyUrl != null)
            _row(s.privacyPolicy,
                () => launchUrl(Uri.parse(config.privacyUrl!))),
          if (config.termsUrl != null)
            _row(
                s.termsOfService, () => launchUrl(Uri.parse(config.termsUrl!))),
          if (config.websiteUrl != null)
            _row(s.website, () => launchUrl(Uri.parse(config.websiteUrl!))),
        ],
      ),
    );
  }

  Widget _row(String title, VoidCallback? onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: WbCard(
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 15, color: WbColors.ice),
              ),
            ),
            const Icon(Icons.chevron_right, color: WbColors.ice60),
          ],
        ),
      ),
    );
  }
}
