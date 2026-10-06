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
import '../../services/core_api/models.dart';
import '../../services/device/device_service.dart';
import '../../services/providers.dart';
import '../../services/vpn/connection_manager.dart';
import 'settings_ui.dart';

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

    return SettingsPage(
      title: s.support,
      fallback: '/settings/help',
      children: [
        SettingsGroup(
          title: s.groupContact,
          children: [
            if (config.supportTelegram != null)
              SettingsRow(
                icon: Icons.send_outlined,
                title: s.contactSupportTelegram,
                onTap: () => launchUrl(Uri.parse(config.supportTelegram!)),
              ),
            SettingsRow(
              icon: Icons.mail_outline_rounded,
              title: s.contactSupportEmail,
              subtitle: email,
              onTap: () => _sendEmail(context, s, email),
            ),
            if (config.helpUrl != null)
              SettingsRow(
                icon: Icons.help_outline_rounded,
                title: s.helpCenter,
                onTap: () => launchUrl(Uri.parse(config.helpUrl!)),
              ),
            // A plain text export handed to the system share sheet, so a
            // report like "won't connect on my carrier" can come with the
            // app's own connection/error trail, no cable or adb needed.
            SettingsRow(
              icon: Icons.bug_report_outlined,
              title: s.exportDiagnosticLogs,
              onTap: () => _exportLogs(context),
            ),
          ],
        ),
        SettingsGroup(
          title: s.supportTemplatesTitle,
          children: [
            for (final t in _templates(s))
              SettingsRow(
                icon: t.icon,
                title: t.title,
                onTap: () => _sendTemplate(context, ref, s, email, t),
              ),
          ],
        ),
      ],
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
    if (Platform.isAndroid) {
      // Own share on Android: the receiving app (Telegram) opens in its own
      // task, not inside WAVEBREAK's — see FileSharer.kt.
      try {
        final shared = await const MethodChannel('app.wavebreak/share')
            .invokeMethod<bool>('shareFile', {
          'path': file.path,
          'mimeType': 'text/plain',
          'text': 'WAVEBREAK diagnostic log',
        });
        if (shared == true) return;
      } catch (_) {
        // Fall back to share_plus below.
      }
      if (!context.mounted) return;
    }
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'WAVEBREAK diagnostic log',
    );
  }

}
