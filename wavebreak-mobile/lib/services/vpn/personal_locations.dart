import 'dart:async';
import 'dart:convert';

import 'package:wavebreak_links/wavebreak_links.dart' show ShareLink, TunnelEngine;

import '../../core/logging/app_logger.dart';
import '../../core/storage/secure_store.dart';
import '../core_api/core_gateway.dart';
import '../core_api/models.dart';
import '../custom_servers/share_link_parsing.dart';

/// WAVEBREAK's own servers for a paid account (bug 10).
///
/// These used to be share links hardcoded into the app with one shared
/// credential, so every user's traffic landed on a single subscription,
/// limits never applied and the credential shipped inside every APK.
/// Now they come from Core's `POST /v1/me/access`: the account's own
/// credential (one per subscription, shared by its devices) and the links
/// for it — VLESS REALITY, Direct-TLS, Hysteria2 — so traffic is counted
/// on the user's own subscription.
///
/// The last access Core returned is kept in [SecureStore] so connecting
/// still works when Core is unreachable (the nodes, not Core, carry the
/// traffic). It is dropped as soon as Core says the account has no active
/// subscription, and on sign-out.
class PersonalLocations {
  PersonalLocations._();

  /// Covers ApiClient's own retries (3 attempts of 5s plus backoff).
  static const _timeout = Duration(seconds: 20);

  /// Throws when Core can't be reached and nothing is saved yet: an empty
  /// list would read as "no servers", while an error gets the screen's
  /// own message and retry button.
  static Future<List<LocationItem>> load(CoreGateway gateway) async {
    PersonalAccess? access;
    try {
      access = await gateway.personalAccess().timeout(_timeout);
    } catch (error) {
      AppLogger.warn('Personal access unavailable, using the saved one: $error');
      access = await _saved();
      if (access == null) rethrow;
      return _parse(access);
    }
    if (access == null) {
      await forget();
      return const [];
    }
    await SecureStore.write(SecureStore.personalAccess, jsonEncode(access.toJson()));
    return _parse(access);
  }

  /// Drops the saved access (no active subscription any more).
  static Future<void> forget() => SecureStore.delete(SecureStore.personalAccess);

  static Future<PersonalAccess?> _saved() async {
    final raw = await SecureStore.read(SecureStore.personalAccess);
    if (raw == null || raw.isEmpty) return null;
    try {
      return PersonalAccess.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Android runs Xray-core, which supports every transport Core publishes.
  static const _engine = TunnelEngine.xray;

  /// Links this app's tunnel engine can't run are left out rather than
  /// listed and failing on connect.
  static List<LocationItem> _parse(PersonalAccess access) =>
      parseSubscriptionBody(access.links
          .where((l) => ShareLink.tryParse(l)?.supportedBy(_engine) ?? false)
          .join('\n'));
}
