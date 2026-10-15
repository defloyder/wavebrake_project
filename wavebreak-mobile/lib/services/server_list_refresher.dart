import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/shared/data_providers.dart';
import 'custom_servers/custom_link_sync.dart';
import 'custom_servers/custom_server_controller.dart';

/// How often the server lists are read again while the app runs.
const serverListRefreshEvery = Duration(minutes: 30);

/// Every 30 minutes (owner, 15.10: nodes added on the server or by a
/// provider showed up only after a restart): WAVEBREAK's locations from
/// Core and every third-party subscription are read again. The saved
/// lists stay on screen meanwhile and when a read fails.
class ServerListRefresher {
  ServerListRefresher(this._ref);

  final Ref _ref;
  Timer? _timer;
  Timer? _first;

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(serverListRefreshEvery, (_) => refresh());
    // Own links synced across devices, if on: once shortly after start.
    _first = Timer(const Duration(seconds: 5),
        () => unawaited(_ref.read(customLinkSyncProvider).sync()));
  }

  void stop() {
    _timer?.cancel();
    _first?.cancel();
    _timer = null;
    _first = null;
  }

  Future<void> refresh() async {
    _ref.invalidate(locationsProvider);
    await _ref.read(customServersProvider.notifier).refreshAll();
    await _ref.read(customLinkSyncProvider).sync();
  }
}

final serverListRefresherProvider = Provider<ServerListRefresher>((ref) {
  final refresher = ServerListRefresher(ref);
  ref.onDispose(refresher.stop);
  return refresher;
});
