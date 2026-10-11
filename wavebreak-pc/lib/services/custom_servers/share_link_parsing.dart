import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:wavebreak_links/wavebreak_links.dart';

import '../core_api/models.dart';
import 'node_label.dart';

/// Turning a raw share link (or a whole subscription body full of them)
/// into [LocationItem]s — shared between [CustomServerController] (a
/// user's own pasted link/subscription) and WAVEBREAK's own bundled pilot
/// locations (see personal_locations.dart), so both read flag/country/city
/// out of a link's fragment the exact same way instead of drifting apart.
// Single source of truth: wavebreak_links (shared with the other client).
// ssr was listed before but never connectable; tuic/wireguard/socks5 added.
const knownShareSchemes = subscriptionSchemes;

List<LocationItem> parseSubscriptionBody(String body) {
  final servers = <LocationItem>[];
  for (final line in extractShareLinks(body)) {
    final uri = Uri.tryParse(line);
    if (uri == null) continue;
    servers.add(locationFromUri(uri, line));
  }
  return servers;
}

/// Every node of a third-party subscription (any format, see
/// [parseSubscription]). Nodes this phone's engine can't run (TUIC on
/// Xray, types the profile lists that have no share link) stay in the list
/// greyed out (available: false) instead of disappearing.
List<LocationItem> serversFromSubscription(ParsedSubscription parsed,
    {TunnelEngine engine = TunnelEngine.xray}) {
  return [
    for (final link in parsed.links)
      () {
        final uri = Uri.tryParse(link);
        if (uri == null) return null;
        final item = locationFromUri(uri, link);
        final runs = ShareLink.tryParse(link)?.supportedBy(engine) ?? false;
        return runs ? item : _unavailable(item);
      }(),
    for (final node in parsed.unsupported)
      () {
        final parsedLabel = parseNodeLabel(node.name);
        return LocationItem(
          id: stableLocationId('unsupported:${node.type}:${node.name}'),
          countryCode: parsedLabel.countryCode ?? '',
          country: parsedLabel.country,
          city: parsedLabel.place,
          available: false,
          isCustom: true,
        );
      }(),
  ].whereType<LocationItem>().toList();
}

LocationItem _unavailable(LocationItem l) => LocationItem(
      id: l.id,
      countryCode: l.countryCode,
      country: l.country,
      city: l.city,
      available: false,
      isCustom: true,
      rawLink: l.rawLink,
    );

LocationItem locationFromUri(Uri uri, String rawLink) {
  final label = uri.fragment.isNotEmpty
      ? Uri.decodeComponent(uri.fragment)
      : (uri.host.isNotEmpty ? uri.host : rawLink);
  final parsed = parseNodeLabel(label);
  return LocationItem(
    id: stableLocationId(rawLink),
    countryCode: parsed.countryCode ?? '',
    country: parsed.country,
    city: parsed.place,
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
/// on-device: WAVEBREAK's own bundled pilot nodes (personal_locations.dart)
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

/// The country code of the first flag emoji in [label] (see node_label.dart).
String? flagCodeFromLabel(String label) => flagCodeIn(label);

final _shareCodePath = RegExp(r'^/v1/share/([A-Za-z0-9_-]{48})$');

/// The token of a WAVEBREAK share code (`https://<core>/v1/share/<token>`,
/// what the "Share" QR holds), or null for any other link. The token is
/// only ever redeemed with this app's own Core, whatever host the code
/// names.
String? wavebreakShareToken(String link) {
  final uri = Uri.tryParse(link.trim());
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
    return null;
  }
  return _shareCodePath.firstMatch(uri.path)?.group(1);
}
