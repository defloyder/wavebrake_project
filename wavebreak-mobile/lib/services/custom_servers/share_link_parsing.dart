import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core_api/models.dart';

/// Turning a raw share link (or a whole subscription body full of them)
/// into [LocationItem]s — shared between [CustomServerController] (a
/// user's own pasted link/subscription) and WAVEBREAK's own bundled pilot
/// locations (see bundled_locations.dart), so both read flag/country/city
/// out of a link's fragment the exact same way instead of drifting apart.
const knownShareSchemes = ['vless', 'trojan', 'vmess', 'ss', 'hysteria2', 'hy2', 'ssr', 'socks'];

List<LocationItem> parseSubscriptionBody(String body) {
  var text = body.trim();
  if (!text.contains('://')) {
    try {
      final decoded = utf8.decode(base64.decode(base64.normalize(text)));
      if (decoded.contains('://')) text = decoded;
    } catch (_) {
      // Not base64 — fall through and try the raw body as-is.
    }
  }

  final servers = <LocationItem>[];
  for (final rawLine in text.split(RegExp(r'[\r\n]+'))) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final uri = Uri.tryParse(line);
    if (uri == null || !knownShareSchemes.contains(uri.scheme)) continue;
    servers.add(locationFromUri(uri, line));
  }
  return servers;
}

LocationItem locationFromUri(Uri uri, String rawLink) {
  final label = uri.fragment.isNotEmpty
      ? Uri.decodeComponent(uri.fragment)
      : (uri.host.isNotEmpty ? uri.host : rawLink);
  final countryCode = flagCodeFromLabel(label);
  final parsed = splitCountryCity(label, countryCode != null);
  return LocationItem(
    id: stableLocationId(rawLink),
    countryCode: countryCode ?? '',
    country: parsed.$1,
    city: parsed.$2 ?? uri.scheme.toUpperCase(),
    available: true,
    isCustom: true,
    rawLink: rawLink,
  );
}

/// A random id here (the previous approach, `Uuid().v4()`) meant a location
/// re-parsed from the same link on a later fetch never matched its earlier
/// self — `ConnectionManager` and `PrefsStore.lastLocationId` identify the
/// selected/persisted location purely by id, so restoring "what was
/// selected" after a restart could only ever work by accident. Confirmed
/// on-device: WAVEBREAK's own bundled pilot nodes (bundled_locations.dart)
/// are re-parsed fresh on every cold start, and a previously-selected one
/// never rehydrated correctly — the app fell back to whatever OTHER stored
/// selection happened to share an id, silently reconnecting to a stale
/// custom link instead. Hashing the link itself makes the id a pure
/// function of content: the same link always gets the same id, a changed
/// one (different credential, different port) gets a new one, which is
/// exactly "is this the same server" for a share link.
String stableLocationId(String rawLink) {
  return sha256.convert(utf8.encode(rawLink)).toString().substring(0, 32);
}

/// A share link's label commonly leads with an actual flag emoji (e.g.
/// WAVEBREAK's own `"🇳🇱 Netherlands, Amsterdam (CDN)"`) — decoding the two
/// regional-indicator codepoints back into an ISO code is exact and needs
/// no country-name matching, unlike guessing from free text. Without it,
/// [LocationItem.countryCode] stayed empty for every custom server, which
/// is why the flag/icon UI fell back to a neutral globe for all of them
/// regardless of what the link actually pointed at.
String? flagCodeFromLabel(String label) {
  final units = label.codeUnits;
  for (var i = 0; i + 3 < units.length; i++) {
    final high1 = units[i], low1 = units[i + 1];
    final high2 = units[i + 2], low2 = units[i + 3];
    final cp1 = _surrogatePair(high1, low1);
    final cp2 = _surrogatePair(high2, low2);
    if (cp1 == null || cp2 == null) continue;
    if (cp1 < 0x1F1E6 || cp1 > 0x1F1FF) continue;
    if (cp2 < 0x1F1E6 || cp2 > 0x1F1FF) continue;
    final a = String.fromCharCode(cp1 - 0x1F1E6 + 65);
    final b = String.fromCharCode(cp2 - 0x1F1E6 + 65);
    return '$a$b';
  }
  return null;
}

int? _surrogatePair(int high, int low) {
  if (high < 0xD800 || high > 0xDBFF || low < 0xDC00 || low > 0xDFFF) return null;
  return 0x10000 + (high - 0xD800) * 0x400 + (low - 0xDC00);
}

/// Best-effort split of `"🇳🇱 Netherlands, Amsterdam (CDN)"` into
/// (`"Netherlands"`, `"Amsterdam"`) — strips the flag and any trailing
/// `(protocol)` note, then splits on the first comma. Falls back to the
/// whole label as-is if it doesn't look like that shape, since a custom
/// link's fragment can be genuinely arbitrary text.
(String, String?) splitCountryCity(String label, bool hadFlag) {
  var text = label;
  if (hadFlag) {
    // Drop the flag (2 regional-indicator codepoints = 4 UTF-16 units)
    // and any space right after it.
    final units = text.codeUnits;
    var start = 0;
    for (var i = 0; i + 3 < units.length; i++) {
      final cp1 = _surrogatePair(units[i], units[i + 1]);
      final cp2 = _surrogatePair(units[i + 2], units[i + 3]);
      if (cp1 != null && cp2 != null && cp1 >= 0x1F1E6 && cp1 <= 0x1F1FF) {
        start = i + 4;
        break;
      }
    }
    text = String.fromCharCodes(units.sublist(start)).trimLeft();
  }
  // Kept, not discarded: a subscription that hands back the same
  // "Country, City" under several transports (a direct link plus a
  // CDN/Trojan fallback) only differs by this "(CDN)"/"(Trojan)" note.
  // Dropping it made every variant read as one indistinguishable
  // "Netherlands · Amsterdam" row.
  final parenIndex = text.indexOf(' (');
  final note = parenIndex > 0 ? text.substring(parenIndex).trim() : '';
  if (parenIndex > 0) text = text.substring(0, parenIndex);
  final commaIndex = text.indexOf(',');
  if (commaIndex > 0 && commaIndex < text.length - 1) {
    final country = text.substring(0, commaIndex).trim();
    final city = text.substring(commaIndex + 1).trim();
    return (country, note.isEmpty ? city : '$city $note');
  }
  return (label, null);
}
