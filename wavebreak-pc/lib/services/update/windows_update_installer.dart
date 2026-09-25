import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'update_service.dart';

enum WindowsUpdateStatus { idle, downloading, readyToInstall, failed }

class WindowsUpdateState {
  const WindowsUpdateState({
    this.status = WindowsUpdateStatus.idle,
    this.progress = 0,
    this.installerPath,
  });

  final WindowsUpdateStatus status;
  final double progress; // 0..1
  final String? installerPath;

  WindowsUpdateState copyWith({
    WindowsUpdateStatus? status,
    double? progress,
    String? installerPath,
  }) =>
      WindowsUpdateState(
        status: status ?? this.status,
        progress: progress ?? this.progress,
        installerPath: installerPath ?? this.installerPath,
      );
}

/// PC equivalent of mobile's ApkInstallController — same shape
/// (download with progress, then hand off to the platform's own install
/// mechanism), adapted for how a Windows desktop app actually
/// self-updates: there's no OS-mediated "install this package" intent
/// the way Android has. The standard pattern (and the one used here) is
/// download the new Inno Setup installer, launch it detached, and exit
/// this process — the installer overwrites the current install in place
/// once this process has released its file locks, then optionally
/// relaunches the app itself (see wavebreak.iss's own [Run] section,
/// which already offers "launch after install" on a normal manual run;
/// a self-update launch skips that prompt and the installer just runs
/// with its own default UI).
///
/// windows/installer/wavebreak.iss produces the installer this expects
/// to receive a URL to; wiring an actual hosted version-windows.json +
/// uploaded installer is a deployment step, not something this client
/// code does on its own — see update_service.dart's own doc comment on
/// the version-check URL this reads from.
final windowsUpdateControllerProvider =
    NotifierProvider<WindowsUpdateController, WindowsUpdateState>(
        WindowsUpdateController.new);

class WindowsUpdateController extends Notifier<WindowsUpdateState> {
  @override
  WindowsUpdateState build() => const WindowsUpdateState();

  Future<void> downloadAndInstall(UpdateInfo info) async {
    if (!Platform.isWindows) return;
    if (state.status == WindowsUpdateStatus.downloading) return;

    state =
        state.copyWith(status: WindowsUpdateStatus.downloading, progress: 0);
    try {
      // System temp, not the install directory itself — the installer
      // needs to be able to overwrite files this same process has open
      // (its own exe/DLLs), which only works from outside {app}.
      final path =
          '${Directory.systemTemp.path}\\WaveBreak-Setup-${info.versionName}.exe';
      final dio = Dio();
      await dio.download(
        info.url,
        path,
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          state = state.copyWith(progress: received / total);
        },
      );
      state = state.copyWith(
        status: WindowsUpdateStatus.readyToInstall,
        progress: 1,
        installerPath: path,
      );
    } catch (_) {
      state = state.copyWith(status: WindowsUpdateStatus.failed);
    }
  }

  /// Launches the downloaded installer and exits this process — see this
  /// class's own doc comment for why that's the right sequence on
  /// Windows. `detached` so the installer survives this process exiting
  /// (a normal child process would be at risk of being torn down along
  /// with its parent depending on how the OS/job-object hierarchy is set
  /// up).
  ///
  /// /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-: this is an update the
  /// user already asked for from inside a running WAVEBREAK (the update
  /// screen's own progress bar was the "something happened" signal, not
  /// the installer's wizard) — re-clicking through the same directory
  /// picker, "create desktop shortcut" checkbox and finish page it was
  /// installed with the first time read as a full reinstall rather than
  /// an update, which is exactly the complaint this fixes. wavebreak.iss's
  /// own [Run] entry (deliberately without `skipifsilent`) still relaunches
  /// the app once this finishes, so the whole flow is: download, install,
  /// relaunch, no clicks — the same shape Chrome/Discord/Telegram's own
  /// updaters use. A genuine first-time install downloaded straight from
  /// the website still runs the installer directly (never through this
  /// class) and keeps its normal wizard.
  Future<void> runInstallerAndExit() async {
    final path = state.installerPath;
    if (path == null) return;
    try {
      await Process.start(
        path,
        ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-'],
        mode: ProcessStartMode.detached,
      );
    } catch (_) {
      state = state.copyWith(status: WindowsUpdateStatus.failed);
      return;
    }
    exit(0);
  }

  void reset() => state = const WindowsUpdateState();
}
