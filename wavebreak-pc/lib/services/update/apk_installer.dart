import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/logging/app_logger.dart';
import '../../core/storage/prefs_store.dart';
import 'resumable_download.dart';
import 'update_service.dart';

enum ApkInstallStatus {
  idle,
  downloading,
  needsPermission,
  // The OS install intent has been fired — Android's own "Install" dialog
  // is (or is about to be) on screen. Named for what's actually
  // happening rather than "readyToInstall" (its old name): by this point
  // the app has already committed to installing, it's just waiting on
  // the one confirmation tap Android itself requires for a non-Play-
  // Store package (see UpdateInstaller.kt's own doc comment — that OS
  // dialog can't be skipped or restyled, only handed off to promptly).
  installing,
  // Back in the app after [installing] without the update having been
  // applied: Android's dialog never appeared (the user was in another app
  // when the download finished) or was dismissed. The downloaded file is
  // kept; one tap asks for the confirmation again.
  awaitingConfirmation,
  // The app is running a build whose versionCode matches (or exceeds)
  // the update this controller was installing — see
  // checkPendingInstallCompleted()'s own doc comment for how that's
  // actually detected across the process restart Android's own install
  // always causes.
  installed,
  failed,
}

class ApkInstallState {
  const ApkInstallState({
    this.status = ApkInstallStatus.idle,
    this.progress = 0,
    this.filePath,
    this.versionName,
  });

  final ApkInstallStatus status;
  final double progress; // 0..1
  final String? filePath;

  /// Carried through from download to `installed`, purely for copy —
  /// "Обновление 1.2.0 установлено" reads better than a bare "Обновление
  /// установлено" with no confirmation of which version actually landed.
  final String? versionName;

  ApkInstallState copyWith({
    ApkInstallStatus? status,
    double? progress,
    String? filePath,
    String? versionName,
  }) =>
      ApkInstallState(
        status: status ?? this.status,
        progress: progress ?? this.progress,
        filePath: filePath ?? this.filePath,
        versionName: versionName ?? this.versionName,
      );
}

/// Downloads the APK named in an [UpdateInfo] to this app's own
/// external-files "updates" dir (via a Kotlin MethodChannel — see
/// UpdateInstaller.kt — rather than adding a path_provider-style plugin
/// just for one directory lookup) and hands it to the system installer.
/// Android-only: there's no equivalent self-update flow on iOS (App
/// Store-gated) or Windows (a future installer/updater is separate work).
final apkInstallControllerProvider =
    NotifierProvider<ApkInstallController, ApkInstallState>(
        ApkInstallController.new);

class ApkInstallController extends Notifier<ApkInstallState> {
  static const _channel = MethodChannel('app.wavebreak/updater');

  @override
  ApkInstallState build() {
    // Fire-and-forget on every controller creation (app cold start, or
    // this provider's first watch) — covers the case where Android
    // finished installing and killed/restarted the app process (the
    // normal outcome of an in-place APK replace) entirely on its own,
    // without this session ever seeing an `installing` state to resume
    // from. See checkPendingInstallCompleted()'s own doc comment.
    Future.microtask(checkPendingInstallCompleted);
    // Field report: download started, user switched to Telegram, came
    // back — "Installing update…" forever and no system prompt. While
    // Android's install dialog is up this app isn't in the foreground;
    // being back in front still `installing` means it never showed or was
    // dismissed. A short grace covers the native side showing a held-back
    // confirmation right on resume (MainActivity.onResume).
    if (!Platform.isAndroid) return const ApkInstallState();
    final lifecycle = AppLifecycleListener(onResume: () {
      // Back from "allow installs from this app": carry on with the
      // install right away instead of waiting for another tap.
      if (state.status == ApkInstallStatus.needsPermission) {
        unawaited(retryInstallIfAllowed());
        return;
      }
      if (state.status != ApkInstallStatus.installing) return;
      Future<void>.delayed(const Duration(milliseconds: 1500), () {
        if (state.status == ApkInstallStatus.installing &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed) {
          AppLogger.info('Update: back in the app without installing — '
              'offering the install prompt again');
          state = state.copyWith(status: ApkInstallStatus.awaitingConfirmation);
        }
      });
    });
    ref.onDispose(lifecycle.dispose);
    return const ApkInstallState();
  }

  Future<void> downloadAndInstall(UpdateInfo info) async {
    if (!Platform.isAndroid) return;
    if (state.status == ApkInstallStatus.downloading) return;

    state = state.copyWith(
      status: ApkInstallStatus.downloading,
      progress: 0,
      versionName: info.versionName,
    );
    try {
      final dir = await _channel.invokeMethod<String>('getApkStagingDir');
      if (dir == null) throw StateError('no staging dir');
      final path = '$dir/wavebreak-${info.versionCode}.apk';
      await _removeStaleDownloads(dir, info.versionCode);

      final abis = await _channel
              .invokeListMethod<String>('supportedAbis')
              .catchError((Object _) => null) ??
          const <String>[];
      final urls = info.downloadUrls(abis);
      AppLogger.info(
          'Update download: ${urls.first} (+${urls.length - 1} fallback)');
      var lastShown = -1.0;
      await ResumableDownloader().download(
        urls,
        path,
        onProgress: (received, total) {
          if (total <= 0) return;
          final progress = received / total;
          // Per-chunk callbacks are far more often than a progress bar
          // needs; rebuild on each tenth of a percent.
          if (progress - lastShown < 0.001 && progress < 1) return;
          lastShown = progress;
          state = state.copyWith(progress: progress);
        },
      );

      state = state.copyWith(progress: 1, filePath: path);
      // Auto-proceeds straight to the install prompt the instant the
      // download finishes — no separate "now tap Install" step for a
      // download that already succeeded; the only tap left is Android's
      // own unavoidable install-confirmation dialog.
      await _tryInstall(path, info.versionCode);
    } catch (error) {
      AppLogger.warn('Update download failed: $error');
      state = state.copyWith(status: ApkInstallStatus.failed);
    }
  }

  /// APKs and partial downloads of other versions: each is ~40-100 MB of the
  /// user's storage. A partial of THIS version stays, to be resumed.
  static Future<void> _removeStaleDownloads(String dir, int versionCode) async {
    try {
      final keep = 'wavebreak-$versionCode.apk';
      await for (final entry in Directory(dir).list()) {
        final name = entry.uri.pathSegments.last;
        if (entry is File &&
            name.startsWith('wavebreak-') &&
            !name.startsWith(keep)) {
          await entry.delete();
        }
      }
    } catch (_) {
      // Housekeeping only.
    }
  }

  Future<void> _tryInstall(String path, int versionCode) async {
    final canInstall =
        await _channel.invokeMethod<bool>('canRequestInstall') ?? false;
    if (!canInstall) {
      state = state.copyWith(
          status: ApkInstallStatus.needsPermission, filePath: path);
      return;
    }
    final started =
        await _channel.invokeMethod<bool>('installApk', {'path': path}) ??
            false;
    if (!started) {
      state = state.copyWith(status: ApkInstallStatus.failed);
      return;
    }
    // Survives the process restart Android's own install causes — see
    // checkPendingInstallCompleted()'s doc comment for why this can't
    // just live in Riverpod state.
    await PrefsStore.setInt(PrefsStore.pendingInstallVersionCode, versionCode);
    state = state.copyWith(status: ApkInstallStatus.installing);
  }

  /// Real constraint this works around: once Android's own install
  /// dialog actually completes an in-place APK replace, it kills this
  /// app's process as part of applying the new code — there is no way
  /// for THIS Dart isolate to ever observe "the install finished", because
  /// the isolate that fired the install request is gone by the time it
  /// has. What survives is disk (PrefsStore) and the fact that whatever
  /// process launches next — the OS's own "Open" button on its install-
  /// complete screen, or the user just reopening WAVEBREAK — is
  /// necessarily already running the new build if the install succeeded.
  /// So: stash the versionCode being installed before handing off (see
  /// `_tryInstall`), and on every fresh start of this controller, compare
  /// it against the version that's ACTUALLY running now. A match means
  /// the install this session started really did complete, even though
  /// no code from that session is still alive to have seen it happen —
  /// that's the "install finished, here's your confirmation" moment this
  /// state machine otherwise has no way to reach. Leaves `idle` alone if
  /// there was nothing pending, so this is always safe to call.
  Future<void> checkPendingInstallCompleted() async {
    final pending = PrefsStore.getInt(PrefsStore.pendingInstallVersionCode);
    if (pending == null) return;
    final info = await PackageInfo.fromPlatform();
    final currentCode = int.tryParse(info.buildNumber) ?? 0;
    if (currentCode >= pending) {
      await PrefsStore.setInt(PrefsStore.pendingInstallVersionCode, null);
      state = state.copyWith(
        status: ApkInstallStatus.installed,
        versionName: info.version,
      );
    }
    // Still below `pending`: either the OS dialog is still up, the user
    // backed out of it, or it failed — left alone rather than guessed at
    // here. If they're back in the app without having installed, they'll
    // see the ordinary `installing`/un-downloaded state next time they
    // open Settings > Updates and can just retry from there.
  }

  /// The update banner's single tap handler once a download is already
  /// staged (status is [ApkInstallStatus.needsPermission] or the initial
  /// attempt already failed the permission check): re-checks permission
  /// fresh rather than trusting the state from before the user
  /// (maybe) went to Settings — if it's granted now, installs the
  /// already-downloaded file straight away instead of re-downloading;
  /// otherwise sends them to Settings to grant it.
  Future<void> retryInstallOrOpenSettings() async {
    final path = state.filePath;
    if (path == null) return;
    final canInstall =
        await _channel.invokeMethod<bool>('canRequestInstall') ?? false;
    if (canInstall) {
      final code = int.tryParse(
              RegExp(r'wavebreak-(\d+)\.apk').firstMatch(path)?.group(1) ??
                  '') ??
          0;
      await _tryInstall(path, code);
    } else {
      await _channel.invokeMethod('openInstallUnknownAppsSettings');
    }
  }

  /// Installs the staged APK if installing is allowed now; otherwise
  /// leaves the "allow installs" state as it is.
  Future<void> retryInstallIfAllowed() async {
    final path = state.filePath;
    if (path == null) return;
    final canInstall =
        await _channel.invokeMethod<bool>('canRequestInstall') ?? false;
    if (canInstall && state.status == ApkInstallStatus.needsPermission) {
      await retryInstallOrOpenSettings();
    }
  }

  void reset() => state = const ApkInstallState();
}
