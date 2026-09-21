import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/session_controller.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../shared/detail_scaffold.dart';
import '../shared/nav_utils.dart';
import '../shared/wb_card.dart';

class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(sessionControllerProvider).config;
    final s = ref.watch(stringsProvider);

    return DetailScaffold(
      title: s.support,
      onBack: () => safePop(context, fallback: '/settings'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
                if (config.helpUrl != null)
                  _row(
                    s.helpCenter,
                    Icons.help_outline,
                    () => launchUrl(Uri.parse(config.helpUrl!)),
                  ),
                if (config.supportTelegram != null)
                  _row(
                    s.contactSupportTelegram,
                    Icons.send_outlined,
                    () => launchUrl(Uri.parse(config.supportTelegram!)),
                  ),
                if (config.supportEmail != null)
                  _row(
                    s.contactSupportEmail,
                    Icons.mail_outline,
                    () => launchUrl(
                      Uri(scheme: 'mailto', path: config.supportEmail),
                    ),
                  ),
                _row(
                  s.reportAProblem,
                  Icons.flag_outlined,
                  () => launchUrl(
                    Uri(
                      scheme: 'mailto',
                      path: config.supportEmail ?? 'support@wavebreak.app',
                      query: 'subject=WAVEBREAK issue report',
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _row(String title, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: WbCard(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: WbColors.waveCyan),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15))),
            const Icon(Icons.chevron_right, color: WbColors.ice60),
          ],
        ),
      ),
    );
  }
}
