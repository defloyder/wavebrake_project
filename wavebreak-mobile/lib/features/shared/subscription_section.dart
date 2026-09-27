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
    this.details,
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

  /// The subscription's limits for the header — traffic and devices used,
  /// or why it can't be used right now. Null when not known.
  final String? details;
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
      details: own == null ? null : subscriptionLimitsLine(own, s),
    ),
    for (final g in customGroups)
      SubscriptionSectionData(
        id: g.id,
        title: g.name,
        subtitle: '${g.servers.length} ${s.locationsWord}',
        icon: g.isSubscriptionUrl ? Icons.cloud_outlined : Icons.link,
        servers: g.servers,
        isCustom: true,
        shareLink: g.sharedWithMe ? null : g.sourceLink,
        canRefresh: g.isSubscriptionUrl,
        shareable: !g.sharedWithMe,
        details: g.sharedWithMe ? _receivedDetails(sharing?.receivedFor(g.sourceLink), s) : null,
      ),
  ];
}

String? _receivedDetails(SharedSubscription? received, AppStrings s) {
  if (received == null) return null;
  if (!received.isActive) return s.shareOwnerInactive;
  return subscriptionLimitsLine(received, s);
}

/// Our own section's title: the plan ("WAVEBREAK Fleet"), not a fixed name.
String wavebreakSectionTitle(String? planName) {
  final plan = (planName ?? '').trim();
  if (plan.isEmpty) return 'WAVEBREAK';
  return plan.toUpperCase().startsWith('WAVEBREAK') ? plan : 'WAVEBREAK $plan';
}

/// "2.3 ГБ / 300 ГБ · Устройств: 1 из 2".
String subscriptionLimitsLine(SharedSubscription sub, AppStrings s) {
  final traffic = formatTraffic(sub.trafficUsedBytes, sub.trafficLimitBytes, s);
  if (sub.deviceLimit == null) return traffic;
  final devices = s.shareDevices
      .replaceAll('{used}', '${sub.devicesUsed}')
      .replaceAll('{limit}', '${sub.deviceLimit}');
  return '$traffic · $devices';
}

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
