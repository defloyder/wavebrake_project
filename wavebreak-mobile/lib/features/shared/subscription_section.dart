import 'package:flutter/material.dart';

import '../../core/i18n/app_strings.dart';
import '../../services/core_api/models.dart';
import '../../services/custom_servers/custom_subscription.dart';
import 'traffic_format.dart';

class SubscriptionSectionData {
  const SubscriptionSectionData({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.servers,
    this.isCustom = false,
    this.shareLink,
    this.canRefresh = false,
    this.shareable = true,
    this.limitsTraffic,
    this.limitsDevices,
    this.limitsNote,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<LocationItem> servers;
  final bool isCustom;
  final String? shareLink;
  final bool canRefresh;

  /// False for someone else's subscription redeemed from their share
  /// code: its links hold one of their device slots and aren't passed on.
  final bool shareable;

  /// Traffic used of the limit for the header ("2.3 ГБ / 300 ГБ"), the
  /// compact device count ("1 / 2", shown next to a small device icon so
  /// the line stays short), or a note replacing both when the subscription
  /// can't be used ("Подписка владельца неактивна"). All null when unknown.
  final String? limitsTraffic;
  final String? limitsDevices;
  final String? limitsNote;
}

/// Stands in for the account's own share code: the share sheet asks Core
/// for a fresh one (with its limits) instead of showing a fixed link.
const kPersonalShareLink = 'wavebreak:personal-share';

List<SubscriptionSectionData> buildSubscriptionSections({
  required List<LocationItem> wavebreakLocations,
  required List<CustomSubscriptionGroup> customGroups,
  required AppStrings s,
  SharingOverview? sharing,
}) {
  // Bug 6: no "Auto · Fastest" row — only real locations.
  final wavebreakServers = [...wavebreakLocations];
  final own = sharing?.own;
  return [
    SubscriptionSectionData(
      id: 'wavebreak',
      title: wavebreakSectionTitle(own?.planName),
      subtitle: '${wavebreakServers.length} ${s.locationsWord}',
      icon: Icons.workspace_premium_outlined,
      servers: wavebreakServers,
      // Resolved to a fresh share code from Core when the sheet opens.
      shareLink: kPersonalShareLink,
      limitsTraffic: own == null ? null : _trafficLine(own, s),
      limitsDevices: own == null ? null : _deviceLine(own),
    ),
    for (final g in customGroups)
      _sectionFor(g, s, sharing),
  ];
}

SubscriptionSectionData _sectionFor(
    CustomSubscriptionGroup g, AppStrings s, SharingOverview? sharing) {
  final received = g.sharedWithMe ? sharing?.receivedFor(g.sourceLink) : null;
  final inactive = received != null && !received.isActive;
  return SubscriptionSectionData(
    id: g.id,
    title: g.name,
    subtitle: '${g.servers.length} ${s.locationsWord}',
    icon: g.isSubscriptionUrl ? Icons.cloud_outlined : Icons.link,
    servers: g.servers,
    isCustom: true,
    shareLink: g.sharedWithMe ? null : g.sourceLink,
    canRefresh: g.isSubscriptionUrl,
    shareable: !g.sharedWithMe,
    limitsNote: inactive ? s.shareOwnerInactive : null,
    limitsTraffic: received != null && !inactive ? _trafficLine(received, s) : null,
    limitsDevices: received != null && !inactive ? _deviceLine(received) : null,
  );
}

/// Our own section's title: the plan ("WAVEBREAK Fleet"), not a fixed name.
String wavebreakSectionTitle(String? planName) {
  final plan = (planName ?? '').trim();
  if (plan.isEmpty) return 'WAVEBREAK';
  return plan.toUpperCase().startsWith('WAVEBREAK') ? plan : 'WAVEBREAK $plan';
}

/// "2.3 ГБ / 300 ГБ" (or ".../ Без ограничений").
String _trafficLine(SharedSubscription sub, AppStrings s) =>
    formatTraffic(sub.trafficUsedBytes, sub.trafficLimitBytes, s);

/// Compact "1 / 2" for the device count, shown next to a device icon —
/// short enough to sit on the same line as the traffic. Null for an
/// unmetered device count.
String? _deviceLine(SharedSubscription sub) =>
    sub.deviceLimit == null ? null : '${sub.devicesUsed} / ${sub.deviceLimit}';

/// Which section contains the currently active server, so the picker can
/// open with that section already expanded.
String sectionIdFor(List<SubscriptionSectionData> sections, String locationId) {
  for (final section in sections) {
    if (section.servers.any((l) => l.id == locationId)) return section.id;
  }
  return sections.isNotEmpty ? sections.first.id : '';
}

/// Resolved by the location picker when the user taps "Add your own link".
/// Never a real server — callers must check for this id first and, only
/// otherwise, treat the result as a genuine selection.
const kAddCustomLinkId = '__add_custom_link__';

const addCustomLinkSentinel = LocationItem(
  id: kAddCustomLinkId,
  countryCode: '',
  country: '',
  city: '',
  available: true,
);
