import 'package:flutter/foundation.dart';

import '../env/app_env.dart';

/// Application logger. Never logs passwords, JWTs, refresh tokens, or
/// connection secrets.
class AppLogger {
  AppLogger._();

  static bool _verbose = true;

  static void init() {
    _verbose = !AppEnv.isProduction;
  }

  static void debug(String message) {
    if (_verbose) {
      debugPrint('[WB] $message');
    }
  }

  static void info(String message) {
    debugPrint('[WB] $message');
  }

  static void warn(String message) {
    debugPrint('[WB][warn] $message');
  }

  static void error(String message) {
    debugPrint('[WB][error] $message');
  }
}
