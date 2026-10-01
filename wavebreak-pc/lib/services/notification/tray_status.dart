import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';

/// One entry of the tray icon's right-click menu. [id] > 0 is what
/// [TrayStatus.showMenu] returns when it's picked; [children] makes it a
/// submenu.
class TrayMenuEntry {
  const TrayMenuEntry(this.label,
      {this.id = 0,
      this.checked = false,
      this.enabled = true,
      this.children = const []})
      : separator = false;
  const TrayMenuEntry.separator()
      : label = '',
        id = 0,
        checked = false,
        enabled = false,
        children = const [],
        separator = true;

  final String label;
  final int id;
  final bool checked;
  final bool enabled;
  final bool separator;
  final List<TrayMenuEntry> children;

  Map<String, Object> toMap() => {
        'label': label,
        'id': id,
        'checked': checked,
        'enabled': enabled,
        'separator': separator,
        if (children.isNotEmpty)
          'children': [for (final c in children) c.toMap()],
      };
}

/// The app's Windows notification-area icon (windows/runner/tray_icon.cpp):
/// coloured with a green dot while connected, grey otherwise, a tooltip
/// with the state, and a right-click menu Dart builds on demand.
class TrayStatus {
  const TrayStatus();

  static const _channel = MethodChannel('wavebreak/tray');

  /// Called on a right click on the icon — build and [showMenu] the menu.
  static void onMenuRequested(Future<void> Function() handler) {
    if (!Platform.isWindows) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'menuRequested') await handler();
      return null;
    });
  }

  Future<void> update({required bool connected, required String tooltip}) =>
      _invoke('update', {'connected': connected, 'tooltip': tooltip});

  /// Shows [entries] at the cursor; the picked id, or 0 if dismissed.
  Future<int> showMenu(List<TrayMenuEntry> entries) async =>
      await _invoke<int>('showMenu', [for (final e in entries) e.toMap()]) ??
      0;

  Future<void> showWindow() => _invoke('show');

  /// Removes the icon and closes the app window (disconnect first).
  Future<void> quit() => _invoke('quit');

  Future<T?> _invoke<T>(String method, [Object? args]) async {
    if (!Platform.isWindows) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } catch (e) {
      // No runner channel (tests, an old runner) — the icon is cosmetic.
      AppLogger.debug('Tray $method skipped: $e');
      return null;
    }
  }
}
