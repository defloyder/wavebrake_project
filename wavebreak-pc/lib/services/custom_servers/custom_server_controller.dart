import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:wavebreak_links/wavebreak_links.dart' show ShareLink;

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
      return list.whereType<Map>().map((e) => _fromStored(Map<String, dynamic>.from(e))).toList();
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

    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return _addFromSubscriptionUrl(trimmed, uri);
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
    final identity = server.city.isNotEmpty && server.city != uri.scheme.toUpperCase()
        ? '${server.country} · ${server.city}'
        : (uri.host.isNotEmpty ? uri.host : server.country);
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

  Future<String?> _addFromSubscriptionUrl(String link, Uri uri) async {
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

    String body;
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        maxRedirects: 3,
        responseType: ResponseType.plain,
      ));
      final response = await dio.get<String>(link);
      body = response.data ?? '';
      if (body.length > 2 * 1024 * 1024) return 'invalid';
    } catch (_) {
      return 'unreachable';
    }

    final servers = parseSubscriptionBody(body);
    if (servers.isEmpty) return 'empty';

    final group = CustomSubscriptionGroup(
      id: const Uuid().v4(),
      name: uri.host,
      sourceLink: link,
      servers: servers,
    );
    state = [...state, group];
    await _persist();
    return null;
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
      access = await gateway.redeemShare(token: token, deviceName: name, platform: platform);
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
    final existing = state.where((g) => g.sharedWithMe && g.sourceLink == source).toList();
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
    return plan.toUpperCase().startsWith('WAVEBREAK') ? plan : 'WAVEBREAK $plan';
  }

  static List<LocationItem> _sharedServers(List<String> links) =>
      parseSubscriptionBody(links
          .where((l) => ShareLink.tryParse(l)?.supportedBy(PersonalLocations.engine) ?? false)
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
      if (entry == null && redeemed != null && DateTime.now().difference(redeemed) < _redeemGrace) {
        next.add(g);
        continue;
      }
      if (entry == null) {
        disconnect = disconnect ||
            (connection.status != ConnectionStatus.idle &&
                g.servers.any((s) => s.id == connection.location.id));
        continue;
      }
      final servers = entry.links.isEmpty ? g.servers : _sharedServers(entry.links);
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
    if (disconnect) await ref.read(connectionManagerProvider.notifier).disconnect();
  }

  Future<void> refreshGroup(String id) async {
    final group = state.firstWhere((g) => g.id == id, orElse: () => state.first);
    if (group.sharedWithMe) {
      // Through Core, not the raw subscription URL: that one carries every
      // transport (CDN included) and would rename the section to its host.
      try {
        await syncShared(await ref.read(coreGatewayProvider).sharing());
      } catch (_) {}
      return;
    }
    if (!group.isSubscriptionUrl) return;
    final uri = Uri.parse(group.sourceLink);
    String body;
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        maxRedirects: 3,
        responseType: ResponseType.plain,
      ));
      final response = await dio.get<String>(group.sourceLink);
      body = response.data ?? '';
    } catch (_) {
      return;
    }
    final servers = parseSubscriptionBody(body);
    if (servers.isEmpty) return;
    state = [
      for (final g in state)
        if (g.id == id)
          CustomSubscriptionGroup(
            id: g.id,
            name: uri.host,
            sourceLink: g.sourceLink,
            servers: servers,
            sharedWithMe: g.sharedWithMe,
          )
        else
          g,
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
              'servers': g.servers
                  .map((s) => {
                        'id': s.id,
                        'label': s.country,
                        'proto': s.city,
                        'link': s.rawLink,
                        'flag': s.countryCode,
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
              available: true,
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
    );
  }
}
