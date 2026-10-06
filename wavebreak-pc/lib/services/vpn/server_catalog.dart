import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/language_controller.dart';
import '../../features/home/location_bar.dart';
import '../../features/shared/data_providers.dart';
import '../../features/shared/subscription_section.dart';
import '../core_api/models.dart';
import '../custom_servers/custom_server_controller.dart';
import 'connection_manager.dart';

/// One place (a city in a country) of one subscription section, with its
/// protocol variants — the single source the home header (protocol switch)
/// and the Servers tab (place + protocol) both pick from, so the same
/// choice is always the same [LocationItem].
///
/// Why this exists: the header used to build its protocol switch from all
/// same-country WAVEBREAK entries while the server list showed every
/// entry on its own row. A place could then have two "Direct" entries
/// (a Core node and a personal link, which connect differently), and the
/// header and the list could each pick a different one.
class ServerPlace {
  ServerPlace({
    required this.sectionId,
    required this.countryCode,
    required this.country,
    required this.title,
    required this.variants,
  });

  /// 'wavebreak' or a custom group's id.
  final String sectionId;
  final String countryCode;
  final String country;

  /// The city (without the protocol in brackets), or the country.
  final String title;

  /// One entry per protocol, in [protocolOrder].
  final List<LocationItem> variants;

  LocationItem get primary => variants.first;

  String get key => placeKey(sectionId, countryCode, country, title);

  /// The variant for [protocol] (a [protocolLabel]), if this place has it.
  LocationItem? variant(String? protocol) {
    for (final v in variants) {
      if (protocolLabel(v) == protocol) return v;
    }
    return null;
  }
}

class ServerSection {
  ServerSection({required this.data, required this.places});

  /// Title, limits, share link… (unchanged from the old list).
  final SubscriptionSectionData data;
  final List<ServerPlace> places;
}

String placeKey(String section, String code, String country, String title) =>
    '$section|$code|$country|${title.toLowerCase()}';

/// Display order of protocols inside a place.
const protocolOrder = ['Direct', 'Hysteria2', 'REALITY', 'CDN'];

int _protoRank(String? p) {
  final i = protocolOrder.indexOf(p ?? '');
  return i < 0 ? protocolOrder.length : i;
}

String _titleOf(LocationItem l) {
  final (place, _) = splitPlaceAndProtocol(l.city);
  return place.isNotEmpty ? place : l.country;
}

/// Groups [items] of one section into places. Within a place one entry per
/// protocol is kept: the one with id [preferId] if it is among them (so
/// the current connection keeps its exact entry), otherwise the first
/// available one in list order.
List<ServerPlace> buildPlaces(
  String sectionId,
  List<LocationItem> items, {
  String? preferId,
}) {
  final groups = <String, List<LocationItem>>{};
  final order = <String>[];
  for (final l in items) {
    if (l.isAuto) continue;
    final k = placeKey(sectionId, l.countryCode, l.country, _titleOf(l));
    if (!groups.containsKey(k)) order.add(k);
    (groups[k] ??= []).add(l);
  }
  return [
    for (final k in order) _place(sectionId, groups[k]!, preferId),
  ];
}

ServerPlace _place(String sectionId, List<LocationItem> group, String? preferId) {
  final byProto = <String, LocationItem>{};
  for (final l in group) {
    final p = protocolLabel(l) ?? '';
    final kept = byProto[p];
    if (kept == null) {
      byProto[p] = l;
    } else if (l.id == preferId || (!kept.available && l.available)) {
      if (kept.id != preferId) byProto[p] = l;
    }
  }
  final variants = byProto.values.toList()
    ..sort((a, b) => _protoRank(protocolLabel(a)).compareTo(_protoRank(protocolLabel(b))));
  final first = group.first;
  return ServerPlace(
    sectionId: sectionId,
    countryCode: first.countryCode,
    country: first.country,
    title: _titleOf(first),
    variants: variants,
  );
}

/// The place holding [current]: by id first, else by place + protocol
/// (the current entry may be a duplicate the catalog folded away).
ServerPlace? placeOf(LocationItem current, List<ServerSection> sections) {
  for (final s in sections) {
    for (final p in s.places) {
      if (p.variants.any((v) => v.id == current.id)) return p;
    }
  }
  final title = _titleOf(current);
  for (final s in sections) {
    for (final p in s.places) {
      if (p.countryCode == current.countryCode &&
          p.country == current.country &&
          p.title.toLowerCase() == title.toLowerCase()) {
        return p;
      }
    }
  }
  return null;
}

/// The catalog: WAVEBREAK first, then the user's own groups — same order
/// and titles as before.
final serverCatalogProvider = Provider<List<ServerSection>>((ref) {
  final s = ref.watch(stringsProvider);
  final wavebreak = ref.watch(locationsProvider).valueOrNull ?? const [];
  final custom = ref.watch(customServersProvider);
  final current =
      ref.watch(connectionManagerProvider.select((c) => c.location.id));
  final data = buildSubscriptionSections(
    wavebreakLocations: wavebreak,
    customGroups: custom,
    s: s,
    sharing: ref.watch(sharingProvider).valueOrNull,
  );
  return [
    for (final d in data)
      ServerSection(
        data: d,
        places: buildPlaces(d.id, d.servers, preferId: current),
      ),
  ];
});

