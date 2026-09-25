import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/update/apk_installer.dart';
import '../../services/update/update_service.dart';
import '../../services/update/windows_update_installer.dart';

/// The expanded detail behind the update bell — replaces the old
/// always-on bottom pill (real feedback: too small/easy to miss against
/// the animated background, and it sat there permanently with nothing to
/// dismiss). The bell + badge (see home_screen.dart's toolbar) is the
/// persistent, glanceable signal that something's pending; this sheet is
/// where the actual "what/why/act on it" content lives, opened on tap and
/// closed like any other bottom sheet — dismissing it only closes this
/// view, it doesn't clear the pending update. The badge stays lit, and
/// About's "check for updates" row (about_screen.dart) keeps showing it
/// too, so closing this sheet is never the last chance to find it again.
Future<void> showUpdateAvailableSheet(
  BuildContext context,
  WidgetRef ref,
  UpdateInfo update,
) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _UpdateAvailableSheet(update: update),
  );
}

class _UpdateAvailableSheet extends ConsumerWidget {
  const _UpdateAvailableSheet({required this.update});

  final UpdateInfo update;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);

    // Android downloads an APK and hands it to the system installer
    // (needs an "allow installs from this source" permission dance);
    // Windows downloads the Inno Setup installer and runs it directly —
    // no OS-mediated install-package concept to route through. Same
    // sheet, same visual language, different controller/action
    // underneath per platform — see windows_update_installer.dart's own
    // doc comment for the full rationale.
    final isWindows = Platform.isWindows;
    final apkInstall =
        isWindows ? null : ref.watch(apkInstallControllerProvider);
    final windowsUpdate =
        isWindows ? ref.watch(windowsUpdateControllerProvider) : null;

    final downloading = isWindows
        ? windowsUpdate!.status == WindowsUpdateStatus.downloading
        : apkInstall!.status == ApkInstallStatus.downloading;
    final needsPermission =
        !isWindows && apkInstall!.status == ApkInstallStatus.needsPermission;
    final readyToRunInstaller = isWindows &&
        windowsUpdate!.status == WindowsUpdateStatus.readyToInstall;
    final progress = isWindows ? windowsUpdate!.progress : apkInstall!.progress;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
          decoration: BoxDecoration(
            color: WbColors.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: WbColors.waveCyan.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: WbColors.ice08,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: WbColors.waveCyan.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.system_update_rounded,
                    color: WbColors.waveCyan, size: 28),
              ),
              const SizedBox(height: 16),
              Text(
                s.updateAvailable,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '${s.version} ${update.versionName}',
                style: const TextStyle(color: WbColors.ice60, fontSize: 13),
              ),
              const SizedBox(height: 20),
              if (downloading) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: WbColors.ice08,
                    valueColor: const AlwaysStoppedAnimation(WbColors.waveCyan),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${s.updateDownloading} ${(progress * 100).round()}%',
                  style: const TextStyle(color: WbColors.ice60, fontSize: 13),
                ),
              ] else
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: () {
                      if (isWindows) {
                        final notifier =
                            ref.read(windowsUpdateControllerProvider.notifier);
                        if (readyToRunInstaller) {
                          notifier.runInstallerAndExit();
                        } else {
                          notifier.downloadAndInstall(update);
                        }
                        return;
                      }
                      final notifier =
                          ref.read(apkInstallControllerProvider.notifier);
                      if (needsPermission) {
                        notifier.retryInstallOrOpenSettings();
                      } else {
                        notifier.downloadAndInstall(update);
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: WbColors.waveCyan,
                      foregroundColor: WbColors.midnight,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      needsPermission ? s.updateAllowInstalls : s.updateInstall,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
