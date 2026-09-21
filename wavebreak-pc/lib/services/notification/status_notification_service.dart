import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';

/// Talks to a small native foreground-service notification (Android for
/// now) that mirrors the current connection state in the system's
/// notification shade / status bar — the persistent "floating bar" a VPN
/// app is expected to show while connected. Kept in sync from Dart until a
/// real native VpnService tunnel exists to show one automatically (see
/// PlatformVpnAdapter's doc comment on the still-missing native tunnel).
class StatusNotificationService {
  const StatusNotificationService();

  static const _channel = MethodChannel('app.wavebreak/status_notification');

  Future<void> show({required String title, required String text, bool ongoing = true}) async {
    try {
      await _channel.invokeMethod<void>('show', {
        'title': title,
        'text': text,
        'ongoing': ongoing,
      });
    } catch (e) {
      // No-op where the native side isn't wired up (iOS/desktop/web).
      AppLogger.warn('status notification show failed: $e');
    }
  }

  Future<void> hide() async {
    try {
      await _channel.invokeMethod<void>('hide');
    } catch (e) {
      AppLogger.warn('status notification hide failed: $e');
    }
  }
}
