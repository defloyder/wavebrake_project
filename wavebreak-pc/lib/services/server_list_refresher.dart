import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/shared/data_providers.dart';
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

  void start() {
    _timer ??= Timer.periodic(serverListRefreshEvery, (_) => refresh());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> refresh() async {
    _ref.invalidate(locationsProvider);
    await _ref.read(customServersProvider.notifier).refreshAll();
  }
}

final serverListRefresherProvider = Provider<ServerListRefresher>((ref) {
  final refresher = ServerListRefresher(ref);
  ref.onDispose(refresher.stop);
  return refresher;
});
