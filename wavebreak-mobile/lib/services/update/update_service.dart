import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// No Core endpoint for "what's the latest Android build" exists yet
/// (checked wavebreak-core's httpapi) — rather than add one just for
/// this, the app checks a small static JSON file the web team can update
/// on its own each time a new APK ships, no Core/database change needed:
/// `{"versionCode": 3, "versionName": "1.0.2", "url": "https://.../wavebreak-android.apk"}`
/// served alongside the APK itself from wavebreak-web/public/downloads/.
const _versionCheckUrl = 'https://wavebreak.com.tr/downloads/version.json';

/// Real-device complaint this fixes: the update badge/notification only
/// ever appeared right after a cold start (or a manual "Check for
/// updates" tap) — closing and reopening the app, or tapping the button,
/// was the only way to ever see a just-shipped release. [availableUpdateProvider]
/// re-checks on this interval for as long as anything is watching it
/// (app_shell.dart's badge watches it continuously while signed in, so
/// this effectively means "every 20 minutes the app is open"), not just
/// once per provider creation.
const _pollInterval = Duration(minutes: 20);

class UpdateInfo {
  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.url,
  });

  final int versionCode;
  final String versionName;
  final String url;

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
        versionCode: (json['versionCode'] as num?)?.toInt() ?? 0,
        versionName: (json['versionName'] ?? '').toString(),
        url: (json['url'] ?? '').toString(),
      );
}

Future<UpdateInfo?> _checkOnce() async {
  final current = await PackageInfo.fromPlatform();
  final currentCode = int.tryParse(current.buildNumber) ?? 0;

  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
  ));
  final Response<Map<String, dynamic>> response;
  try {
    response = await dio.get<Map<String, dynamic>>(
      _versionCheckUrl,
      // Cache-busting: this is a small static file behind a CDN/browser
      // cache by default, which would otherwise keep serving a stale
      // "no update" answer well after a new APK actually shipped.
      queryParameters: {'t': DateTime.now().millisecondsSinceEpoch},
    );
  } catch (_) {
    return null;
  }

  final data = response.data;
  if (data == null) return null;
  final info = UpdateInfo.fromJson(data);
  if (info.versionCode <= currentCode || info.url.isEmpty) return null;
  return info;
}

/// Null when no update is available (either the check failed, or the
/// server's versionCode isn't newer than this install's own) — the UI
/// treats "checked, nothing to show" and "haven't checked yet" the same
/// way (no banner), so there's no separate loading/error state to render.
///
/// StreamProvider, not FutureProvider — deliberately, so it keeps
/// re-checking on [_pollInterval] for as long as something is watching it
/// instead of running exactly once. See this file's own doc comment on
/// the real-device "have to close and reopen the app" complaint this
/// fixes. `ref.invalidate(availableUpdateProvider)` (updates_screen.dart's
/// manual "Check now" button) still works exactly as before — invalidating
/// a StreamProvider restarts its whole async* body, which re-yields
/// immediately and resumes the same polling cadence from there.
final availableUpdateProvider = StreamProvider<UpdateInfo?>((ref) async* {
  yield await _checkOnce();
  yield* Stream.periodic(_pollInterval).asyncMap((_) => _checkOnce());
});

const _updaterChannel = MethodChannel('app.wavebreak/updater');

/// Fires the native "update available" notification (branded icon/accent
/// — see UpdateAvailableNotifier.kt) — Android only, matching
/// [availableUpdateProvider]'s own callers, which already gate on
/// `Platform.isAndroid`. Best-effort: a notification failing to post
/// (permission revoked, channel blocked by the user, ...) must never be
/// treated as the update check itself having failed — the in-app badge
/// (app_shell.dart) already covers that case regardless.
Future<void> showUpdateAvailableNotification(String versionName) async {
  try {
    await _updaterChannel.invokeMethod('showUpdateAvailableNotification', {
      'versionName': versionName,
    });
  } catch (_) {}
}
