import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'update_service.dart';

enum ApkInstallStatus {
  idle,
  downloading,
  needsPermission,
  readyToInstall,
  failed
}

class ApkInstallState {
  const ApkInstallState({
    this.status = ApkInstallStatus.idle,
    this.progress = 0,
    this.filePath,
  });

  final ApkInstallStatus status;
  final double progress; // 0..1
  final String? filePath;

  ApkInstallState copyWith({
    ApkInstallStatus? status,
    double? progress,
    String? filePath,
  }) =>
      ApkInstallState(
        status: status ?? this.status,
        progress: progress ?? this.progress,
        filePath: filePath ?? this.filePath,
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
  ApkInstallState build() => const ApkInstallState();

  Future<void> downloadAndInstall(UpdateInfo info) async {
    if (!Platform.isAndroid) return;
    if (state.status == ApkInstallStatus.downloading) return;

    state = state.copyWith(status: ApkInstallStatus.downloading, progress: 0);
    try {
      final dir = await _channel.invokeMethod<String>('getApkStagingDir');
      if (dir == null) throw StateError('no staging dir');
      final path = '$dir/wavebreak-${info.versionCode}.apk';

      final dio = Dio();
      await dio.download(
        info.url,
        path,
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          // A handful of updates a second is plenty for a progress bar —
          // Dio's own callback already fires far more often than that for
          // a fast connection, so this isn't adding throttling that isn't
          // already implicitly needed, just not fighting it either.
          state = state.copyWith(progress: received / total);
        },
      );

      state = state.copyWith(progress: 1, filePath: path);
      await _tryInstall(path);
    } catch (_) {
      state = state.copyWith(status: ApkInstallStatus.failed);
    }
  }

  Future<void> _tryInstall(String path) async {
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
    state = state.copyWith(
      status:
          started ? ApkInstallStatus.readyToInstall : ApkInstallStatus.failed,
    );
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
      await _tryInstall(path);
    } else {
      await _channel.invokeMethod('openInstallUnknownAppsSettings');
    }
  }

  void reset() => state = const ApkInstallState();
}
