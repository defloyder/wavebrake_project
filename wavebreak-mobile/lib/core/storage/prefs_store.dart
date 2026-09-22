import 'package:shared_preferences/shared_preferences.dart';

class PrefsStore {
  PrefsStore._();

  static late SharedPreferences _prefs;

  static const biometricEnabled = 'biometric_enabled';
  static const requireBiometricOnOpen = 'require_biometric_on_open';
  static const pinEnabled = 'pin_enabled';
  static const appLockEnabled = 'app_lock_enabled';
  static const guestMode = 'guest_mode';
  static const onboardingChoiceMade = 'onboarding_choice_made';
  static const lastLocationId = 'last_location_id';
  static const autoConnect = 'auto_connect';
  static const autoConnectOnLaunch = 'auto_connect_on_launch';
  static const autoConnectUntrustedWifi = 'auto_connect_untrusted_wifi';
  static const notifyConnection = 'notify_connection';
  static const notifySubscription = 'notify_subscription';
  static const biometricPromptShown = 'biometric_prompt_shown';
  static const language = 'language';
  static const customServers = 'custom_servers';
  static const accentOverride = 'accent_override';
  static const textScale = 'text_scale';
  static const reduceMotion = 'reduce_motion';

  // Last-known-good snapshots of Core data, used to render something
  // real instead of a blank/error screen when a refresh fails offline —
  // see features/shared/data_providers.dart. Each is a plain JSON blob
  // matching that model's own fromJson/toJson shape, not a Core response
  // verbatim.
  static const cachedSubscription = 'cache_subscription_v1';
  static const cachedLocations = 'cache_locations_v1';
  static const cachedDevices = 'cache_devices_v1';
  static const cachedPlans = 'cache_plans_v1';
  static const cachedUsage = 'cache_usage_v1';

  static void init(SharedPreferences prefs) {
    _prefs = prefs;
  }

  static bool getBool(String key, {bool fallback = false}) =>
      _prefs.getBool(key) ?? fallback;

  static Future<void> setBool(String key, bool value) =>
      _prefs.setBool(key, value);

  static String? getString(String key) => _prefs.getString(key);

  static Future<void> setString(String key, String? value) async {
    if (value == null) {
      await _prefs.remove(key);
      return;
    }
    await _prefs.setString(key, value);
  }

  static double? getDouble(String key) => _prefs.getDouble(key);

  static Future<void> setDouble(String key, double value) =>
      _prefs.setDouble(key, value);

  static int? getInt(String key) => _prefs.getInt(key);

  static Future<void> setInt(String key, int? value) async {
    if (value == null) {
      await _prefs.remove(key);
      return;
    }
    await _prefs.setInt(key, value);
  }
}
