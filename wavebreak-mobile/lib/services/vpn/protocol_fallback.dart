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
