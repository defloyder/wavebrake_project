import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/storage/prefs_store.dart';
import '../core_api/models.dart';
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
  /// VPN adapter — nothing here is ever sent to WAVEBREAK Core.
  ///
  /// Returns null on success, or an error code: 'invalid', 'blocked',
  /// 'unreachable', 'empty'.
  Future<String?> addFromLink(String link) async {
    final trimmed = link.trim();
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

  Future<void> removeGroup(String id) async {
    state = state.where((g) => g.id != id).toList();
    await _persist();
  }

  Future<void> refreshGroup(String id) async {
    final group = state.firstWhere((g) => g.id == id, orElse: () => state.first);
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
    );
  }
}
