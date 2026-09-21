import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

bool _isOffline(List<ConnectivityResult> results) {
  return results.isEmpty || results.every((r) => r == ConnectivityResult.none);
}

/// True when the device currently has no network connectivity at all.
/// Doesn't guarantee WAVEBREAK Core is reachable — just a quick, honest
/// signal for "you're offline" banners.
final isOfflineProvider = StreamProvider<bool>((ref) async* {
  yield _isOffline(await Connectivity().checkConnectivity());
  yield* Connectivity().onConnectivityChanged.map(_isOffline);
});
