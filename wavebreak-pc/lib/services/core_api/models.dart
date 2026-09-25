class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    this.role = 'user',
    this.status = 'active',
  });

  final String id;
  final String email;
  final String role;
  final String status;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final nested =
        json['user'] is Map<String, dynamic> ? json['user'] as Map<String, dynamic> : json;
    return UserProfile(
      id: (nested['id'] ?? nested['user_id'] ?? '').toString(),
      email: (nested['email'] ?? '').toString(),
      role: (nested['role'] ?? 'user').toString(),
      status: (nested['status'] ?? 'active').toString(),
    );
  }
}

class TokenPair {
  const TokenPair({
    required this.accessToken,
    required this.refreshToken,
    this.tokenType = 'Bearer',
    this.expiresIn,
  });

  final String accessToken;
  final String refreshToken;
  final String tokenType;

  /// Access token lifetime in seconds (Core defaults to 900 = 15 minutes).
  final int? expiresIn;

  factory TokenPair.fromJson(Map<String, dynamic> json) {
    final nested = json['tokens'] is Map<String, dynamic>
        ? json['tokens'] as Map<String, dynamic>
        : json;
    return TokenPair(
      accessToken: (nested['access_token'] ?? nested['accessToken'] ?? '')
          .toString(),
      refreshToken: (nested['refresh_token'] ?? nested['refreshToken'] ?? '')
          .toString(),
      tokenType: (nested['token_type'] ?? 'Bearer').toString(),
      expiresIn: _asInt(nested['expires_in']),
    );
  }
}

/// A billing plan Core offers (`GET /v1/plans`). `priceMinor` is in minor
/// currency units — e.g. `priceMinor: 900, currency: "USD"` is $9.00.
class Plan {
  const Plan({
    required this.id,
    required this.code,
    required this.name,
    required this.priceMinor,
    required this.currency,
    required this.interval,
    this.deviceLimit,
    this.trafficLimitBytes,
    this.concurrentConnectionLimit,
    this.isActive = true,
    this.isPublic = true,
    this.sortOrder = 0,
  });

  final String id;
  final String code;
  final String name;
  final int priceMinor;
  final String currency;
  final String interval;
  final int? deviceLimit;
  final int? trafficLimitBytes;
  final int? concurrentConnectionLimit;
  final bool isActive;
  final bool isPublic;
  final int sortOrder;

  double get priceMajor => priceMinor / 100;

  factory Plan.fromJson(Map<String, dynamic> json) {
    return Plan(
      id: (json['id'] ?? '').toString(),
      code: (json['code'] ?? '').toString(),
      name: (json['name'] ?? json['code'] ?? 'WAVEBREAK').toString(),
      priceMinor: _asInt(json['price_minor']) ?? 0,
      currency: (json['currency'] ?? 'USD').toString(),
      interval: (json['interval'] ?? 'month').toString(),
      deviceLimit: _asInt(json['device_limit']),
      trafficLimitBytes: _asInt(json['traffic_limit_bytes']),
      concurrentConnectionLimit: _asInt(json['concurrent_connection_limit']),
      isActive: json['is_active'] != false,
      isPublic: json['is_public'] != false,
      sortOrder: _asInt(json['sort_order']) ?? 0,
    );
  }

  /// Round-trips with [Plan.fromJson] — used only to cache the last
  /// successful fetch on-device for offline fallback (see
  /// features/shared/data_providers.dart), never sent anywhere.
  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'price_minor': priceMinor,
        'currency': currency,
        'interval': interval,
        'device_limit': deviceLimit,
        'traffic_limit_bytes': trafficLimitBytes,
        'concurrent_connection_limit': concurrentConnectionLimit,
        'is_active': isActive,
        'is_public': isPublic,
        'sort_order': sortOrder,
      };
}

class SubscriptionInfo {
  const SubscriptionInfo({
    required this.status,
    this.id,
    this.planId,
    this.planName = 'WAVEBREAK',
    this.expiresAt,
    this.deviceLimit,
    this.trafficLimitBytes,
    this.manageUrl,
  });

  final String? id;
  final String status;
  final String? planId;
  final String planName;
  final DateTime? expiresAt;
  final int? deviceLimit;
  final int? trafficLimitBytes;
  final String? manageUrl;

  bool get isActive =>
      status.toLowerCase() == 'active' || status.toLowerCase() == 'trialing';

  bool get isExpired =>
      status.toLowerCase() == 'expired' ||
      status.toLowerCase() == 'canceled' ||
      (expiresAt != null && expiresAt!.isBefore(DateTime.now()));

  int? get daysRemaining {
    if (expiresAt == null) return null;
    final diff = expiresAt!.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  /// Core's subscription object only carries `plan_id`, not a display
  /// name — call this with the fetched `/v1/plans` list to attach one.
  SubscriptionInfo withPlanName(List<Plan> plans) {
    if (planId == null) return this;
    final match = plans.where((p) => p.id == planId);
    if (match.isEmpty) return this;
    return SubscriptionInfo(
      id: id,
      status: status,
      planId: planId,
      planName: match.first.name,
      expiresAt: expiresAt,
      deviceLimit: deviceLimit,
      trafficLimitBytes: trafficLimitBytes,
      manageUrl: manageUrl,
    );
  }

  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) {
    final nested = json['subscription'] is Map<String, dynamic>
        ? json['subscription'] as Map<String, dynamic>
        : json;
    return SubscriptionInfo(
      id: nested['id']?.toString(),
      status: (nested['status'] ?? 'unknown').toString(),
      planId: nested['plan_id']?.toString(),
      // A couple of non-Core-shaped keys are kept as a fallback so this
      // still reads sensibly against the mock backend's simpler shape.
      planName:
          (nested['plan_name'] ?? nested['plan'] ?? nested['name'] ?? 'WAVEBREAK')
              .toString(),
      expiresAt: _parseDate(nested['current_period_ends_at'] ?? nested['expires_at']),
      deviceLimit: _asInt(nested['device_limit_snapshot'] ?? nested['device_limit']),
      trafficLimitBytes:
          _asInt(nested['traffic_limit_bytes_snapshot'] ?? nested['traffic_limit_bytes']),
      manageUrl: nested['manage_url'] as String?,
    );
  }

  /// Round-trips with [SubscriptionInfo.fromJson] — offline cache only.
  Map<String, dynamic> toJson() => {
        'id': id,
        'status': status,
        'plan_id': planId,
        'plan_name': planName,
        'current_period_ends_at': expiresAt?.toIso8601String(),
        'device_limit_snapshot': deviceLimit,
        'traffic_limit_bytes_snapshot': trafficLimitBytes,
        'manage_url': manageUrl,
      };
}

/// `GET /v1/me/usage` — traffic used this billing period, keyed on the
/// subscription itself rather than any particular access grant, so it's
/// available regardless of which (or whether any) node the user is
/// actually connected through right now.
class UsageSummary {
  const UsageSummary({
    required this.subscriptionId,
    required this.bytesUp,
    required this.bytesDown,
    required this.bytesTotal,
    this.limitBytes,
  });

  final String subscriptionId;
  final int bytesUp;
  final int bytesDown;
  final int bytesTotal;
  final int? limitBytes;

  factory UsageSummary.fromJson(Map<String, dynamic> json) {
    return UsageSummary(
      subscriptionId: (json['subscription_id'] ?? '').toString(),
      bytesUp: _asInt(json['bytes_up']) ?? 0,
      bytesDown: _asInt(json['bytes_down']) ?? 0,
      bytesTotal: _asInt(json['bytes_total']) ?? 0,
      limitBytes: _asInt(json['limit_bytes']),
    );
  }

  /// Round-trips with [UsageSummary.fromJson] — offline cache only.
  Map<String, dynamic> toJson() => {
        'subscription_id': subscriptionId,
        'bytes_up': bytesUp,
        'bytes_down': bytesDown,
        'bytes_total': bytesTotal,
        'limit_bytes': limitBytes,
      };
}

/// A Core node/location (`GET /v1/locations`). Core doesn't send a
/// human country/city pair — `region` is the location's ISO-ish
/// country code (e.g. `"TR"`) and `code` is the node's own identifier
/// (e.g. `"TR-IST-01"`), which doubles as the display label since
/// there's no separate city name in the contract.
/// A server-provided recipe for testing reachability to a specific node
/// *without* an active VPN tunnel — a raw TCP connect to [host]:[port]
/// (or one of [testTargets], reachable *through* the node once a tunnel
/// exists) is what Core actually means by "test this location's
/// connection." Comes from the node's own `connection_test` object; not
/// something the client invents an endpoint for.
class ConnectionTest {
  const ConnectionTest({
    required this.host,
    required this.port,
    this.nodeId,
    this.nodeCode,
    this.protocol,
    this.transport,
    this.security,
    this.sni,
    this.timeoutMs,
    this.testTargets = const [],
  });

  final String host;
  final int port;
  final String? nodeId;
  final String? nodeCode;
  final String? protocol;
  final String? transport;
  final String? security;
  final String? sni;
  final int? timeoutMs;
  final List<String> testTargets;

  factory ConnectionTest.fromJson(Map<String, dynamic> json) {
    return ConnectionTest(
      host: (json['host'] ?? '').toString(),
      port: _asInt(json['port']) ?? 0,
      nodeId: json['node_id'] as String?,
      nodeCode: json['node_code'] as String?,
      protocol: json['protocol'] as String?,
      transport: json['transport'] as String?,
      security: json['security'] as String?,
      sni: json['sni'] as String?,
      timeoutMs: _asInt(json['timeout_ms']),
      testTargets:
          (json['test_targets'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }

  /// Round-trips with [ConnectionTest.fromJson] — offline cache only.
  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'node_id': nodeId,
        'node_code': nodeCode,
        'protocol': protocol,
        'transport': transport,
        'security': security,
        'sni': sni,
        'timeout_ms': timeoutMs,
        'test_targets': testTargets,
      };
}

class LocationItem {
  const LocationItem({
    required this.id,
    required this.countryCode,
    required this.country,
    required this.city,
    required this.available,
    this.isAuto = false,
    this.pingMs,
    this.isCustom = false,
    this.rawLink,
    this.connectionTest,
  });

  final String id;
  final String countryCode;
  final String country;
  final String city;
  final bool available;
  final bool isAuto;
  final int? pingMs;

  /// True for a location the user added themselves by pasting a
  /// subscription link, rather than one WAVEBREAK Core assigned.
  final bool isCustom;
  final String? rawLink;

  /// Present on real Core locations (never on mock/custom ones) — lets
  /// the app test reachability to this specific node before ever
  /// creating an access grant or opening a tunnel.
  final ConnectionTest? connectionTest;

  static const auto = LocationItem(
    id: 'auto',
    countryCode: 'AUTO',
    country: 'Auto',
    city: 'Fastest location',
    available: true,
    isAuto: true,
  );

  factory LocationItem.fromJson(Map<String, dynamic> json) {
    // Real Core's rich location shape — the `locations` array (not the
    // legacy flat `nodes` one) in /v1/locations, bootstrap, and a grant
    // config's `location`/`vless.location`. Telltale fields: `node_code`
    // and/or `connection_test`, which the other two shapes never have.
    if (json['node_code'] != null || json['connection_test'] != null) {
      final region = (json['region'] ?? '').toString().toUpperCase();
      return LocationItem(
        id: (json['id'] ?? json['node_id'] ?? '').toString(),
        countryCode: region,
        country: (json['country'] ?? region).toString(),
        city: (json['city'] ?? json['node_code'] ?? '').toString(),
        available: json['online'] == true ||
            (json['status'] ?? '').toString().toLowerCase() == 'online',
        connectionTest: json['connection_test'] is Map
            ? ConnectionTest.fromJson((json['connection_test'] as Map).cast<String, dynamic>())
            : null,
      );
    }

    // Mock backend / legacy shape: explicit country + city fields.
    if (json['country'] != null || json['city'] != null) {
      final country = (json['country'] ?? '').toString();
      final city = (json['city'] ?? '').toString();
      final code = (json['country_code'] ?? json['code'] ?? '').toString();
      return LocationItem(
        id: (json['id'] ?? '$code-$city').toString(),
        countryCode: code.toUpperCase(),
        country: country,
        city: city,
        available: json['available'] != false,
        pingMs: json['ping_ms'] is int ? json['ping_ms'] as int : null,
      );
    }

    // Real Core's legacy flat node shape: { id, code, region, status, ... }
    // — still returned as `nodes` alongside the rich `locations` array,
    // kept here only as a fallback for a caller that hasn't switched over.
    final region = (json['region'] ?? '').toString().toUpperCase();
    final code = (json['code'] ?? '').toString();
    return LocationItem(
      id: (json['id'] ?? code).toString(),
      countryCode: region,
      country: region,
      city: code,
      available: (json['status'] ?? '').toString().toLowerCase() == 'online',
    );
  }

  /// Round-trips with [LocationItem.fromJson] — always encoded in the
  /// "rich Core shape" (carries `node_code` so it decodes back through
  /// that branch) regardless of which branch originally produced this
  /// instance. Offline cache only.
  Map<String, dynamic> toJson() => {
        'id': id,
        'node_id': id,
        'node_code': city,
        'region': countryCode,
        'country': country,
        'city': city,
        'online': available,
        'connection_test': connectionTest?.toJson(),
      };
}

class DeviceItem {
  const DeviceItem({
    required this.id,
    required this.publicId,
    required this.platform,
    required this.name,
    this.current = false,
    this.createdAt,
    this.lastSeenAt,
    this.revokedAt,
  });

  /// Core's internal device id — this is the `device_id` an access grant
  /// is created with. Distinct from [publicId].
  final String id;
  final String publicId;
  final String platform;
  final String name;
  final bool current;
  final DateTime? createdAt;
  final DateTime? lastSeenAt;
  final DateTime? revokedAt;

  bool get isRevoked => revokedAt != null;

  factory DeviceItem.fromJson(Map<String, dynamic> json) {
    return DeviceItem(
      id: (json['id'] ?? '').toString(),
      publicId: (json['device_public_id'] ?? json['id'] ?? '').toString(),
      platform: (json['platform'] ?? '').toString(),
      name: (json['name'] ?? 'Device').toString(),
      current: json['current'] == true,
      createdAt: _parseDate(json['created_at']),
      lastSeenAt: _parseDate(json['last_seen_at']),
      revokedAt: _parseDate(json['revoked_at']),
    );
  }

  /// Round-trips with [DeviceItem.fromJson] — offline cache only.
  Map<String, dynamic> toJson() => {
        'id': id,
        'device_public_id': publicId,
        'platform': platform,
        'name': name,
        'current': current,
        'created_at': createdAt?.toIso8601String(),
        'last_seen_at': lastSeenAt?.toIso8601String(),
        'revoked_at': revokedAt?.toIso8601String(),
      };
}

/// A server-side permission to access one node from one device
/// (`POST /v1/access/grants`). `id` is what the config-polling endpoint
/// is keyed on.
class AccessGrant {
  const AccessGrant({
    required this.id,
    required this.nodeId,
    required this.deviceId,
    required this.protocol,
    required this.status,
    this.expiresAt,
    this.desiredRevision,
    this.createdAt,
    this.revokedAt,
    this.revokedReason,
  });

  final String id;
  final String nodeId;
  final String deviceId;
  final String protocol;
  final String status;
  final DateTime? expiresAt;
  final int? desiredRevision;
  final DateTime? createdAt;
  final DateTime? revokedAt;
  final String? revokedReason;

  bool get isActive => status.toLowerCase() == 'active';

  factory AccessGrant.fromJson(Map<String, dynamic> json) {
    return AccessGrant(
      id: (json['id'] ?? '').toString(),
      nodeId: (json['node_id'] ?? '').toString(),
      deviceId: (json['device_id'] ?? '').toString(),
      protocol: (json['protocol'] ?? 'wireguard').toString(),
      status: (json['status'] ?? 'unknown').toString(),
      expiresAt: _parseDate(json['expires_at']),
      desiredRevision: _asInt(json['desired_revision']),
      createdAt: _parseDate(json['created_at']),
      revokedAt: _parseDate(json['revoked_at']),
      revokedReason: json['revoked_reason'] as String?,
    );
  }
}

class WireguardInterfaceConfig {
  const WireguardInterfaceConfig({
    this.privateKey,
    this.address,
    this.dns = const [],
    this.mtu,
  });

  final String? privateKey;
  final String? address;
  final List<String> dns;
  final int? mtu;

  factory WireguardInterfaceConfig.fromJson(Map<String, dynamic> json) {
    return WireguardInterfaceConfig(
      privateKey: json['private_key'] as String?,
      address: json['address'] as String?,
      dns: (json['dns'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      mtu: _asInt(json['mtu']),
    );
  }
}

class WireguardPeerConfig {
  const WireguardPeerConfig({
    this.publicKey,
    this.presharedKey,
    this.endpoint,
    this.allowedIps = const [],
    this.persistentKeepalive,
  });

  final String? publicKey;
  final String? presharedKey;
  final String? endpoint;
  final List<String> allowedIps;
  final int? persistentKeepalive;

  factory WireguardPeerConfig.fromJson(Map<String, dynamic> json) {
    return WireguardPeerConfig(
      publicKey: json['public_key'] as String?,
      presharedKey: json['preshared_key'] as String?,
      endpoint: json['endpoint'] as String?,
      allowedIps:
          (json['allowed_ips'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      persistentKeepalive: _asInt(json['persistent_keepalive']),
    );
  }
}

class WireguardConfig {
  const WireguardConfig({required this.interface, required this.peer});

  final WireguardInterfaceConfig interface;
  final WireguardPeerConfig peer;

  factory WireguardConfig.fromJson(Map<String, dynamic> json) {
    return WireguardConfig(
      interface: WireguardInterfaceConfig.fromJson(
        (json['interface'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      peer: WireguardPeerConfig.fromJson(
        (json['peer'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );
  }

  /// True once every field the native tunnel adapter actually needs is
  /// present — Core's `pending_runtime_config` state leaves peer material
  /// null, so `config_status` alone isn't quite enough to trust this.
  bool get hasUsablePeer =>
      peer.publicKey != null && peer.publicKey!.isNotEmpty && peer.endpoint != null;
}

/// The pilot Core's actual live protocol — a ready-to-use VLESS REALITY
/// link plus its parsed pieces, returned alongside (not instead of)
/// [VpnConfigResponse.connectionUrl]. See docs/mobile-desktop-pilot-testing.md.
class VlessConfig {
  const VlessConfig({
    this.clientId,
    this.label,
    this.protocol,
    this.security,
    this.network,
    this.flow,
    this.server,
    this.port,
    this.uri,
  });

  final String? clientId;
  final String? label;
  final String? protocol;
  final String? security;
  final String? network;
  final String? flow;
  final String? server;
  final int? port;

  /// The direct (non-CDN) share link for this exact `vless` block — plain
  /// TCP + REALITY, no WebSocket wrapping. Distinct from
  /// [VpnConfigResponse.connectionUrl]/[shareUrl], which Core now defaults
  /// to the CDN-fronted WebSocket+TLS variant instead (see
  /// docs/vpn-config-contract.md's `vless_cdn`).
  final String? uri;

  factory VlessConfig.fromJson(Map<String, dynamic> json) {
    return VlessConfig(
      clientId: json['client_id'] as String?,
      label: json['label'] as String?,
      protocol: json['protocol'] as String?,
      security: json['security'] as String?,
      network: json['network'] as String?,
      flow: json['flow'] as String?,
      server: json['server'] as String?,
      port: _asInt(json['port']),
      uri: json['uri'] as String?,
    );
  }
}

/// Response of `GET /v1/access/grants/{grantID}/config`. Two backends, two
/// shapes: the mock/legacy WireGuard contract ([wireguard], still null
/// until `config_status` is `"ready"`), and the pilot's real VLESS REALITY
/// contract ([connectionUrl] + [vless]). Both can't be assumed present —
/// [isReady] and the caller must check which one actually came back rather
/// than force-unwrapping either. See docs/vpn-config-contract.md and
/// docs/mobile-desktop-pilot-testing.md.
class VpnConfigResponse {
  const VpnConfigResponse({
    required this.grant,
    required this.configStatus,
    this.node,
    this.location,
    this.device,
    this.configVersion,
    this.wireguard,
    this.connectionUrl,
    this.shareUrl,
    this.vless,
    this.rawConfig,
    this.warnings = const [],
    this.routingPolicy,
    this.bytesUp,
    this.bytesDown,
  });

  final AccessGrant grant;
  /// Legacy flat node info — prefer [location] (richer: real country/
  /// city/online flag and a [ConnectionTest]) when it's present.
  final LocationItem? node;
  final LocationItem? location;
  final DeviceItem? device;
  final String configStatus;
  final int? configVersion;
  final WireguardConfig? wireguard;
  final String? connectionUrl;
  final String? shareUrl;
  final VlessConfig? vless;
  final String? rawConfig;
  final List<String> warnings;

  /// Core's `smart-routing-v1` policy (see docs/mobile-desktop-api.md) —
  /// keeps RU-addressed traffic direct and everything else through the
  /// protected tunnel. Only WAVEBREAK's own clients apply this; a plain
  /// share link handed to a third-party app has no way to carry it.
  final Map<String, dynamic>? routingPolicy;

  /// Bytes used so far this billing period. Only the grant-config endpoint
  /// (this response) carries live usage — `/v1/subscriptions/current`
  /// only has the plan's traffic *limit*, never what's actually been used
  /// — so this is the sole source for "how much is left" and is only as
  /// fresh as the last successful connect/reconnect.
  final int? bytesUp;
  final int? bytesDown;

  bool get hasUsableVless => connectionUrl != null && connectionUrl!.isNotEmpty;

  bool get isReady =>
      configStatus == 'ready' &&
      ((wireguard?.hasUsablePeer ?? false) || hasUsableVless);

  factory VpnConfigResponse.fromJson(Map<String, dynamic> json) {
    return VpnConfigResponse(
      grant: AccessGrant.fromJson(
        (json['grant'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      node: json['node'] is Map
          ? LocationItem.fromJson((json['node'] as Map).cast<String, dynamic>())
          : null,
      location: json['location'] is Map
          ? LocationItem.fromJson((json['location'] as Map).cast<String, dynamic>())
          : null,
      device: json['device'] is Map
          ? DeviceItem.fromJson((json['device'] as Map).cast<String, dynamic>())
          : null,
      configStatus: (json['config_status'] ?? 'pending_runtime_config').toString(),
      configVersion: _asInt(json['config_version']),
      wireguard: json['wireguard'] is Map
          ? WireguardConfig.fromJson((json['wireguard'] as Map).cast<String, dynamic>())
          : null,
      connectionUrl: json['connection_url'] as String?,
      shareUrl: json['share_url'] as String?,
      vless: json['vless'] is Map
          ? VlessConfig.fromJson((json['vless'] as Map).cast<String, dynamic>())
          : null,
      rawConfig: json['raw_config'] as String?,
      warnings: (json['warnings'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      routingPolicy: json['routing_policy'] is Map
          ? (json['routing_policy'] as Map).cast<String, dynamic>()
          : null,
      bytesUp: _asInt(json['bytes_up']),
      bytesDown: _asInt(json['bytes_down']),
    );
  }
}

class ClientConfig {
  const ClientConfig({
    this.minimumSupportedVersion,
    this.recommendedVersion,
    this.supportTelegram,
    this.supportEmail,
    this.privacyUrl,
    this.termsUrl,
    this.websiteUrl,
    this.helpUrl,
    this.maintenance = false,
  });

  final String? minimumSupportedVersion;
  final String? recommendedVersion;
  final String? supportTelegram;
  final String? supportEmail;
  final String? privacyUrl;
  final String? termsUrl;
  final String? websiteUrl;
  final String? helpUrl;
  final bool maintenance;

  factory ClientConfig.fromJson(Map<String, dynamic> json) {
    return ClientConfig(
      minimumSupportedVersion: json['minimum_supported_version'] as String?,
      recommendedVersion: json['recommended_version'] as String?,
      supportTelegram: json['support_telegram'] as String?,
      supportEmail: json['support_email'] as String?,
      privacyUrl: json['privacy_url'] as String?,
      termsUrl: json['terms_url'] as String?,
      websiteUrl: json['website_url'] as String?,
      helpUrl: json['help_url'] as String?,
      maintenance: json['maintenance'] == true,
    );
  }

  static const fallback = ClientConfig(
    privacyUrl: 'https://wavebreak.app/privacy',
    termsUrl: 'https://wavebreak.app/terms',
    websiteUrl: 'https://wavebreak.app',
    supportEmail: 'support@wavebreak.app',
  );
}

/// `GET /v1/client/bootstrap` — one call that hydrates the whole cabinet
/// after login. Individual screens still use their own focused endpoints
/// (`/v1/plans`, `/v1/locations`, ...) for refresh/pagination, but this is
/// the recommended first read.
class BootstrapResponse {
  const BootstrapResponse({
    required this.user,
    this.subscription,
    this.devices = const [],
    this.plans = const [],
    this.nodes = const [],
    this.grants = const [],
  });

  final UserProfile user;
  final SubscriptionInfo? subscription;
  final List<DeviceItem> devices;
  final List<Plan> plans;
  final List<LocationItem> nodes;
  final List<AccessGrant> grants;

  factory BootstrapResponse.fromJson(Map<String, dynamic> json) {
    final overview = (json['overview'] as Map?)?.cast<String, dynamic>() ?? const {};
    return BootstrapResponse(
      user: UserProfile.fromJson(
        (json['user'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      subscription: overview['subscription'] is Map
          ? SubscriptionInfo.fromJson(
              (overview['subscription'] as Map).cast<String, dynamic>())
          : null,
      devices: ((overview['devices'] ?? json['devices']) as List?)
              ?.whereType<Map>()
              .map((e) => DeviceItem.fromJson(e.cast<String, dynamic>()))
              .toList() ??
          const [],
      plans: (json['plans'] as List?)
              ?.whereType<Map>()
              .map((e) => Plan.fromJson(e.cast<String, dynamic>()))
              .toList() ??
          const [],
      nodes: ((json['locations'] ?? json['nodes']) as List?)
              ?.whereType<Map>()
              .map((e) => LocationItem.fromJson(e.cast<String, dynamic>()))
              .toList() ??
          const [],
      grants: (json['grants'] as List?)
              ?.whereType<Map>()
              .map((e) => AccessGrant.fromJson(e.cast<String, dynamic>()))
              .toList() ??
          const [],
    );
  }
}

/// Opaque connection profile handed to the native tunnel adapter. Do not
/// log or send to analytics.
class ConnectionProfile {
  const ConnectionProfile(this.rawJson);

  final String rawJson;
}

DateTime? _parseDate(dynamic value) {
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}
