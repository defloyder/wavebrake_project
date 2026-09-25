import 'dart:convert';

import 'package:dio/dio.dart' show CancelToken;

import '../../core/api/api_client.dart';
import '../../core/errors/app_exception.dart';
import 'models.dart';

/// WAVEBREAK Core API client. Paths follow
/// `wavebreak-core/api/openapi.yaml` / `MOBILE_DESKTOP_DEVELOPER_HANDOFF.md`
/// exactly — Core is a standalone service; the app never talks to the
/// Laravel Web/Admin apps or the node-agent directly.
class CoreApi {
  CoreApi(this._client);

  final ApiClient _client;

  // ---- Auth ----------------------------------------------------------

  Future<TokenPair> register({
    required String email,
    required String password,
    CancelToken? cancelToken,
  }) {
    return _client.post(
      '/auth/register',
      body: {'email': email, 'password': password},
      parse: _tokens,
      cancelToken: cancelToken,
      retryOnConnectionError: true,
    );
  }

  Future<TokenPair> login({
    required String email,
    required String password,
    CancelToken? cancelToken,
  }) {
    return _client.post(
      '/auth/login',
      body: {'email': email, 'password': password},
      parse: _tokens,
      cancelToken: cancelToken,
      retryOnConnectionError: true,
    );
  }

  Future<TokenPair> refresh(String refreshToken) {
    return _client.post(
      '/auth/refresh',
      body: {'refresh_token': refreshToken},
      parse: _tokens,
    );
  }

  Future<void> logout(String refreshToken) async {
    try {
      await _client.post(
        '/auth/logout',
        body: {'refresh_token': refreshToken},
      );
    } on AppException {
      // Local session is cleared regardless of whether Core acknowledged.
    }
  }

  // ---- Session / bootstrap --------------------------------------------

  Future<UserProfile> me() {
    return _client.get('/me', parse: (data) => UserProfile.fromJson(_asMap(data)));
  }

  Future<BootstrapResponse> bootstrap() {
    return _client.get(
      '/client/bootstrap',
      parse: (data) => BootstrapResponse.fromJson(_asMap(data)),
    );
  }

  // ---- Plans / subscription -------------------------------------------

  Future<List<Plan>> plans() {
    return _client.get(
      '/plans',
      parse: (data) {
        final list = _asMap(data)['plans'];
        if (list is! List) return const <Plan>[];
        return list
            .whereType<Map>()
            .map((e) => Plan.fromJson(e.cast<String, dynamic>()))
            .toList();
      },
    );
  }

  Future<SubscriptionInfo> createSubscription(String planId) {
    return _client.post(
      '/subscriptions',
      body: {'plan_id': planId},
      parse: (data) => SubscriptionInfo.fromJson(_asMap(data)),
    );
  }

  Future<SubscriptionInfo> currentSubscription() {
    return _client.get(
      '/subscriptions/current',
      parse: (data) => SubscriptionInfo.fromJson(_asMap(data)),
    );
  }

  // ---- Devices ---------------------------------------------------------

  Future<List<DeviceItem>> devices() {
    return _client.get(
      '/me/devices',
      parse: (data) {
        final list = _asMap(data)['devices'];
        if (list is! List) return const <DeviceItem>[];
        return list
            .whereType<Map>()
            .map((e) => DeviceItem.fromJson(e.cast<String, dynamic>()))
            .toList();
      },
    );
  }

  Future<DeviceItem> registerDevice({
    required String platform,
    required String name,
  }) {
    return _client.post(
      '/me/devices',
      body: {'name': name, 'platform': platform},
      parse: (data) => DeviceItem.fromJson(_asMap(data)),
    );
  }

  Future<DeviceItem> updateDevice({
    required String deviceId,
    required String name,
    required String platform,
  }) {
    return _client.patch(
      '/me/devices/$deviceId',
      body: {'name': name, 'platform': platform},
      parse: (data) => DeviceItem.fromJson(_asMap(data)),
    );
  }

  Future<void> revokeDevice(String deviceId) {
    return _client.delete('/me/devices/$deviceId');
  }

  // ---- Locations ---------------------------------------------------------

  Future<List<LocationItem>> locations() {
    return _client.get(
      '/locations',
      parse: (data) {
        final map = _asMap(data);
        // `locations` is the rich shape (real country/city, online flag,
        // connection_test) — prefer it. `nodes` is the older flat shape,
        // kept only as a fallback for a Core version that hasn't added
        // `locations` yet.
        final list = map['locations'] ?? map['nodes'];
        if (list is! List) return const <LocationItem>[];
        return list
            .whereType<Map>()
            .map((e) => LocationItem.fromJson(e.cast<String, dynamic>()))
            .toList();
      },
    );
  }

  // ---- Access grants -----------------------------------------------------

  Future<List<AccessGrant>> accessGrants() {
    return _client.get(
      '/access/grants',
      parse: (data) {
        final list = _asMap(data)['grants'];
        if (list is! List) return const <AccessGrant>[];
        return list
            .whereType<Map>()
            .map((e) => AccessGrant.fromJson(e.cast<String, dynamic>()))
            .toList();
      },
    );
  }

  Future<AccessGrant> createAccessGrant({
    required String nodeId,
    required String deviceId,
    String protocol = 'wireguard',
  }) {
    return _client.post(
      '/access/grants',
      body: {'node_id': nodeId, 'device_id': deviceId, 'protocol': protocol},
      parse: (data) => AccessGrant.fromJson(_asMap(data)),
    );
  }

  Future<AccessGrant> revokeAccessGrant(String grantId) {
    return _client.post(
      '/access/grants/$grantId/revoke',
      parse: (data) => AccessGrant.fromJson(_asMap(data)),
    );
  }

  Future<VpnConfigResponse> grantConfig(String grantId) {
    return _client.get(
      '/access/grants/$grantId/config',
      parse: (data) => VpnConfigResponse.fromJson(_asMap(data)),
    );
  }

  // ---- Usage ---------------------------------------------------------

  Future<UsageSummary> usage() {
    return _client.get('/me/usage', parse: (data) => UsageSummary.fromJson(_asMap(data)));
  }

  Future<Map<String, dynamic>> usageHistory({required String period}) {
    return _client.get(
      '/me/usage/history',
      query: {'period': period},
      parse: (data) => _asMap(data),
    );
  }

  // ---- Telegram identity -----------------------------------------------

  Future<List<Map<String, dynamic>>> identities() {
    return _client.get(
      '/me/identities',
      parse: (data) {
        final list = _asMap(data)['identities'];
        if (list is! List) return const <Map<String, dynamic>>[];
        return list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
      },
    );
  }

  Future<String?> createTelegramLinkToken() {
    return _client.post(
      '/me/identities/telegram/link',
      parse: (data) => _asMap(data)['token'] as String?,
    );
  }

  Future<void> unlinkTelegram() {
    return _client.delete('/me/identities/telegram');
  }

  TokenPair _tokens(dynamic data) => TokenPair.fromJson(_asMap(data));

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        // fall through
      }
    }
    return <String, dynamic>{};
  }
}
