import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/features/shared/subscription_section.dart';
import 'package:wavebreak/features/home/location_bar.dart';
import 'package:wavebreak/services/core_api/models.dart';
import 'package:wavebreak/services/vpn/server_catalog.dart';

LocationItem _l(String id, String city, {String? link, bool available = true}) =>
    LocationItem(
      id: id,
      countryCode: 'TR',
      country: 'Turkey',
      city: city,
      available: available,
      rawLink: link,
    );

void main() {
  // A Core node and a personal link can both be "Istanbul · Direct".
  final coreDirect = _l('core-ist', 'Istanbul (Direct-TLS)');
  final linkDirect = _l('p-ist-d', 'Istanbul (Direct-TLS)', link: 'vless://x');
  final linkHy2 = _l('p-ist-h', 'Istanbul (Hysteria2)', link: 'hysteria2://x');
  final items = [coreDirect, linkHy2, linkDirect];

  test('one place, one entry per protocol, Direct first', () {
    final places = buildPlaces('wavebreak', items);
    expect(places, hasLength(1));
    expect(places.single.title, 'Istanbul');
    expect(places.single.variants.map(protocolLabel), ['Direct', 'Hysteria2']);
    // Without a preference: the first entry in list order.
    expect(places.single.variant('Direct')!.id, 'core-ist');
  });

  test('the current connection keeps its exact entry', () {
    final places = buildPlaces('wavebreak', items, preferId: 'p-ist-d');
    expect(places.single.variant('Direct')!.id, 'p-ist-d');
  });

  test('header and server list pick the same entry for a place + protocol', () {
    final section = ServerSection(
      data: SubscriptionSectionData(
          id: 'wavebreak',
          title: 'WAVEBREAK',
          subtitle: '',
          icon: Icons.public,
          servers: items),
      places: buildPlaces('wavebreak', items, preferId: 'p-ist-h'),
    );
    // Header: the place of the current location, then the protocol.
    final header = placeOf(linkHy2, [section])!.variant('Direct');
    // Server list: the row of that place, then the protocol chip.
    final row = section.places.firstWhere((p) => p.title == 'Istanbul');
    expect(identical(header, row.variant('Direct')), isTrue);
    // A current entry the catalog folded away still finds its place.
    expect(placeOf(linkDirect, [section])!.title, 'Istanbul');
  });

  test('an unavailable duplicate gives way to an available one', () {
    final places = buildPlaces('wavebreak', [
      _l('a', 'Istanbul (Direct-TLS)', available: false),
      _l('b', 'Istanbul (Direct-TLS)'),
    ]);
    expect(places.single.variant('Direct')!.id, 'b');
  });
}
