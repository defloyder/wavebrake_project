import 'package:dio/dio.dart' show CancelToken;

import '../../core/api/api_client.dart';
import '../../core/env/app_env.dart';
import '../../core/errors/app_exception.dart';
import '../../core/storage/secure_store.dart';
import 'core_api.dart';
import 'mock_backend.dart';
import 'models.dart';

class CoreGateway {
  CoreGateway({
    required this.live,
    required this.mock,
    this.useMock = AppEnv.useMockApi,
  });

  final CoreApi live;
  final MockCoreBackend mock;
  final bool useMock;

  // ---- Auth ------------------------------------------------------------

  Future<TokenPair> login({
    required String email,
    required String password,
    CancelToken? cancelToken,
  }) {
    if (useMock) return mock.login(email, password);
    return live.login(
        email: email, password: password, cancelToken: cancelToken);
  }

  Future<TokenPair> register({
    required String email,
    required String password,
    CancelToken? cancelToken,
  }) {
    if (useMock) return mock.register(email, password);
    return live.register(
        email: email, password: password, cancelToken: cancelToken);
  }

  Future<TokenPair> refresh(String refreshToken) {
    if (useMock) return mock.refresh();
    return live.refresh(refreshToken);
  }

  Future<void> logout(String refreshToken) async {
    if (useMock) return;
    await live.logout(refreshToken);
  }

  Future<void> forgotPassword(String email) {
    // Core's public API doesn't expose a forgot-password endpoint yet.
    return Future<void>.value();
  }

  Future<UserProfile> me() {
    if (useMock) return mock.me();
    return live.me();
  }

  Future<BootstrapResponse> bootstrap() {
    if (useMock) return mock.bootstrap();
    return live.bootstrap();
  }

  // ---- Plans / subscription --------------------------------------------

  Future<List<Plan>> plans() {
    if (useMock) return mock.getPlans();
    return live.plans();
  }

  Future<SubscriptionInfo> createSubscription(String planId) async {
    final sub = useMock
        ? await mock.createSubscription(planId)
        : await live.createSubscription(planId);
    return _withPlanName(sub);
  }

  Future<SubscriptionInfo> subscription() async {
    if (useMock) return _withPlanName(await mock.getSubscription());
    try {
      return await _withPlanName(await live.currentSubscription());
    } on AppException catch (error) {
      // Core answers a real account with no subscription yet (never
      // bought a plan) with a 404 "subscription not found" — a perfectly
      // normal state, not a failure. Left unhandled, that 404 fell
      // through error_mapper's generic >=400 fallback as "WAVEBREAK
      // temporarily unavailable" instead of the same "none" state a
      // guest sees, which otherwise-fixed data_providers.dart gating
      // still surfaced as a scary, wrong error for a plain free account.
      if (error.statusCode == 404) return const SubscriptionInfo(status: 'none');
      rethrow;
    }
  }

  Future<UsageSummary?> usage() async {
    if (useMock) return mock.getUsage();
    try {
      return await live.usage();
    } on AppException catch (error) {
      // Same "no subscription yet" shape as subscription() above — no
      // usage to report is not a failure.
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<SubscriptionInfo> _withPlanName(SubscriptionInfo sub) async {
    if (sub.planId == null) return sub;
    try {
      final allPlans = await plans();
      return sub.withPlanName(allPlans);
    } catch (_) {
      return sub;
    }
  }

  // ---- Devices -----------------------------------------------------------

  Future<DeviceItem> registerDevice({
    required String platform,
    required String name,
  }) {
    if (useMock) {
      return mock.registerDevice(platform: platform, name: name);
    }
    return live.registerDevice(platform: platform, name: name);
  }

  Future<List<DeviceItem>> devices() async {
    // Core's list includes revoked devices too (with revoked_at set)
    // rather than dropping them — left unfiltered, a device the user just
    // revoked doesn't disappear from Settings ▸ Devices, it just re-sorts
    // (often to the bottom, since its updated_at just changed), which
    // reads as "revoke doesn't actually work."
    final items = (useMock ? await mock.getDevices() : await live.devices())
        .where((d) => !d.isRevoked)
        .toList();
    // Core's device list has no `current` flag — mark whichever entry
    // matches this install's own registered device id instead.
    final ownId = await SecureStore.read(SecureStore.deviceId);
    if (ownId == null) return items;
    return [
      for (final d in items)
        if (d.id == ownId && !d.current)
          DeviceItem(
            id: d.id,
            publicId: d.publicId,
            platform: d.platform,
            name: d.name,
            current: true,
            createdAt: d.createdAt,
            lastSeenAt: d.lastSeenAt,
            revokedAt: d.revokedAt,
          )
        else
          d,
    ];
  }

  Future<void> revokeDevice(String deviceId) {
    if (useMock) return mock.revokeDevice(deviceId);
    return live.revokeDevice(deviceId);
  }

  // ---- Locations -----------------------------------------------------------

  Future<List<LocationItem>> locations() {
    if (useMock) return mock.getLocations();
    return live.locations();
  }

  // ---- Access grants -------------------------------------------------------

  Future<AccessGrant> createAccessGrant({
    required String nodeId,
    required String deviceId,
    String protocol = 'wireguard',
  }) {
    if (useMock) {
      return mock.createAccessGrant(nodeId: nodeId, deviceId: deviceId, protocol: protocol);
    }
    return live.createAccessGrant(nodeId: nodeId, deviceId: deviceId, protocol: protocol);
  }

  Future<AccessGrant> revokeAccessGrant(String grantId) {
    if (useMock) return mock.revokeAccessGrant(grantId);
    return live.revokeAccessGrant(grantId);
  }

  Future<VpnConfigResponse> grantConfig(String grantId) {
    if (useMock) return mock.grantConfig(grantId);
    return live.grantConfig(grantId);
  }

  Future<ClientConfig> clientConfig() async {
    // Core has no `/client-config`-style endpoint — the maintenance/
    // minimum-version gate is a mock-only concept for now.
    if (!useMock) return ClientConfig.fallback;
    try {
      return await mock.config();
    } on AppException {
      return ClientConfig.fallback;
    }
  }
}

class RefreshingApi {
  RefreshingApi(this.client);
  final ApiClient client;
}
