import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/session_controller.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/logging/app_logger.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/core_api/models.dart';
import '../../services/device/device_service.dart';
import '../../services/providers.dart';
import '../../services/vpn/connection_manager.dart';
import '../shared/detail_scaffold.dart';
import '../shared/nav_utils.dart';
import '../shared/wb_card.dart';

/// One ready-made request: the subject and the question that opens the
/// email; the rest of the body is the same for every template.
class _Template {
  const _Template(this.icon, this.title, this.hint);

  final IconData icon;
  final String title;
  final String hint;
}

class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  List<_Template> _templates(AppStrings s) => [
        _Template(Icons.wifi_off_rounded, s.tplNoConnect, s.tplNoConnectHint),
        _Template(Icons.speed_rounded, s.tplSlow, s.tplSlowHint),
        _Template(Icons.credit_card_rounded, s.tplSubscription, s.tplSubscriptionHint),
        _Template(Icons.devices_rounded, s.tplDevices, s.tplDevicesHint),
        _Template(Icons.lock_outline_rounded, s.tplLogin, s.tplLoginHint),
        _Template(Icons.flag_outlined, s.reportAProblem, s.tplOtherHint),
      ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(sessionControllerProvider).config;
    final s = ref.watch(stringsProvider);
    final email = config.supportEmail ?? kSupportEmail;

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
          _row(
            s.contactSupportEmail,
            Icons.mail_outline,
            () => _sendEmail(context, s, email),
            subtitle: email,
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
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              s.supportTemplatesTitle,
              style: const TextStyle(
                color: WbColors.ice60,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final t in _templates(s))
            _row(
              t.title,
              t.icon,
              () => _sendTemplate(context, ref, s, email, t),
            ),
        ],
      ),
    );
  }

  /// The body every template shares: the template's own question, the
  /// usual follow-ups, then the details support needs to find the account
  /// and reproduce the problem. The user sees all of it before sending.
  Future<String> _templateBody(WidgetRef ref, AppStrings s, _Template t) async {
    var version = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version} (${info.buildNumber})';
    } catch (_) {}
    var device = Platform.operatingSystem;
    try {
      final (platform, name) =
          await DeviceService(ref.read(coreGatewayProvider)).platformInfo();
      device = '$name, $platform ${Platform.operatingSystemVersion}';
    } catch (_) {}
    final account = ref.read(sessionControllerProvider).user?.email ?? '—';
    final connection = ref.read(connectionManagerProvider);
    final location = connection.location;
    final where = [location.country, location.city]
        .where((part) => part.trim().isNotEmpty)
        .join(' · ');

    return [
      t.hint,
      '',
      '',
      s.tplNetwork,
      '',
      s.tplSince,
      '',
      '',
      '— ${s.tplDiagnostics}',
      'App: WAVEBREAK $version',
      'Device: $device',
      'Account: $account',
      'Location: ${where.isEmpty ? '—' : where}',
      'Status: ${connection.status.name}',
    ].join('\n');
  }

  Future<void> _sendTemplate(BuildContext context, WidgetRef ref,
      AppStrings s, String email, _Template t) async {
    final body = await _templateBody(ref, s, t);
    if (!context.mounted) return;
    await _sendEmail(context, s, email,
        subject: 'WAVEBREAK: ${t.title}', body: body);
  }

  /// Opens the mail app; without one, the address goes to the clipboard.
  Future<void> _sendEmail(
    BuildContext context,
    AppStrings s,
    String email, {
    String? subject,
    String? body,
  }) async {
    final query = [
      if (subject != null) 'subject=${Uri.encodeComponent(subject)}',
      if (body != null) 'body=${Uri.encodeComponent(body)}',
    ].join('&');
    final uri = Uri.parse('mailto:$email${query.isEmpty ? '' : '?$query'}');
    var opened = false;
    try {
      opened = await launchUrl(uri);
    } catch (_) {}
    if (opened) return;
    await Clipboard.setData(ClipboardData(text: email));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.emailCopied.replaceAll('{email}', email))),
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

  Widget _row(String title, IconData icon, VoidCallback onTap, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: WbCard(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: WbColors.waveCyan),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 15)),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: const TextStyle(color: WbColors.ice60, fontSize: 12.5),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: WbColors.ice60),
          ],
        ),
      ),
    );
  }
}
