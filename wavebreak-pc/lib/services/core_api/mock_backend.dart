import 'dart:async';

import '../../core/errors/app_exception.dart';
import 'models.dart';

/// In-memory Core stand-in for UI development and tests.
/// Never used when USE_MOCK_API=false.
///
/// Shapes returned here mirror the real Core API's *models*, not its raw
/// JSON — the mock hands back typed objects directly rather than going
/// through `fromJson`. One deliberate difference from live Core: grant
/// config here resolves as `ready` immediately (with harmless placeholder
/// WireGuard material) instead of staying `pending_runtime_config`, so the
/// demo experience keeps showing an instant, satisfying "connected" state
/// rather than the real backend's current "configuration is being
/// prepared" wait.
class MockCoreBackend {
  MockCoreBackend();

  String? accessToken = 'mock-access';
  String? refreshToken = 'mock-refresh';
  bool refreshShouldFail = false;
  bool forceUnauthorized = false;
  bool deviceRevoked = false;
  String email = 'user@wavebreak.app';

  final List<Plan> plans = const [
    Plan(
      id: 'plan-monthly',
      code: 'wavebreak-monthly',
      name: 'WAVEBREAK Monthly',
      priceMinor: 900,
      currency: 'USD',
      interval: 'month',
      deviceLimit: 5,
      concurrentConnectionLimit: 5,
      sortOrder: 10,
    ),
  ];

  SubscriptionInfo subscription = const SubscriptionInfo(
    id: 'sub-1',
    status: 'active',
    planId: 'plan-monthly',
    planName: 'WAVEBREAK Monthly',
    deviceLimit: 5,
  );

  List<LocationItem> locations = const [
    LocationItem(
      id: 'tr-istanbul',
      countryCode: 'TR',
      country: 'Turkey',
      city: 'Istanbul',
      available: true,
      pingMs: 34,
    ),
    LocationItem(
      id: 'nl-amsterdam',
      countryCode: 'NL',
      country: 'Netherlands',
      city: 'Amsterdam',
      available: true,
      pingMs: 62,
    ),
    LocationItem(
      id: 'fi-helsinki',
      countryCode: 'FI',
      country: 'Finland',
      city: 'Helsinki',
      available: true,
      pingMs: 58,
    ),
  ];

  final List<DeviceItem> _devices = [];
  final Map<String, AccessGrant> _grants = {};
  int _grantSeq = 0;

  Future<TokenPair> login(String email, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (email.isEmpty || password.length < 6) {
      throw AppException(AppErrorKind.invalidCredentials);
    }
    this.email = email;
    accessToken = 'mock-access';
    refreshToken = 'mock-refresh';
    return TokenPair(accessToken: accessToken!, refreshToken: refreshToken!, expiresIn: 900);
  }

  Future<TokenPair> register(String email, String password) => login(email, password);

  Future<TokenPair> refresh() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (refreshShouldFail) {
      throw AppException(AppErrorKind.sessionExpired);
    }
    accessToken = 'mock-access-refreshed';
    return TokenPair(accessToken: accessToken!, refreshToken: refreshToken!, expiresIn: 900);
  }

  Future<UserProfile> me() async {
    _guard();
    return UserProfile(id: 'user-1', email: email);
  }

  Future<BootstrapResponse> bootstrap() async {
    _guard();
    return BootstrapResponse(
      user: UserProfile(id: 'user-1', email: email),
      subscription: subscription,
      devices: List.unmodifiable(_devices),
      plans: plans,
      nodes: locations,
      grants: List.unmodifiable(_grants.values),
    );
  }

  Future<List<Plan>> getPlans() async {
    _guard();
    return plans;
  }

  Future<SubscriptionInfo> createSubscription(String planId) async {
    _guard();
    subscription = SubscriptionInfo(
      id: 'sub-1',
      status: 'active',
      planId: planId,
      planName: plans.where((p) => p.id == planId).firstOrNull?.name ?? 'WAVEBREAK',
      deviceLimit: plans.where((p) => p.id == planId).firstOrNull?.deviceLimit,
    );
    return subscription;
  }

  Future<SubscriptionInfo> getSubscription() async {
    _guard();
    return subscription;
  }

  Future<UsageSummary> getUsage() async {
    _guard();
    return UsageSummary(
      subscriptionId: subscription.id ?? 'mock',
      bytesUp: 1200000000,
      bytesDown: 34500000000,
      bytesTotal: 35700000000,
      limitBytes: subscription.trafficLimitBytes,
    );
  }

  Future<List<LocationItem>> getLocations() async {
    _guard();
    return locations;
  }

  Future<DeviceItem> registerDevice({
    required String platform,
    required String name,
  }) async {
    _guard();
    final device = DeviceItem(
      id: 'device-${_devices.length + 1}',
      publicId: 'device-public-${_devices.length + 1}',
      platform: platform,
      name: name,
      current: true,
    );
    _devices.add(device);
    return device;
  }

  Future<List<DeviceItem>> getDevices() async {
    _guard();
    // No fallback seed here — `registerDevice` always runs during session
    // bootstrap before anything reads this list, and it assigns the id
    // `SecureStore.deviceId` is cached against. A second, independent id
    // scheme here (as this used to have) can race it and mint a device
    // under a different id than the one the app already registered as
    // "this device", which is exactly why the current device stopped
    // being recognized in its own list.
    return List.unmodifiable(_devices);
  }

  Future<void> revokeDevice(String deviceId) async {
    _guard();
    _devices.removeWhere((d) => d.id == deviceId);
  }

  Future<AccessGrant> createAccessGrant({
    required String nodeId,
    required String deviceId,
    required String protocol,
  }) async {
    _guard();
    if (subscription.isExpired || !subscription.isActive) {
      throw AppException(AppErrorKind.subscriptionRequired);
    }
    _grantSeq += 1;
    final grant = AccessGrant(
      id: 'grant-$_grantSeq',
      nodeId: nodeId,
      deviceId: deviceId,
      protocol: protocol,
      status: 'active',
      createdAt: DateTime.now(),
    );
    _grants[grant.id] = grant;
    return grant;
  }

  Future<AccessGrant> revokeAccessGrant(String grantId) async {
    _guard();
    final existing = _grants[grantId];
    if (existing == null) throw AppException(AppErrorKind.locationUnavailable);
    final revoked = AccessGrant(
      id: existing.id,
      nodeId: existing.nodeId,
      deviceId: existing.deviceId,
      protocol: existing.protocol,
      status: 'revoked',
      createdAt: existing.createdAt,
      revokedAt: DateTime.now(),
      revokedReason: 'user',
    );
    _grants[grantId] = revoked;
    return revoked;
  }

  Future<VpnConfigResponse> grantConfig(String grantId) async {
    _guard();
    final grant = _grants[grantId];
    if (grant == null) throw AppException(AppErrorKind.locationUnavailable);
    final node = locations.where((l) => l.id == grant.nodeId).firstOrNull;
    return VpnConfigResponse(
      grant: grant,
      node: node,
      configStatus: 'ready',
      configVersion: 1,
      wireguard: const WireguardConfig(
        interface: WireguardInterfaceConfig(
          privateKey: 'mock-private-key',
          address: '10.77.0.2/32',
          dns: ['1.1.1.1', '1.0.0.1'],
          mtu: 1420,
        ),
        peer: WireguardPeerConfig(
          publicKey: 'mock-server-public-key',
          endpoint: 'mock.wavebreak.test:51820',
          allowedIps: ['0.0.0.0/0', '::/0'],
          persistentKeepalive: 25,
        ),
      ),
    );
  }

  Future<ClientConfig> config() async => ClientConfig.fallback;

  void _guard() {
    if (deviceRevoked) throw AppException(AppErrorKind.accessDenied);
    if (forceUnauthorized) throw AppException(AppErrorKind.sessionExpired);
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
