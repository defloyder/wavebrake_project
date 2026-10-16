import '../../features/home/location_bar.dart' show splitPlaceAndProtocol;
import '../core_api/models.dart';

/// The next of the same country's WAVEBREAK locations to try after
/// [current] passed no traffic — the one after it in [own]'s order
/// (wrapping around), skipping unavailable ones and those already [tried].
/// Null when every protocol of that country has been tried: another
/// country is the user's call, the app never picks one for them.
///
/// Only ever used on the user's tap ("Try another protocol"); the app
/// doesn't switch transports by itself.
LocationItem? nextProtocolLocation(
  List<LocationItem> own,
  LocationItem current,
  Set<String> tried,
) {
  final start = own.indexWhere((l) => l.id == current.id);
  for (var step = 1; step <= own.length; step++) {
    final l = own[(start + step) % own.length];
    if (l.id == current.id ||
        l.isAuto ||
        !l.available ||
        tried.contains(l.id) ||
        l.countryCode != current.countryCode) {
      continue;
    }
    return l;
  }
  return null;
}

/// Auto select's next candidate after [failed] passed no traffic (owner,
/// 16.10): the same place's other protocols first — a blocked transport
/// is the usual cause — then the rest of [ranked] (best ping first).
/// Skips [tried] and unavailable ones; null when nothing is left.
LocationItem? nextAutoCandidate(
  List<LocationItem> ranked,
  LocationItem failed,
  Set<String> tried,
) {
  bool open(LocationItem l) =>
      l.id != failed.id && l.available && !l.isAuto && !tried.contains(l.id);
  String place(LocationItem l) =>
      '${l.countryCode}|${splitPlaceAndProtocol(l.city).$1}';
  final here = place(failed);
  for (final l in ranked) {
    if (open(l) && place(l) == here) return l;
  }
  for (final l in ranked) {
    if (open(l)) return l;
  }
  return null;
}
