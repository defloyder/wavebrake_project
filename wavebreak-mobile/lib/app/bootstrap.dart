import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/logging/app_logger.dart';
import '../core/storage/prefs_store.dart';
import '../core/storage/secure_store.dart';

late final SharedPreferences appPrefs;
late final FlutterSecureStorage appSecureStorage;

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.init();
  appPrefs = await SharedPreferences.getInstance();
  appSecureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  PrefsStore.init(appPrefs);
  SecureStore.init(appSecureStorage);
}
