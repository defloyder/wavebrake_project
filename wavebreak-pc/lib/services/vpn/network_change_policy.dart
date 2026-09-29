import 'package:connectivity_plus/connectivity_plus.dart';

/// A loss of the network shorter than this, coming back as the same
/// networks, is a blip: the tunnel's connections survive it, and reloading
/// sing-box would itself be the visible drop. Same value as Android's
/// NETWORK_BLIP_MS.
const networkBlip = Duration(seconds: 3);

/// The real networks (Wi-Fi/Ethernet/mobile) in a connectivity event —
/// our own TUN adapter and other VPNs are left out.
Set<ConnectivityResult> physicalNetworks(List<ConnectivityResult> results) =>
    results
        .where((r) =>
            r == ConnectivityResult.wifi ||
            r == ConnectivityResult.ethernet ||
            r == ConnectivityResult.mobile)
        .toSet();

/// Whether a settled connectivity event should reload a working tunnel.
///
/// [previous] is the set of real networks before (null: not known yet),
/// [current] the set now (never empty — a fully offline event is not a
/// reason by itself), [offlineFor] how long the machine had no real
/// network right before this event (null: it never lost it).
bool networkChangeNeedsRecovery({
  required Set<ConnectivityResult>? previous,
  required Set<ConnectivityResult> current,
  Duration? offlineFor,
}) {
  if (previous == null || current.isEmpty) return false;
  final same =
      current.length == previous.length && current.containsAll(previous);
  if (!same) return true;
  return offlineFor != null && offlineFor >= networkBlip;
}
