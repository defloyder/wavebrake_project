import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// See the Kotlin side's own BatteryOptimization.kt for the full
/// rationale — Doze/App Standby can defer this app's background work even
/// with the VpnService foreground notification's partial exemption, and
/// this is the standard (non-silent, user-approved) way to ask for the
/// rest. Android-only; iOS/Windows have no equivalent concept.
class BatteryOptimizationService {
  const BatteryOptimizationService();

  static const _channel = MethodChannel('app.wavebreak/vpn_state');

  Future<bool> isExempt() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel
              .invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Shows Android's own per-app exemption dialog. Fire-and-forget: the
  /// result only ever reaches this app again via a fresh [isExempt] check
  /// next time it's asked, not a callback — Android gives no other signal
  /// for "the user approved/declined this."
  Future<void> requestExemption() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {}
  }

  /// Xiaomi / Redmi / POCO: MIUI and HyperOS freeze a background app's
  /// network — the VPN engine's too — beyond Android's own exemption,
  /// until its battery saver is "No restrictions" and Autostart is on
  /// (owner, 12.10: the VPN stopped passing traffic until the app was
  /// opened). See OemBackground.kt.
  Future<bool> isXiaomi() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isXiaomi') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// The app's battery saver screen (Xiaomi), else its system settings.
  Future<void> openBackgroundSettings() => _open('openBackgroundSettings');

  /// The Autostart list (Xiaomi), else the app's system settings.
  Future<void> openAutostartSettings() => _open('openAutostartSettings');

  Future<void> _open(String method) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod(method);
    } catch (_) {}
  }
}
