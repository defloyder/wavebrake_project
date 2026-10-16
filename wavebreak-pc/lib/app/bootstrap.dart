import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/logging/app_logger.dart';
import '../core/logging/file_log.dart';
import '../core/storage/prefs_store.dart';
import '../core/storage/secure_store.dart';
import '../services/pin/pin_service.dart';

late final SharedPreferences appPrefs;
late final FlutterSecureStorage appSecureStorage;

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.init();
  // One failing piece (a widget, an effect a weak or old phone can't run,
  // a platform call that doesn't exist there) must never take the whole
  // app down: log it, keep going. In release a widget that failed to
  // build leaves an empty space instead of the grey error box.
  FlutterError.onError = (details) {
    AppLogger.error('UI error: ${details.exceptionAsString()}');
    if (kDebugMode) FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.error('Uncaught error: $error');
    return true;
  };
  if (kReleaseMode) {
    ErrorWidget.builder = (_) => const SizedBox.shrink();
  }
  appPrefs = await _openPrefs();
  appSecureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  PrefsStore.init(appPrefs);
  SecureStore.init(appSecureStorage);
  // Old installs: copy the PIN out of Keystore before the lock screen
  // needs it (see PinService).
  unawaited(const PinService().warmUp());
}

/// The settings file, opened even when it's damaged. On Windows it is
/// %APPDATA%\…\shared_preferences.json; cut short or zeroed by a power cut
/// or a full disk, it stopped every start with "FormatException:
/// Unexpected character" — a user's app never opened again (15.10, logs
/// from 07.10 on). The damaged file is kept beside it and the app starts
/// with fresh settings: sign-in again, nothing else lost.
Future<SharedPreferences> _openPrefs() async {
  try {
    return await SharedPreferences.getInstance();
  } on FormatException catch (e) {
    final moved = await setAsideDamagedPrefs();
    FileLog.writeNow('settings file unreadable ($e) — set aside: $moved');
    return SharedPreferences.getInstance();
  }
}

/// Renames the settings file to `shared_preferences.damaged-<time>.json`
/// and returns the new path (null when there was none).
@visibleForTesting
Future<String?> setAsideDamagedPrefs({Directory? dir}) async {
  final base = dir ?? await getApplicationSupportDirectory();
  final file =
      File('${base.path}${Platform.pathSeparator}shared_preferences.json');
  if (!file.existsSync()) return null;
  final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
  final target =
      '${base.path}${Platform.pathSeparator}shared_preferences.damaged-$stamp.json';
  await file.rename(target);
  return target;
}
