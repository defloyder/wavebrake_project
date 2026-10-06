import '../../core/theme/wb_theme.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/update/apk_installer.dart';
import '../../services/update/update_service.dart';
import '../shared/detail_scaffold.dart';
import '../shared/nav_utils.dart';
import '../shared/toast.dart';
import '../shared/wb_card.dart';

/// The single, consolidated home for everything update-related — replaces
/// both the old header bell (removed: it collided with the logo/wordmark
/// once the offline indicator needed header space too) and About's own
/// "check for updates" row (having the same information live in two
/// places was the actual bug, not just the bell's layout). The Settings
/// bottom-nav/rail icon carries a small badge dot whenever
/// [availableUpdateProvider] resolves non-null (see app_shell.dart) — this
/// screen is where that badge always points to.
class UpdatesScreen extends ConsumerWidget {
  const UpdatesScreen({super.key});

  /// Taps while a check is running are ignored; the answer replaces any
  /// message already on screen (no queue of toasts).
  static bool _checking = false;

  Future<void> _checkForUpdates(BuildContext context, WidgetRef ref) async {
    if (_checking) return;
    _checking = true;
    try {
      final s = ref.read(stringsProvider);
      final messenger = ScaffoldMessenger.of(context);
      ref.invalidate(availableUpdateProvider);
      ref.invalidate(installedRollbackProvider);
      final update = await ref.read(availableUpdateProvider.future);
      if (!context.mounted) return;
      if (update == null) {
        final rolledBack = await ref.read(installedRollbackProvider.future);
        if (!context.mounted) return;
        showToast(messenger, rolledBack != null ? s.rollbackInstalled : s.upToDate);
      }
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final install = ref.watch(apkInstallControllerProvider);
    final pendingUpdate = ref.watch(availableUpdateProvider).asData?.value;
    final downloading = install.status == ApkInstallStatus.downloading;
    final needsPermission = install.status == ApkInstallStatus.needsPermission;
    final installing = install.status == ApkInstallStatus.installing;
    final awaitingConfirmation =
        install.status == ApkInstallStatus.awaitingConfirmation;
    final installed = install.status == ApkInstallStatus.installed;
    final rollback = ref.watch(rollbackOfferProvider).asData?.value;
    final rolledBack =
        ref.watch(installedRollbackProvider).asData?.value != null;

    return DetailScaffold(
      title: s.updates,
      onBack: () => safePop(context, fallback: '/settings/help'),
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
                    color: context.accent.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.system_update_rounded,
                      color: context.accent, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snapshot) {
                      final version = snapshot.data?.version ?? '1.0.0';
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
                            pendingUpdate != null
                                ? '${s.updateAvailable} · ${pendingUpdate.versionName}'
                                : rolledBack
                                    ? s.rollbackInstalled
                                    : s.upToDate,
                            style: TextStyle(
                              fontSize: 13,
                              color: pendingUpdate != null
                                  ? context.accent
                                  : WbColors.ice60,
                              fontWeight: pendingUpdate != null
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
          if (installed) ...[
            _InstalledConfirmation(
              versionName: install.versionName,
              s: s,
              onDone: () =>
                  ref.read(apkInstallControllerProvider.notifier).reset(),
            ),
          ] else if (installing) ...[
            _InstallingIndicator(s: s, versionName: install.versionName),
          ] else if (downloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: install.progress,
                minHeight: 6,
                backgroundColor: WbColors.ice08,
                valueColor: AlwaysStoppedAnimation(context.accent),
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
                  if (pendingUpdate != null) {
                    final notifier =
                        ref.read(apkInstallControllerProvider.notifier);
                    if (needsPermission || awaitingConfirmation) {
                      notifier.retryInstallOrOpenSettings();
                    } else {
                      unawaited(notifier.downloadAndInstall(pendingUpdate));
                    }
                  } else {
                    unawaited(_checkForUpdates(context, ref));
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: context.accent,
                  foregroundColor: WbColors.midnight,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  pendingUpdate == null
                      ? s.checkForUpdates
                      : needsPermission
                          ? s.updateAllowInstalls
                          : s.updateInstall,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          // Bug 14: one step back to the previous version, only while no
          // download/install is running and no newer update is pending.
          if (!installed &&
              !installing &&
              !downloading &&
              !needsPermission &&
              !awaitingConfirmation &&
              pendingUpdate == null &&
              rollback != null) ...[
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
                child: Text(
                    s.rollbackAction.replaceAll('{v}', rollback.versionName)),
              ),
            ),
          ],
        ],
      ),
    );
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
        .read(apkInstallControllerProvider.notifier)
        .downloadAndInstall(rollback.asUpdate));
  }
}

/// Shown from the moment the OS install intent is fired until either this
/// screen is left or (on the next cold start, if the install actually
/// went through) [ApkInstallStatus.installed] takes over — see
/// ApkInstallController.checkPendingInstallCompleted's doc comment for
/// why this can't wait for a completion signal from the install itself.
/// A spinning ring around the update glyph rather than a static icon:
/// Android's own confirmation dialog is about to cover this anyway, but
/// returning to it (backgrounded the dialog, switched apps) should never
/// land on something that reads as stuck.
class _InstallingIndicator extends StatefulWidget {
  const _InstallingIndicator({required this.s, this.versionName});

  final AppStrings s;
  final String? versionName;

  @override
  State<_InstallingIndicator> createState() => _InstallingIndicatorState();
}

class _InstallingIndicatorState extends State<_InstallingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              RotationTransition(
                turns: _controller,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation(context.accent),
                  backgroundColor: WbColors.ice08,
                ),
              ),
              Icon(Icons.system_update_rounded,
                  color: context.accent, size: 18),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.s.updateInstalling,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              if (widget.versionName != null) ...[
                const SizedBox(height: 2),
                Text(
                  widget.versionName!,
                  style: const TextStyle(fontSize: 13, color: WbColors.ice60),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The "you're on the new version now" confirmation — reached only via
/// [ApkInstallController.checkPendingInstallCompleted] on a fresh start,
/// since Android kills this app's process partway through every real
/// install (see that method's own doc comment). By the time anyone sees
/// this, the update has ALREADY been applied — [onDone] just clears the
/// controller back to idle so this screen falls back to its normal
/// "you're up to date" state; there's nothing left to actually open or
/// restart into.
class _InstalledConfirmation extends StatelessWidget {
  const _InstalledConfirmation({
    required this.s,
    required this.onDone,
    this.versionName,
  });

  final AppStrings s;
  final String? versionName;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: WbColors.oceanTeal.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: WbColors.oceanTeal, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.updateInstalledTitle,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  if (versionName != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      versionName!,
                      style:
                          const TextStyle(fontSize: 13, color: WbColors.ice60),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            onPressed: onDone,
            style: FilledButton.styleFrom(
              backgroundColor: WbColors.oceanTeal,
              foregroundColor: WbColors.midnight,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              s.updateOpenApp,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}
