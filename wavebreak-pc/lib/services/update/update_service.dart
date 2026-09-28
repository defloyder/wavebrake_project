import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
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
/// The Moscow mirror (dl.) first: a Russian IP that Russian carriers
/// don't throttle, carrying the same manifest; the site is the fallbacks.
List<String> get _versionCheckUrls {
  final name = Platform.isWindows ? 'version-windows.json' : 'version.json';
  return [
    'https://dl.wavebreak.com.tr/downloads/$name',
    'https://wavebreak.com.tr/downloads/$name',
  ];
}

/// Same checking cadence as wavebreak-mobile's update_service.dart — see
/// its doc comment: at start, on every return to the app, every 10 minutes,
/// and one minute after a failed check.
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
/// The manifest carries `"rollback": {"fromVersionCode": N,
/// "versionCode": N+1, "versionName": "...", "url": "..."}`: the previous
/// version's installer, built with a build number ABOVE the release it
/// rolls back from — so the older app, once reinstalled, doesn't at once
/// offer to update back to N (the next regular release is ≥ N+2). It is
/// offered only on exactly build N; the reinstalled older app has no
/// rollback of its own, so a second rollback is impossible until the next
/// update. Settings and sign-in live outside the install directory.
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
