import '../../core/env/app_env.dart';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// No Core endpoint for "what's the latest Android build" exists yet
/// (checked wavebreak-core's httpapi) — rather than add one just for
/// this, the app checks a small static JSON file the web team can update
/// on its own each time a new APK ships, no Core/database change needed:
/// `{"versionCode": 3, "versionName": "1.0.2", "url": "https://.../wavebreak-android.apk"}`
/// served alongside the APK itself from wavebreak-web/public/downloads/.
///
/// The Moscow mirror (dl.) first: a Russian IP that Russian carriers
/// don't throttle, carrying the same manifest; the site is the fallback.
const _versionCheckUrls = [
  'https://dl.wavebreak.com.tr/downloads/version.json',
  'https://wavebreak.com.tr/downloads/version.json',
];

/// Real-device complaint this fixes: the update badge/notification only
/// ever appeared right after a cold start (or a manual "Check for
/// updates" tap) — closing and reopening the app, or tapping the button,
/// was the only way to ever see a just-shipped release. [availableUpdateProvider]
/// re-checks on this interval for as long as anything is watching it
/// (app_shell.dart's badge watches it continuously while signed in), not
/// just once per provider creation. Field report: the badge still only
/// appeared after tapping "Check for updates" — a check at start that
/// failed (Russian mobile networks drop the app's direct requests) was
/// not repeated for 20 minutes, and returning to the app didn't check at
/// all. Now: at start, on every return to the app, every 10 minutes, and
/// one minute after a failed check.
const _pollInterval = Duration(minutes: 10);
const _retryAfterFailure = Duration(minutes: 1);
const _minGapOnResume = Duration(seconds: 30);

class UpdateInfo {
  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.url,
    this.mirrors = const [],
    this.abiUrls = const {},
  });

  final int versionCode;
  final String versionName;

  /// The universal APK — all older app versions read only this.
  final String url;

  /// The same universal APK elsewhere, tried in order after [url]
  /// (`"mirrors": [...]`).
  final List<String> mirrors;

  /// Per-architecture APKs, a third of the universal one's size:
  /// `"abis": {"arm64-v8a": ["https://...", ...], ...}`.
  final Map<String, List<String>> abiUrls;

  /// What to download, best first: the APK for the device's preferred
  /// architecture that the manifest has (from [supportedAbis], most
  /// preferred first), then the universal one and its mirrors.
  List<String> downloadUrls(List<String> supportedAbis) {
    final out = <String>[];
    for (final abi in supportedAbis) {
      final urls = abiUrls[abi];
      if (urls != null && urls.isNotEmpty) {
        out.addAll(urls);
        break;
      }
    }
    out
      ..add(url)
      ..addAll(mirrors);
    final seen = <String>{};
    return [
      for (final u in out)
        if (u.isNotEmpty && seen.add(u)) u
    ];
  }

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
        versionCode: (json['versionCode'] as num?)?.toInt() ?? 0,
        versionName: (json['versionName'] ?? '').toString(),
        url: (json['url'] ?? '').toString(),
        mirrors: _urlList(json['mirrors']),
        abiUrls: {
          if (json['abis'] is Map)
            for (final e in (json['abis'] as Map).entries)
              e.key.toString(): _urlList(e.value),
        },
      );

  static List<String> _urlList(Object? value) => [
        if (value is String && value.startsWith('https://')) value,
        if (value is List)
          for (final v in value)
            if (v is String && v.startsWith('https://')) v,
      ];
}

/// Bug 14: a one-step rollback the server offers for exactly one release.
/// Android never installs a lower versionCode over a higher one, so the
/// previous version is published rebuilt with a versionCode ABOVE the
/// release it rolls back from (N → N−1 built as N+1; the next regular
/// release is ≥ N+2). The manifest carries it as
/// `"rollback": {"fromVersionCode": N, "versionCode": N+1,
/// "versionName": "N−1", "url": "..."}` (N−1 as its name); it is offered only on exactly
/// build N. The rolled-back build is the old app, which has no rollback
/// of its own — so a second rollback is impossible until the next update.
/// Sign-in and settings survive (same package and signing key).
class RollbackInfo {
  const RollbackInfo({
    required this.fromVersionCode,
    required this.versionCode,
    required this.versionName,
    required this.url,
    this.mirrors = const [],
  });

  final int fromVersionCode;
  final int versionCode;
  final String versionName;
  final String url;
  final List<String> mirrors;

  /// What the installer downloads and installs.
  UpdateInfo get asUpdate => UpdateInfo(
      versionCode: versionCode,
      versionName: versionName,
      url: url,
      mirrors: mirrors);

  static RollbackInfo? fromJson(Object? json) {
    if (json is! Map) return null;
    final from = (json['fromVersionCode'] as num?)?.toInt() ?? 0;
    final code = (json['versionCode'] as num?)?.toInt() ?? 0;
    final url = (json['url'] ?? '').toString();
    if (from <= 0 || code <= from || url.isEmpty) return null;
    return RollbackInfo(
      fromVersionCode: from,
      versionCode: code,
      versionName: (json['versionName'] ?? '').toString(),
      url: url,
      mirrors: UpdateInfo._urlList(json['mirrors']),
    );
  }
}

Future<Map<String, dynamic>?> _fetchManifest() async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
  ));
  for (final url in _versionCheckUrls) {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        url,
        // Cache-busting: this is a small static file behind a CDN/browser
        // cache by default, which would otherwise keep serving a stale
        // "no update" answer well after a new APK actually shipped.
        queryParameters: {'t': DateTime.now().millisecondsSinceEpoch},
      );
      if (response.data != null) return response.data;
    } catch (_) {
      // Next source.
    }
  }
  return null;
}

/// The rollback this exact build may take, or null (none published, or
/// it's for another build).
final rollbackOfferProvider = FutureProvider<RollbackInfo?>((ref) async {
  final current = await PackageInfo.fromPlatform();
  final currentCode = int.tryParse(current.buildNumber) ?? 0;
  final data = await _fetchManifest();
  final rollback = RollbackInfo.fromJson(data?['rollback']);
  if (rollback == null || rollback.fromVersionCode != currentCode) return null;
  return rollback;
});

/// The rollback this build IS (it was installed through the manifest's
/// rollback), or null. Such a build carries a versionCode above the
/// release it rolled back from, so "no newer versionCode" doesn't mean
/// "latest version" there — the UI says it's the rolled-back one and that
/// the fix comes with the next update.
final installedRollbackProvider = FutureProvider<RollbackInfo?>((ref) async {
  final current = await PackageInfo.fromPlatform();
  final currentCode = int.tryParse(current.buildNumber) ?? 0;
  final data = await _fetchManifest();
  final rollback = RollbackInfo.fromJson(data?['rollback']);
  if (rollback == null || rollback.versionCode != currentCode) return null;
  return rollback;
});

/// One check: `checked` is false when the manifest couldn't be fetched
/// (so "no update" can't be concluded), `update` the newer release or null.
Future<({bool checked, UpdateInfo? update})> _checkOnce() async {
  final current = await PackageInfo.fromPlatform();
  final currentCode = int.tryParse(current.buildNumber) ?? 0;

  final data = await _fetchManifest();
  if (data == null) return (checked: false, update: null);
  final info = UpdateInfo.fromJson(data);
  if (info.versionCode <= currentCode || info.url.isEmpty) {
    return (checked: true, update: null);
  }
  return (checked: true, update: info);
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
final availableUpdateProvider = StreamProvider<UpdateInfo?>((ref) {
  // The TV build is its own package: the phone's APK is never offered.
  if (AppEnv.isTv) return Stream.value(null);
  final controller = StreamController<UpdateInfo?>();
  Timer? timer;
  var running = false;
  var emitted = false;
  DateTime? lastRun;

  Future<void> run() async {
    if (running || controller.isClosed) return;
    running = true;
    timer?.cancel();
    lastRun = DateTime.now();
    final result = await _checkOnce();
    running = false;
    if (controller.isClosed) return;
    // A failed check keeps whatever was shown (a found update must not
    // vanish because one request timed out); only the very first result
    // is emitted regardless, so the UI isn't left loading.
    if (result.checked || !emitted) {
      controller.add(result.update);
      emitted = true;
    }
    timer = Timer(result.checked ? _pollInterval : _retryAfterFailure, run);
  }

  // Back in the app: check again (timers don't run while it's in the
  // background for long on Android).
  final lifecycle = AppLifecycleListener(onResume: () {
    final last = lastRun;
    if (last == null || DateTime.now().difference(last) > _minGapOnResume) {
      unawaited(run());
    }
  });
  ref.onDispose(() {
    timer?.cancel();
    lifecycle.dispose();
    controller.close();
  });
  unawaited(run());
  return controller.stream;
});

const _updaterChannel = MethodChannel('app.wavebreak/updater');

/// Fires the native "update available" notification (branded icon/accent
/// — see UpdateAvailableNotifier.kt) — Android only, matching
/// [availableUpdateProvider]'s own callers, which already gate on
/// `Platform.isAndroid`. Best-effort: a notification failing to post
/// (permission revoked, channel blocked by the user, ...) must never be
/// treated as the update check itself having failed — the in-app badge
/// (app_shell.dart) already covers that case regardless.
Future<void> showUpdateAvailableNotification(String versionName,
    {int? versionCode}) async {
  try {
    await _updaterChannel.invokeMethod('showUpdateAvailableNotification', {
      'versionName': versionName,
      if (versionCode != null) 'versionCode': versionCode,
    });
  } catch (_) {}
}
