import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

bool _isOffline(List<ConnectivityResult> results) {
  return results.isEmpty || results.every((r) => r == ConnectivityResult.none);
}

// Real-device bug this exists to fix: the offline/"showing saved data"
// banner would flash on for no reason a user could see — they were never
// actually offline. Root cause: this app runs a VPN, and connecting,
// reconnecting, or switching locations makes Android tear down and bring
// up network interfaces, which fires onConnectivityChanged with a
// momentary `none` result during the handover even though the device's
// real internet connection never actually dropped — confirmed as the
// mechanism, not a guess, by data_providers.dart's own `_canQueryCore`
// watching this exact stream (added to fix a DIFFERENT bug — the banner
// getting stuck showing stale data forever) and re-fetching on every
// emission, including these transient VPN-handover blips. A short
// debounce means only a connectivity change that actually holds for a
// beat is treated as real, filtering exactly this kind of momentary
// flicker while still catching a genuine, sustained loss of connection.
const _debounce = Duration(seconds: 3);

/// True when the device currently has no network connectivity at all.
/// Doesn't guarantee WAVEBREAK Core is reachable — just a quick, honest
/// signal for "you're offline" banners.
final isOfflineProvider = StreamProvider<bool>((ref) {
  final controller = StreamController<bool>();
  var current = false;
  Timer? debounceTimer;
  var haveEmittedInitial = false;

  void commit(bool value) {
    current = value;
    if (!controller.isClosed) controller.add(value);
  }

  void onValue(bool value) {
    if (!haveEmittedInitial) {
      haveEmittedInitial = true;
      commit(value);
      return;
    }
    if (value == current) {
      // Back to the value already committed — whatever prompted this
      // emission resolved on its own before the debounce fired, exactly
      // the "momentary blip" case this exists to ignore.
      debounceTimer?.cancel();
      return;
    }
    debounceTimer?.cancel();
    debounceTimer = Timer(_debounce, () => commit(value));
  }

  // Errors here (e.g. no platform implementation at all — every widget
  // test in this app's suite runs in an environment with no real
  // connectivity_plus channel behind it) must not become unhandled async
  // errors: Riverpod's own AsyncValue machinery already turns a thrown
  // error inside a plain `async*` StreamProvider body into a normal
  // AsyncError every consumer here already treats as "assume online" via
  // `.asData?.value ?? false` — this manual controller version needs to
  // replicate that explicitly instead of getting it for free.
  Connectivity()
      .checkConnectivity()
      .then((r) => onValue(_isOffline(r)))
      .catchError((_) {});
  final sub = Connectivity()
      .onConnectivityChanged
      .map(_isOffline)
      .listen(onValue, onError: (_) {});

  ref.onDispose(() {
    debounceTimer?.cancel();
    sub.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Which radio is actually carrying traffic right now — WiFi vs mobile —
/// so a "you're back online" indicator can show the connection the
/// device is really using instead of a generic signal glyph regardless
/// of which one it is. No debounce here (unlike [isOfflineProvider]):
/// this is cosmetic (which icon to draw), not a "should we trust this
/// long enough to show a banner" decision, so a brief flicker during a
/// genuine WiFi<->mobile handover just means the icon updates a beat
/// sooner, not a false alarm.
final connectivityTypeProvider = StreamProvider<ConnectivityResult>((ref) {
  ConnectivityResult pick(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi)) {
      return ConnectivityResult.wifi;
    }
    if (results.contains(ConnectivityResult.ethernet)) {
      return ConnectivityResult.ethernet;
    }
    if (results.contains(ConnectivityResult.mobile)) {
      return ConnectivityResult.mobile;
    }
    return results.isNotEmpty ? results.first : ConnectivityResult.none;
  }

  final controller = StreamController<ConnectivityResult>();
  Connectivity()
      .checkConnectivity()
      .then((r) => controller.add(pick(r)))
      .catchError((_) {});
  final sub = Connectivity()
      .onConnectivityChanged
      .map(pick)
      .listen(controller.add, onError: (_) {});
  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });
  return controller.stream;
});
