import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// No Core endpoint for "what's the latest build" exists yet (checked
/// wavebreak-core's httpapi) — rather than add one just for this, the
/// app checks a small static JSON file the web team can update on its
/// own each time a new build ships, no Core/database change needed:
/// `{"versionCode": 3, "versionName": "1.0.2", "url": "https://.../wavebreak-android.apk"}`
/// served alongside the build itself from wavebreak-web/public/downloads/.
///
/// A separate file per platform (not one shared version.json with two
/// url fields) — Android's `versionCode` is a real Android build-number
/// concept tied to the Play/APK versioning contract; Windows has no such
/// thing, `versionCode` here is just this app's own pubspec build number
/// (see PackageInfo.buildNumber below) compared the same way. Keeping
/// them in separate files means an Android release and a Windows
/// release can ship independently without one platform's version bump
/// looking like an available update to the other.
String get _versionCheckUrl => Platform.isWindows
    ? 'https://wavebreak.com.tr/downloads/version-windows.json'
    : 'https://wavebreak.com.tr/downloads/version.json';

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

/// Null when no update is available (either the check failed, or the
/// server's versionCode isn't newer than this install's own) — the UI
/// treats "checked, nothing to show" and "haven't checked yet" the same
/// way (no banner), so there's no separate loading/error state to render.
final availableUpdateProvider = FutureProvider<UpdateInfo?>((ref) async {
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
});
