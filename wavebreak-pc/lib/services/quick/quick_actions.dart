import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/auth/session_controller.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/logging/app_logger.dart';
import '../../core/theme/flag_colors.dart';
import '../../features/home/location_bar.dart';
import '../../features/shared/data_providers.dart';
import '../core_api/models.dart';
import '../custom_servers/custom_server_controller.dart';
import '../vpn/connection_manager.dart';

/// Quick actions from outside the app window (Android): the Quick Settings
/// tile turns the VPN on and off (see QuickTileService.kt / QuickActions.kt).
/// Native hands each action over "app.wavebreak/quick"; it runs here
/// through the same ConnectionManager calls as the home screen. Also keeps
/// a small snapshot file (the tile's subtitle texts) the tile reads
/// without waiting for Flutter.
///
/// Changing the server or protocol is only in the app (home header and
/// the Servers tab) — the notification buttons and the picker over other
/// apps were removed (owner: too many places to switch).
final quickActionsProvider = Provider<QuickActions>((ref) {
  final quick = QuickActions(ref);
  ref.listen(connectionManagerProvider, (prev, next) {
    if (prev?.status != next.status || prev?.location.id != next.location.id) {
      quick.publish();
      quick._notifyStateChanged();
    }
  });
  ref.listen(stringsProvider, (_, __) => quick.publish());
  return quick;
});

class QuickActions {
  QuickActions(this._ref);

  final Ref _ref;
  static const _channel = MethodChannel('app.wavebreak/quick');
  static const _engine = MethodChannel('app.wavebreak/vpn_engine');
  bool _started = false;

  /// Called once from the app root; then native may deliver actions.
  void start() {
    if (_started || !Platform.isAndroid) return;
    _started = true;
    _channel.setMethodCallHandler(_handle);
    publish();
    _channel.invokeMethod('ready').catchError((Object _) => null);
  }

  void _notifyStateChanged() {
    if (!_started) return;
    _channel.invokeMethod('stateChanged').catchError((Object _) => null);
  }

  Future<Object?> _handle(MethodCall call) async {
    if (call.method != 'action') throw MissingPluginException();
    final args = Map<String, Object?>.from(call.arguments as Map);
    final type = args['type'] as String?;
    final s = _ref.read(stringsProvider);
    final openApp = {'result': 'open_app', 'message': s.quickOpenApp};
    AppLogger.info('Quick action: $type');

    // A cold process runs main() headless: wait for the saved session.
    final phase = await _settledPhase();
    if (phase != SessionPhase.authenticated && phase != SessionPhase.guest) {
      return openApp;
    }
    final manager = _ref.read(connectionManagerProvider.notifier);
    final locations = await _locations();
    if (locations.isNotEmpty) manager.hydrateLocations(locations);
    final state = _ref.read(connectionManagerProvider);
    final active = state.status != ConnectionStatus.idle &&
        state.status != ConnectionStatus.error;
    final canConnect = await _canConnect();

    Future<bool> mayStart(LocationItem target) async {
      if (!target.isCustom && !canConnect) return false;
      return _hasVpnConsent();
    }

    switch (type) {
      // The tile decides from the system's real VPN state (not this
      // engine's, which can lag behind after a restart) and says which.
      case 'on':
        await manager.reconcileWithSystem();
        final now = _ref.read(connectionManagerProvider);
        if (now.status == ConnectionStatus.connected || now.isBusy) break;
        if (!await mayStart(now.location)) return openApp;
        unawaited(manager.connect(subscriptionActive: canConnect));
      case 'off':
        await manager.reconcileWithSystem();
        final now = _ref.read(connectionManagerProvider);
        if (now.status == ConnectionStatus.requestingProfile ||
            now.status == ConnectionStatus.connecting) {
          await manager.cancelConnect();
        } else if (now.status != ConnectionStatus.idle &&
            now.status != ConnectionStatus.disconnecting) {
          unawaited(manager.disconnect());
        }
      case 'toggle':
        if (!active && !await mayStart(state.location)) return openApp;
        unawaited(manager.toggle(subscriptionActive: canConnect));
    }
    return {'result': 'ok'};
  }

  Future<SessionPhase> _settledPhase() async {
    for (var i = 0; i < 80; i++) {
      final phase = _ref.read(sessionControllerProvider).phase;
      if (phase != SessionPhase.booting) return phase;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return _ref.read(sessionControllerProvider).phase;
  }

  Future<bool> _canConnect() async {
    try {
      await _ref
          .read(subscriptionProvider.future)
          .timeout(const Duration(seconds: 6));
    } catch (_) {}
    return _ref.read(canConnectProvider);
  }

  Future<bool> _hasVpnConsent() async {
    try {
      return await _engine.invokeMethod<bool>('hasPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<List<LocationItem>> _locations() async {
    var core = const <LocationItem>[];
    try {
      core = await _ref
          .read(locationsProvider.future)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      core = _ref.read(locationsProvider).valueOrNull ?? const [];
    }
    final custom =
        _ref.read(customServersProvider).expand((g) => g.servers).toList();
    return [
      for (final l in [...core, ...custom])
        if (!l.isAuto && l.available) l,
    ];
  }

  /// Writes the snapshot the tile reads (its subtitle texts).
  Future<void> publish() async {
    if (!Platform.isAndroid) return;
    try {
      final s = _ref.read(stringsProvider);
      final current = _ref.read(connectionManagerProvider).location;
      final (curPlace, _) = splitPlaceAndProtocol(current.city);
      final snapshot = {
        'tileOff': s.notConnected,
        'tileBusy': s.connecting,
        'tileSubtitle': [
          if (current.countryCode.isNotEmpty) flagEmoji(current.countryCode),
          if (curPlace.isNotEmpty) curPlace else current.country,
        ].join(' '),
      };
      final dir = await getApplicationSupportDirectory();
      await File('${dir.path}/quick_locations.json')
          .writeAsString(jsonEncode(snapshot));
    } catch (e) {
      AppLogger.warn('Quick snapshot failed: $e');
    }
  }
}
