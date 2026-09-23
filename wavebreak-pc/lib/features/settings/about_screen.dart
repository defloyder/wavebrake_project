import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/session_controller.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/update/apk_installer.dart';
import '../../services/update/update_service.dart';
import '../../services/update/windows_update_installer.dart';
import '../shared/detail_scaffold.dart';
import '../shared/nav_utils.dart';
import '../shared/wavebreak_mark.dart';
import '../shared/wb_card.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  Future<void> _checkForUpdates(BuildContext context, WidgetRef ref) async {
    final s = ref.read(stringsProvider);
    final messenger = ScaffoldMessenger.of(context);
    // Belt-and-suspenders alongside the automatic check the app already
    // does on its own (see availableUpdateProvider / the bottom banner in
    // app.dart) — this just forces that same check to run again right
    // now instead of waiting for whatever triggered the last one, and
    // gives feedback either way instead of only ever showing UI when an
    // update happens to already be available.
    ref.invalidate(availableUpdateProvider);
    final update = await ref.read(availableUpdateProvider.future);
    if (!context.mounted) return;
    if (update == null) {
      messenger.showSnackBar(SnackBar(content: Text(s.upToDate)));
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(s.updateAvailable)));
    if (Platform.isWindows) {
      unawaited(ref
          .read(windowsUpdateControllerProvider.notifier)
          .downloadAndInstall(update));
    } else {
      unawaited(ref
          .read(apkInstallControllerProvider.notifier)
          .downloadAndInstall(update));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(sessionControllerProvider).config;
    final s = ref.watch(stringsProvider);
    // Android downloads+installs an APK; Windows downloads+runs the
    // Inno Setup installer (see windows_update_installer.dart) — either
    // way, "is a download currently in flight" for this row's own label.
    final downloadingUpdate = Platform.isWindows
        ? ref.watch(windowsUpdateControllerProvider).status ==
            WindowsUpdateStatus.downloading
        : ref.watch(apkInstallControllerProvider).status ==
            ApkInstallStatus.downloading;
    // Mirrors the same pending-update state the Home toolbar's bell badge
    // reflects (see update_available_sheet.dart's comment on why that
    // bell needs a second, always-reachable place to point to) — closing
    // the bell's sheet never loses this, since it never lived only there.
    final pendingUpdate = (Platform.isAndroid || Platform.isWindows)
        ? ref.watch(availableUpdateProvider).asData?.value
        : null;

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
          // Android ships outside the Play Store, so this is the only
          // in-app path to a new build (see update_service.dart);
          // Windows ships outside any app store too, same reasoning —
          // both get this row. iOS has no equivalent self-update flow.
          if (Platform.isAndroid || Platform.isWindows)
            _row(
              downloadingUpdate
                  ? s.updateDownloading
                  : pendingUpdate != null
                      ? s.updateAvailable
                      : s.checkForUpdates,
              downloadingUpdate ? null : () => _checkForUpdates(context, ref),
              badged: pendingUpdate != null,
            ),
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

  Widget _row(String title, VoidCallback? onTap, {bool badged = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: WbCard(
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  color: badged ? WbColors.waveCyan : WbColors.ice,
                  fontWeight: badged ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            if (badged) ...[
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 10),
                decoration: const BoxDecoration(
                  color: WbColors.waveCyan,
                  shape: BoxShape.circle,
                ),
              ),
            ],
            const Icon(Icons.chevron_right, color: WbColors.ice60),
          ],
        ),
      ),
    );
  }
}
