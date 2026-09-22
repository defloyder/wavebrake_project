import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/update/apk_installer.dart';
import '../../services/update/update_service.dart';

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
    final install = ref.watch(apkInstallControllerProvider);
    final downloading = install.status == ApkInstallStatus.downloading;
    final needsPermission = install.status == ApkInstallStatus.needsPermission;

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
                    value: install.progress,
                    minHeight: 6,
                    backgroundColor: WbColors.ice08,
                    valueColor: const AlwaysStoppedAnimation(WbColors.waveCyan),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${s.updateDownloading} ${(install.progress * 100).round()}%',
                  style: const TextStyle(color: WbColors.ice60, fontSize: 13),
                ),
              ] else
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: () {
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
