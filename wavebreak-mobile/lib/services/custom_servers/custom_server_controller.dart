import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:wavebreak_links/wavebreak_links.dart'
    show
        ShareLink,
        SubscriptionUserInfo,
        decodeProfileTitle,
        parseSubscription,
        parseUpdateIntervalHours;

import '../../core/errors/app_exception.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/storage/prefs_store.dart';
import '../core_api/models.dart';
import '../device/device_service.dart';
import '../providers.dart';
import '../vpn/connection_manager.dart';
import '../vpn/personal_locations.dart';
import 'custom_subscription.dart';
import 'share_link_parsing.dart';

final customServersProvider =
    NotifierProvider<CustomServerController, List<CustomSubscriptionGroup>>(
  CustomServerController.new,
);

class CustomServerController extends Notifier<List<CustomSubscriptionGroup>> {
  @override
  List<CustomSubscriptionGroup> build() {
    final raw = PrefsStore.getString(PrefsStore.customServers);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      // Copies of one link added before duplicates were refused: the
      // first one stays.
      final seen = <String>{};
      final groups = list
          .whereType<Map>()
          .map((e) => _fromStored(Map<String, dynamic>.from(e)))
          .where((g) => g.sharedWithMe || seen.add(sameLinkKey(g.sourceLink)))
          .toList();
      // Third-party subscriptions past their update interval are re-read
      // once the app has started (in the background; the stored list is
      // shown meanwhile and kept if a fetch fails).
      if (groups.any((g) => g.isStale(DateTime.now()))) {
        Future<void>.delayed(const Duration(seconds: 3), refreshStale);
      }
      return groups;
    } catch (_) {
      return const [];
    }
  }

  /// Adds either a single server link (vless://, trojan://, ...) or a
  /// subscription URL that expands into many servers. WAVEBREAK never
  /// inspects or forwards link contents anywhere but the local (simulated)
  /// VPN adapter — nothing here is ever sent to WAVEBREAK Core, except the
  /// token of WAVEBREAK's own share code.
  ///
  /// A WAVEBREAK share code (the "Share" QR) is redeemed with Core instead:
  /// that takes one of the owner's device slots, see [_addFromShareCode].
  ///
  /// Returns null on success, or an error code: 'invalid', 'blocked',
  /// 'unreachable', 'empty', or for share codes 'share_limit',
  /// 'share_invalid', 'share_own', 'share_inactive'.
  Future<String?> addFromLink(String link) async {
    final trimmed = link.trim();
    final shareToken = wavebreakShareToken(trimmed);
    if (shareToken != null) return _addFromShareCode(shareToken);
    if (!trimmed.contains('://')) return 'invalid';
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.scheme.isEmpty) return 'invalid';

    // One copy of each link (owner, 06.10: the same Germany link pasted
    // four times made four identical sections).
    final known = await _knownLinkKeys();
    if (known.contains(sameLinkKey(trimmed))) return 'duplicate';

    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return _addFromSubscriptionUrl(trimmed, uri, known);
    }
    if (!knownShareSchemes.contains(uri.scheme)) return 'invalid';

    final server = locationFromUri(uri, trimmed);
    // Naming every single-link group after the bare protocol ("VLESS")
    // meant adding a second VLESS (or Trojan, ...) link over time produced
    // two identically-named groups with no way to tell them apart — bad
    // enough to read as broken. Leading with the protocol *again* here
    // (it's already shown per-server) just added clutter without fixing
    // that, so the identity — a real "Country, City" when the link's
    // fragment decoded to one, otherwise its host — carries the group
    // name on its own.
    final place = server.city.replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), '');
    final identity =
        server.city.isEmpty || server.city == uri.scheme.toUpperCase()
            ? (uri.host.isNotEmpty ? uri.host : server.country)
            // "Germany" alone, not "Germany · Germany", when there's no city.
            : place == server.country
                ? server.country
                : '${server.country} · ${server.city}';
    final group = CustomSubscriptionGroup(
      id: const Uuid().v4(),
      name: identity,
      sourceLink: trimmed,
      servers: [server],
    );
    state = [...state, group];
    await _persist();
    return null;
  }

  /// What makes two links "the same": a single server link without its
  /// `#label` (same server under another name), a subscription URL with
  /// its host lowercased and trailing slash dropped — and WAVEBREAK's two
  /// API hosts (api. behind Cloudflare, core. direct) as one.
  @visibleForTesting
  static String sameLinkKey(String link) {
    final t = link.trim();
    final uri = Uri.tryParse(t);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return t.split('#').first;
    }
    var host = uri.host.toLowerCase();
    if (host == 'api.wavebreak.com.tr') host = 'core.wavebreak.com.tr';
    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return '$host$path?${uri.query}';
  }

  /// Every link already in the list: added sections, their servers, and
  /// the account's own WAVEBREAK servers.
  Future<Set<String>> _knownLinkKeys() async {
    final own =
        await PersonalLocations.saved().catchError((_) => <LocationItem>[]);
    return {
      for (final g in state) ...[
        sameLinkKey(g.sourceLink),
        for (final s in g.servers)
          if (s.rawLink != null) sameLinkKey(s.rawLink!),
      ],
      for (final l in own)
        if (l.rawLink != null) sameLinkKey(l.rawLink!),
    };
  }

  Future<String?> _addFromSubscriptionUrl(
      String link, Uri uri, Set<String> known) async {
    // Plain http:// is common for self-hosted panels/test deployments
    // (no TLS cert on a bare IP, exactly like the pilot itself) — the
    // real risk worth blocking is a request into the user's own local
    // network, not the absence of TLS on a public subscription URL.
    final host = uri.host.toLowerCase();
    if (host.isEmpty ||
        host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host.startsWith('10.') ||
        host.startsWith('192.168.') ||
        RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(host)) {
      return 'blocked';
    }

    final _Fetched fetched;
    try {
      fetched = await _fetch(link);
    } on _TooLarge {
      return 'invalid';
    } catch (_) {
      return 'unreachable';
    }
    final group =
        _groupFrom(fetched, id: const Uuid().v4(), link: link, uri: uri);
    if (group == null) return 'empty';
    // Another address of a subscription that is already here (e.g. the
    // account's own WAVEBREAK one): every server is known.
    if (group.servers.every(
        (s) => s.rawLink != null && known.contains(sameLinkKey(s.rawLink!)))) {
      return 'duplicate';
    }
    state = [...state, group];
    await _persist();
    return null;
  }

  /// Reads a subscription URL: the body and the headers that describe it
  /// (subscription-userinfo, profile-title, profile-update-interval).
  static Future<_Fetched> _fetch(String link) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      maxRedirects: 3,
      responseType: ResponseType.plain,
    ));
    final response = await dio.get<String>(link);
    final body = response.data ?? '';
    if (body.length > 2 * 1024 * 1024) throw _TooLarge();
    return _Fetched(body, response.headers);
  }

  /// A section from a fetched subscription in any format (share links,
  /// base64, Clash/Mihomo YAML, sing-box JSON); null when it has no nodes.
  @visibleForTesting
  static CustomSubscriptionGroup? groupFromResponse(
    String body,
    Map<String, List<String>> headers, {
    required String id,
    required String link,
    DateTime? now,
  }) =>
      _groupFrom(_Fetched(body, Headers.fromMap(headers)),
          id: id, link: link, uri: Uri.parse(link), now: now);

  static CustomSubscriptionGroup? _groupFrom(
    _Fetched fetched, {
    required String id,
    required String link,
    required Uri uri,
    DateTime? now,
  }) {
    final parsed = parseSubscription(fetched.body);
    final servers = serversFromSubscription(parsed);
    if (servers.isEmpty) return null;
    final info = SubscriptionUserInfo.parse(
        fetched.headers.value('subscription-userinfo'));
    return CustomSubscriptionGroup(
      id: id,
      name: decodeProfileTitle(fetched.headers.value('profile-title')) ??
          uri.host,
      sourceLink: link,
      servers: servers,
      usedBytes: info?.used,
      totalBytes: info?.total,
      expiresAt: info?.expire,
      updateIntervalHours: parseUpdateIntervalHours(
          fetched.headers.value('profile-update-interval')),
      updatedAt: now ?? DateTime.now(),
    );
  }

  /// Re-reads every subscription URL whose update interval has passed
  /// (its own `profile-update-interval`, else 12 h). Called when the app
  /// shows its servers; failures keep the last good list.
  Future<void> refreshStale() async {
    final now = DateTime.now();
    for (final g in [...state]) {
      if (g.isStale(now)) await refreshGroup(g.id);
    }
  }

  /// Redeems someone's share code with this app's own Core. Core checks
  /// the owner's device limit and only then returns the owner's links;
  /// they land here as one more section. Scanning the same code again
  /// refreshes that section instead of adding a second one.
  Future<String?> _addFromShareCode(String token) async {
    final gateway = ref.read(coreGatewayProvider);
    final SharedAccess access;
    try {
      final (platform, name) = await DeviceService(gateway).platformInfo();
      access = await gateway.redeemShare(
          token: token, deviceName: name, platform: platform);
    } on AppException catch (e) {
      return switch (e.kind) {
        AppErrorKind.deviceLimitReached => 'share_limit',
        AppErrorKind.shareInvalid => 'share_invalid',
        AppErrorKind.shareOwnSubscription => 'share_own',
        _ when e.statusCode == 404 || e.statusCode == 422 => 'share_inactive',
        _ => 'unreachable',
      };
    } catch (_) {
      return 'unreachable';
    }
    // Only what this app's tunnel engine runs, as for our own locations.
    final servers = _sharedServers(access.links);
    if (servers.isEmpty) return 'empty';
    final source = access.subscriptionUrl ?? '';
    final existing =
        state.where((g) => g.sharedWithMe && g.sourceLink == source).toList();
    final group = CustomSubscriptionGroup(
      id: existing.isNotEmpty ? existing.first.id : const Uuid().v4(),
      name: _sharedName(access.planName),
      sourceLink: source,
      servers: servers,
      sharedWithMe: true,
    );
    _redeemedAt[source] = DateTime.now();
    state = existing.isNotEmpty
        ? [for (final g in state) g.id == group.id ? group : g]
        : [...state, group];
    await _persist();
    return null;
  }

  Future<void> removeGroup(String id) async {
    state = state.where((g) => g.id != id).toList();
    await _persist();
  }

  final _redeemedAt = <String, DateTime>{};
  static const _redeemGrace = Duration(minutes: 2);

  @visibleForTesting
  void forgetRecentRedeems() => _redeemedAt.clear();

  /// Section title of a redeemed subscription: its plan, like our own
  /// ("WAVEBREAK Fleet") — never the Core host its URL happens to name.
  String _sharedName(String planName) {
    final plan = planName.trim();
    if (plan.isEmpty) return ref.read(stringsProvider).sharedAccessTitle;
    return plan.toUpperCase().startsWith('WAVEBREAK')
        ? plan
        : 'WAVEBREAK $plan';
  }

  static List<LocationItem> _sharedServers(List<String> links) =>
      parseSubscriptionBody(links
          .where((l) =>
              ShareLink.tryParse(l)?.supportedBy(PersonalLocations.engine) ??
              false)
          .join('\n'));

  /// Brings redeemed sections in line with Core's GET /me/sharing: plan
  /// name and the same app links as our own locations (no CDN). A section
  /// whose slot the owner revoked is gone from [overview] and is removed
  /// here — disconnecting first if the tunnel runs through it. While the
  /// owner's subscription is inactive the links are kept as they were.
  Future<void> syncShared(SharingOverview overview) async {
    if (!state.any((g) => g.sharedWithMe)) return;
    final connection = ref.read(connectionManagerProvider);
    var disconnect = false;
    final next = <CustomSubscriptionGroup>[];
    for (final g in state) {
      if (!g.sharedWithMe) {
        next.add(g);
        continue;
      }
      final entry = overview.receivedFor(g.sourceLink);
      // An overview requested before a fresh redeem can arrive after it;
      // it just doesn't know the new slot yet — not a revocation.
      final redeemed = _redeemedAt[g.sourceLink];
      if (entry == null &&
          redeemed != null &&
          DateTime.now().difference(redeemed) < _redeemGrace) {
        next.add(g);
        continue;
      }
      if (entry == null) {
        disconnect = disconnect ||
            (connection.status != ConnectionStatus.idle &&
                g.servers.any((s) => s.id == connection.location.id));
        continue;
      }
      final servers =
          entry.links.isEmpty ? g.servers : _sharedServers(entry.links);
      next.add(CustomSubscriptionGroup(
        id: g.id,
        name: _sharedName(entry.planName),
        sourceLink: g.sourceLink,
        servers: servers.isEmpty ? g.servers : servers,
        sharedWithMe: true,
      ));
    }
    state = next;
    await _persist();
    if (disconnect)
      await ref.read(connectionManagerProvider.notifier).disconnect();
  }

  Future<void> refreshGroup(String id) async {
    final group =
        state.firstWhere((g) => g.id == id, orElse: () => state.first);
    if (group.sharedWithMe) {
      // Through Core, not the raw subscription URL: that one carries every
      // transport (CDN included) and would rename the section to its host.
      try {
        await syncShared(await ref.read(coreGatewayProvider).sharing());
      } catch (_) {}
      return;
    }
    if (!group.isSubscriptionUrl) return;
    final _Fetched fetched;
    try {
      fetched = await _fetch(group.sourceLink);
    } catch (_) {
      return;
    }
    final fresh = _groupFrom(fetched,
        id: group.id, link: group.sourceLink, uri: Uri.parse(group.sourceLink));
    if (fresh == null) return;
    state = [
      for (final g in state)
        if (g.id == id) fresh else g,
    ];
    await _persist();
  }

  Future<void> _persist() async {
    final encoded = jsonEncode(state
        .map((g) => {
              'id': g.id,
              'name': g.name,
              'link': g.sourceLink,
              if (g.sharedWithMe) 'shared': true,
              if (g.usedBytes != null) 'used': g.usedBytes,
              if (g.totalBytes != null) 'total': g.totalBytes,
              if (g.expiresAt != null) 'expire': g.expiresAt!.toIso8601String(),
              if (g.updateIntervalHours != null)
                'interval': g.updateIntervalHours,
              if (g.updatedAt != null)
                'updated': g.updatedAt!.toIso8601String(),
              'servers': g.servers
                  .map((s) => {
                        'id': s.id,
                        'label': s.country,
                        'proto': s.city,
                        'link': s.rawLink,
                        'flag': s.countryCode,
                        if (!s.available) 'off': true,
                      })
                  .toList(),
            })
        .toList());
    await PrefsStore.setString(PrefsStore.customServers, encoded);
  }

  CustomSubscriptionGroup _fromStored(Map<String, dynamic> json) {
    final servers = (json['servers'] as List? ?? [])
        .whereType<Map>()
        .map((s) => LocationItem(
              id: s['id'] as String,
              countryCode: (s['flag'] ?? '').toString(),
              country: (s['label'] ?? 'Custom').toString(),
              city: (s['proto'] ?? '').toString(),
              available: s['off'] != true,
              isCustom: true,
              rawLink: s['link'] as String?,
            ))
        .toList();
    return CustomSubscriptionGroup(
      id: json['id'] as String,
      name: (json['name'] ?? 'Custom').toString(),
      sourceLink: (json['link'] ?? '').toString(),
      servers: servers,
      sharedWithMe: json['shared'] == true,
      usedBytes: (json['used'] as num?)?.toInt(),
      totalBytes: (json['total'] as num?)?.toInt(),
      expiresAt: DateTime.tryParse((json['expire'] ?? '').toString()),
      updateIntervalHours: (json['interval'] as num?)?.toInt(),
      updatedAt: DateTime.tryParse((json['updated'] ?? '').toString()),
    );
  }
}

class _Fetched {
  _Fetched(this.body, this.headers);
  final String body;
  final Headers headers;
}

class _TooLarge implements Exception {}
