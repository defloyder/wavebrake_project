import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/logging/app_logger.dart';
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
  appPrefs = await SharedPreferences.getInstance();
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
