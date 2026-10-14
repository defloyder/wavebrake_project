import 'package:flutter/material.dart';

import '../../core/i18n/app_strings.dart';
import '../../services/core_api/models.dart';
import '../../services/custom_servers/custom_subscription.dart';
import '../../services/custom_servers/share_link_parsing.dart' show shortNote;
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
    this.supportUrl,
    this.autoTags = const [],
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

  /// A third-party provider's support contact (button in the section).
  final String? supportUrl;

  /// "Auto select" rows for a third-party subscription: null picks among
  /// all its servers, a tag ("LTE") among those whose name has it (owner,
  /// 14.10: Happ shows the provider's "Авто выбор" and "Авто выбор LTE").
  final List<String?> autoTags;
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
      // No per-location share here: a location's link is the account's
      // own key, usable on any number of devices and apps past the plan's
      // device limit (owner, 06.10). The share code above takes a slot.
      shareable: false,
      limitsTraffic: own == null ? null : _trafficLine(own, s),
      limitsDevices: own == null ? null : _deviceLine(own),
    ),
    for (final g in customGroups) _sectionFor(g, s, sharing),
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
    limitsTraffic: received != null && !inactive
        ? _trafficLine(received, s)
        : _providerLine(g, s),
    limitsDevices: received != null && !inactive ? _deviceLine(received) : null,
    supportUrl: g.supportUrl,
    autoTags: autoTagsFor(g.servers),
  );
}

/// See [SubscriptionSectionData.autoTags]: all servers when two or more
/// run here, and "LTE" when two or more of those are marked for it.
List<String?> autoTagsFor(List<LocationItem> servers) {
  final ok = servers.where((s) => s.available && s.rawLink != null).toList();
  if (ok.length < 2) return const [];
  bool tagged(LocationItem s, String tag) =>
      '${s.country} ${s.city}'.toUpperCase().contains(tag);
  return [
    null,
    if (ok.where((s) => tagged(s, 'LTE')).length >= 2) 'LTE',
  ];
}

/// The servers an "auto select" row picks from.
List<LocationItem> autoCandidates(List<LocationItem> servers, String? tag) => [
      for (final s in servers)
        if (s.available &&
            s.rawLink != null &&
            (tag == null ||
                '${s.country} ${s.city}'.toUpperCase().contains(tag)))
          s,
    ];

/// Our own section's title: the plan ("WAVEBREAK Fleet"), not a fixed name.
String wavebreakSectionTitle(String? planName) {
  final plan = (planName ?? '').trim();
  if (plan.isEmpty) return 'WAVEBREAK';
  return plan.toUpperCase().startsWith('WAVEBREAK') ? plan : 'WAVEBREAK $plan';
}

/// "2.3 ГБ / 300 ГБ" (or ".../ Без ограничений").
String _trafficLine(SharedSubscription sub, AppStrings s) =>
    formatTraffic(sub.trafficUsedBytes, sub.trafficLimitBytes, s);

/// A third-party subscription's own traffic and end date, from its
/// provider's `subscription-userinfo` header: "2.3 ГБ / 100 ГБ · до
/// 31.10.2026". Null when the provider sends neither.
String? _providerLine(CustomSubscriptionGroup g, AppStrings s,
    [DateTime? now]) {
  final parts = <String>[
    if (g.usedBytes != null)
      formatTraffic(
          g.usedBytes!, (g.totalBytes ?? 0) > 0 ? g.totalBytes : null, s),
    if (g.expiresAt != null)
      (g.expiresAt!.isBefore(now ?? DateTime.now())
              ? s.subscriptionExpiredLine
              : s.subscriptionUntilLine)
          .replaceAll('{date}', _date(g.expiresAt!.toLocal())),
    // No header: what the provider wrote in its note entries instead
    // ("📆 Осталось: 6 дней · 🟢 Остаток трафика LTE: 80/80GB").
    if (g.usedBytes == null && g.expiresAt == null)
      for (final n in g.notes) shortNote(n),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

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
