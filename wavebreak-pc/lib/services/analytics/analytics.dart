import '../../core/logging/app_logger.dart';

/// Allowed product analytics only. Never send credentials, destinations,
/// browsing history, or traffic.
class Analytics {
  const Analytics();

  void event(String name) {
    switch (name) {
      case 'app_open':
      case 'login_success':
      case 'connect_button_pressed':
      case 'connection_success':
      case 'connection_error':
      case 'subscription_screen_open':
        AppLogger.debug('event:$name');
        return;
      default:
        return;
    }
  }
}
