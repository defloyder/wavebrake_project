import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/update/update_service.dart';
import '../../services/update/windows_update_installer.dart';
import '../shared/detail_scaffold.dart';
import '../shared/nav_utils.dart';
import '../shared/wb_card.dart';

/// Settings > Updates on Windows: the installed version, whether a newer
/// one is out, downloading it with progress and installing it (the
/// installer replaces the app and relaunches it), and the one-step
/// rollback when the server offers one (bug 14). Mirrors the Android
/// screen of the same name.
class UpdatesScreen extends ConsumerWidget {
  const UpdatesScreen({super.key});

  Future<void> _check(BuildContext context, WidgetRef ref) async {
    final s = ref.read(stringsProvider);
    final messenger = ScaffoldMessenger.of(context);
    ref.invalidate(availableUpdateProvider);
    ref.invalidate(rollbackOfferProvider);
    final update = await ref.read(availableUpdateProvider.future);
    if (update == null) {
      messenger.showSnackBar(SnackBar(content: Text(s.upToDate)));
    }
  }

  Future<void> _rollBack(
      BuildContext context, WidgetRef ref, RollbackInfo rollback) async {
    final s = ref.read(stringsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: WbColors.card,
        title: Text(s.rollbackConfirmTitle),
        content:
            Text(s.rollbackConfirmBody.replaceAll('{v}', rollback.versionName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.rollbackConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    unawaited(ref
        .read(windowsUpdateControllerProvider.notifier)
        .downloadAndInstall(rollback.asUpdate));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final install = ref.watch(windowsUpdateControllerProvider);
    final controller = ref.read(windowsUpdateControllerProvider.notifier);
    final pending = ref.watch(availableUpdateProvider).asData?.value;
    final rollback = ref.watch(rollbackOfferProvider).asData?.value;
    final downloading = install.status == WindowsUpdateStatus.downloading;
    final ready = install.status == WindowsUpdateStatus.readyToInstall;
    final failed = install.status == WindowsUpdateStatus.failed;

    final String label;
    final VoidCallback? action;
    if (ready) {
      label = s.updateInstall;
      action = () => unawaited(controller.runInstallerAndExit());
    } else if (pending != null) {
      label = s.updateInstall;
      action = () => unawaited(controller.downloadAndInstall(pending));
    } else {
      label = s.checkForUpdates;
      action = () => unawaited(_check(context, ref));
    }

    return DetailScaffold(
      title: s.updates,
      onBack: () => safePop(context, fallback: '/settings'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          WbCard(
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: WbColors.waveCyan.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.system_update_rounded,
                      color: WbColors.waveCyan, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snapshot) {
                      final version = snapshot.data?.version ?? '';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${s.version} $version',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            pending != null
                                ? '${s.updateAvailable} · ${pending.versionName}'
                                : s.upToDate,
                            style: TextStyle(
                              fontSize: 13,
                              color: pending != null
                                  ? WbColors.waveCyan
                                  : WbColors.ice60,
                              fontWeight: pending != null
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
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
          ] else ...[
            if (failed) ...[
              Text(
                s.errUnavailable,
                style: const TextStyle(color: WbColors.warning, fontSize: 13),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: action,
                style: FilledButton.styleFrom(
                  backgroundColor: WbColors.waveCyan,
                  foregroundColor: WbColors.midnight,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            // Bug 14: one step back, only when nothing newer is pending.
            if (!ready && pending == null && rollback != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: () => _rollBack(context, ref, rollback),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: WbColors.ice,
                    side: const BorderSide(color: WbColors.ice08),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(s.rollbackAction
                      .replaceAll('{v}', rollback.versionName)),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
