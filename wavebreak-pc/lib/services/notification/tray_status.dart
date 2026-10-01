import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';

/// Mirrors the VPN state into the app's Windows notification-area icon
/// (windows/runner/tray_icon.cpp): coloured with a green dot while
/// connected, grey otherwise, with [tooltip] on hover — so the state is
/// visible under "show hidden icons" without opening the window.
class TrayStatus {
  const TrayStatus();

  static const _channel = MethodChannel('wavebreak/tray');

  Future<void> update({required bool connected, required String tooltip}) async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<void>(
          'update', {'connected': connected, 'tooltip': tooltip});
    } catch (e) {
      // No runner channel (tests, an old runner) — the icon is cosmetic.
      AppLogger.debug('Tray update skipped: $e');
    }
  }
}
