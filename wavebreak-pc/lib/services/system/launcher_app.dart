import 'dart:io';

import 'package:dio/dio.dart';

/// The WAVEBREAK Launcher (Windows): every WAVEBREAK program for this PC in
/// one window (owner, 13.10: "a way to get to the launcher from the
/// app"). Kept next to the launcher's own data, refreshed from the site
/// when it is a few days old, then started on its own.
class LauncherApp {
  const LauncherApp();

  static bool get available => Platform.isWindows;

  static const _url =
      'https://wavebreak.com.tr/downloads/WAVEBREAK-Launcher.exe';
  static const _maxAge = Duration(days: 3);

  File get _exe {
    final base =
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
    return File('$base/WAVEBREAK Launcher/WAVEBREAK-Launcher.exe');
  }

  /// Downloads the launcher if it is missing or old, then starts it.
  /// Throws when there is nothing to start.
  Future<void> open() async {
    final exe = _exe;
    final fresh = exe.existsSync() &&
        DateTime.now().difference(exe.lastModifiedSync()) < _maxAge;
    if (!fresh) {
      try {
        await _download(exe);
      } catch (_) {
        // An older copy still does the job.
        if (!exe.existsSync()) rethrow;
      }
    }
    await Process.start(exe.path, const [],
        workingDirectory: exe.parent.path, mode: ProcessStartMode.detached);
  }

  Future<void> _download(File exe) async {
    exe.parent.createSync(recursive: true);
    final part = File('${exe.path}.part');
    await Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
    )).download(_url, part.path);
    if (part.lengthSync() < 1024 * 1024) {
      part.deleteSync();
      throw const FileSystemException('launcher download incomplete');
    }
    if (exe.existsSync()) exe.deleteSync();
    part.renameSync(exe.path);
  }
}
