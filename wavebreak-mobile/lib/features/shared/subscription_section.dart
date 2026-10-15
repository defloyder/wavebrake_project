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
    this.autoExclude,
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

  /// Left out of every [autoTags] row's own candidate pool (not just a
  /// separate tagged row): RU-LTE-01 is its own standalone chain, not one
  /// of the interchangeable real locations the WAVEBREAK section's plain
  /// "Auto select" should balance across (owner, 14.10).
  final String? autoExclude;
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
  // Bug 6 removed the old hardcoded "Auto · Fastest" row; this one (owner,
  // 14.10) is the real thing, reusing the Auto select machinery built for
  // third-party subscriptions — across the real WAVEBREAK locations only,
  // not RU-LTE-01 (its own standalone chain, excluded via autoExclude).
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
      // Every current Russia-based WAVEBREAK location (LTE, Moscow) chains
      // its egress through Istanbul rather than reaching the internet
      // directly — a restricted-network bypass mechanism, not an
      // interchangeable "pick whichever's fastest" location (owner,
      // 15.10: Moscow specifically flagged after LTE was excluded here
      // but Moscow wasn't).
      autoTags: autoTagsFor(wavebreakServers, exclude: 'Russia'),
      autoExclude: 'Russia',
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

bool _nameHas(LocationItem s, String tag) =>
    '${s.country} ${s.city}'.toUpperCase().contains(tag.toUpperCase());

/// Nodes a provider runs for one service ("YouTube без рекламы",
/// "Netflix", "ChatGPT") rather than as a VPN location: often the lowest
/// ping, so auto select picked them over the real locations (owner,
/// 15.10). They stay in the list, but never in an auto select pool.
final _serviceNode = RegExp(
  r'youtube|ютуб|реклам|\bno[ -]?ads?\b|ad[ -]?free|adblock|'
  r'netflix|spotify|chatgpt|openai|tiktok|torrent|торрент',
  caseSensitive: false,
  unicode: true,
);

bool isServiceNode(LocationItem s) =>
    _serviceNode.hasMatch('${s.country} ${s.city}');

bool _autoEligible(LocationItem s, String? exclude) =>
    s.available &&
    s.rawLink != null &&
    !isServiceNode(s) &&
    (exclude == null || !_nameHas(s, exclude));

/// See [SubscriptionSectionData.autoTags]: all eligible servers when two or
/// more run here (minus [exclude], e.g. "LTE" — a standalone location that
/// doesn't belong in the "all" row's own candidate pool either), and a tag
/// when two or more of those are marked for it.
List<String?> autoTagsFor(List<LocationItem> servers, {String? exclude}) {
  final ok = servers.where((s) => _autoEligible(s, exclude)).toList();
  if (ok.length < 2) return const [];
  return [
    null,
    if (ok.where((s) => _nameHas(s, 'LTE')).length >= 2) 'LTE',
  ];
}

/// The servers an "auto select" row picks from: [tag] narrows to a subset
/// ("LTE"), [exclude] drops one out of every row's pool regardless of tag
/// (RU-LTE-01 out of the WAVEBREAK section's plain "Auto select" — it's its
/// own standalone chain, not interchangeable with the others).
List<LocationItem> autoCandidates(List<LocationItem> servers, String? tag,
        {String? exclude}) =>
    [
      for (final s in servers)
        if (_autoEligible(s, exclude) && (tag == null || _nameHas(s, tag))) s,
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
