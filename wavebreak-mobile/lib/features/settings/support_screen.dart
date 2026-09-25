import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/session_controller.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/logging/app_logger.dart';
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
          // No fancy in-app log viewer — this is a plain text export
          // handed straight to the system share sheet, so a report
          // like "VPN won't connect on my carrier" can come back
          // with the app's own connection/error trail attached even
          // from someone with no USB cable or adb access at all.
          _row(
            s.exportDiagnosticLogs,
            Icons.bug_report_outlined,
            () => _exportLogs(context),
          ),
        ],
      ),
    );
  }

  Future<void> _exportLogs(BuildContext context) async {
    final file = await AppLogger.exportToFile();
    if (!context.mounted) return;
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'WAVEBREAK diagnostic log',
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
