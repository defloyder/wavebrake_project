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
    String? language,
    CancelToken? cancelToken,
  }) {
    if (useMock) return mock.register(email, password);
    return live.register(
        email: email,
        password: password,
        language: language,
        cancelToken: cancelToken);
  }

  // Email verification. The mock backend has none: sign-up there signs in
  // directly, so these only ever run against Core.
  Future<TokenPair> verifyEmail({required String email, required String code}) {
    if (useMock) return mock.login(email, '');
    return live.verifyEmail(email: email, code: code);
  }

  Future<void> resendEmailCode(
      {required String email, String? language}) async {
    if (useMock) return;
    await live.resendEmailCode(email: email, language: language);
  }

  Future<void> sendMyEmailCode({String? language}) async {
    if (useMock) return;
    await live.sendMyEmailCode(language: language);
  }

  Future<void> verifyMyEmail(String code) async {
    if (useMock) return;
    await live.verifyMyEmail(code);
  }

  Future<TokenPair> refresh(String refreshToken) {
    if (useMock) return mock.refresh();
    return live.refresh(refreshToken);
  }

  Future<void> logout(String refreshToken) async {
    if (useMock) return;
    await live.logout(refreshToken);
  }

  /// Core emails a one-time link to wavebreak.com.tr/reset-password (and
  /// answers the same whether or not the account exists).
  Future<void> forgotPassword(String email, {String? language}) async {
    if (useMock) return;
    await live.requestPasswordReset(email: email, language: language);
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
      if (error.statusCode == 404) {
        return const SubscriptionInfo(status: 'none');
      }
      rethrow;
    }
  }

  /// The account's own VPN access, or null when it has none: no active
  /// subscription (Core: 404 SUBSCRIPTION_NOT_FOUND / 422
  /// SUBSCRIPTION_NOT_ACTIVE, e.g. past_due). The mock backend has no
  /// real credentials to hand out.
  Future<PersonalAccess?> personalAccess() async {
    if (useMock) return null;
    try {
      return await live.myAccess();
    } on AppException catch (error) {
      if (error.statusCode == 404 || error.statusCode == 422) return null;
      rethrow;
    }
  }

  /// Share code for the account's own subscription; the mock backend has
  /// none to give.
  Future<ShareInfo> myShare() {
    if (useMock) {
      return Future.error(
          AppException(AppErrorKind.subscriptionRequired, statusCode: 404));
    }
    return live.myShare();
  }

  Future<SharingOverview> sharing() {
    if (useMock) return Future.value(SharingOverview.empty);
    return live.mySharing();
  }

  Future<SharedAccess> redeemShare({
    required String token,
    required String deviceName,
    required String platform,
  }) {
    if (useMock) return Future.error(AppException(AppErrorKind.unavailable));
    return live.redeemShare(
        token: token, deviceName: deviceName, platform: platform);
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
      return mock.createAccessGrant(
          nodeId: nodeId, deviceId: deviceId, protocol: protocol);
    }
    return live.createAccessGrant(
        nodeId: nodeId, deviceId: deviceId, protocol: protocol);
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
