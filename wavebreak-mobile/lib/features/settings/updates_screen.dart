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

  Future<void> _checkForUpdates(BuildContext context, WidgetRef ref) async {
    final s = ref.read(stringsProvider);
    final messenger = ScaffoldMessenger.of(context);
    ref.invalidate(availableUpdateProvider);
    final update = await ref.read(availableUpdateProvider.future);
    if (!context.mounted) return;
    if (update == null) {
      messenger.showSnackBar(SnackBar(content: Text(s.upToDate)));
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
    final installed = install.status == ApkInstallStatus.installed;

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
                                : s.upToDate,
                            style: TextStyle(
                              fontSize: 13,
                              color: pendingUpdate != null
                                  ? WbColors.waveCyan
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
                  if (pendingUpdate != null) {
                    final notifier =
                        ref.read(apkInstallControllerProvider.notifier);
                    if (needsPermission) {
                      notifier.retryInstallOrOpenSettings();
                    } else {
                      unawaited(notifier.downloadAndInstall(pendingUpdate));
                    }
                  } else {
                    unawaited(_checkForUpdates(context, ref));
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
                  pendingUpdate == null
                      ? s.checkForUpdates
                      : needsPermission
                          ? s.updateAllowInstalls
                          : s.updateInstall,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
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
                  valueColor:
                      const AlwaysStoppedAnimation(WbColors.waveCyan),
                  backgroundColor: WbColors.ice08,
                ),
              ),
              const Icon(Icons.system_update_rounded,
                  color: WbColors.waveCyan, size: 18),
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
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
              if (widget.versionName != null) ...[
                const SizedBox(height: 2),
                Text(
                  widget.versionName!,
                  style:
                      const TextStyle(fontSize: 13, color: WbColors.ice60),
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
                      style: const TextStyle(
                          fontSize: 13, color: WbColors.ice60),
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
