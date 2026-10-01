import 'dart:convert';

/// Protocols a share link can describe. Which engine can actually run each
/// one is answered by [ShareLink.supportedBy].
enum LinkProtocol {
  vless,
  vmess,
  trojan,
  shadowsocks,
  hysteria2,
  tuic,
  wireguard,
  socks,
  http,
}

/// Tunnel engines the WAVEBREAK clients embed: Xray-core on Android,
/// sing-box on Windows.
enum TunnelEngine { xray, singBox }

/// Thrown when a link is well-formed but the target engine can't run it
/// (e.g. TUIC on Xray, XHTTP on sing-box). Distinct from [FormatException]
/// so the UI can say "not supported on this device" instead of "broken link".
class UnsupportedByEngineException implements Exception {
  UnsupportedByEngineException(this.protocol, this.engine, [this.detail]);

  final LinkProtocol protocol;
  final TunnelEngine engine;
  final String? detail;

  @override
  String toString() =>
      'UnsupportedByEngineException: ${protocol.name}${detail == null ? '' : ' ($detail)'} '
      'is not supported by ${engine.name}';
}

/// One parsed share link, normalized across schemes. Only the fields that
/// apply to a protocol are set; everything else stays null.
class ShareLink {
  const ShareLink({
    required this.protocol,
    required this.raw,
    required this.host,
    required this.port,
    this.credential,
    this.username,
    this.method,
    this.network = 'tcp',
    this.security,
    this.sni,
    this.fingerprint,
    this.publicKey,
    this.shortId,
    this.spiderX,
    this.flow,
    this.alpn,
    this.path,
    this.hostHeader,
    this.serviceName,
    this.mode,
    this.insecure = false,
    this.obfs,
    this.obfsPassword,
    this.portHopping,
    this.pinSha256,
    this.alterId = 0,
    this.congestionControl,
    this.udpRelayMode,
    this.privateKey,
    this.peerPublicKey,
    this.preSharedKey,
    this.localAddresses = const [],
    this.mtu,
    this.reserved,
    this.remark = '',
    this.cloak = false,
    this.cloakMinSize,
    this.cloakMaxSize,
    this.cloakChaffMinMs,
    this.cloakChaffMaxMs,
  });

  final LinkProtocol protocol;

  /// The link exactly as given (trimmed).
  final String raw;

  final String host;
  final int port;

  /// UUID (vless/vmess/tuic), password (trojan/shadowsocks/tuic/socks/http)
  /// or the full auth string (hysteria2, `user:pass` or `pass`).
  final String? credential;

  /// Username for socks/http, UUID for tuic.
  final String? username;

  /// Shadowsocks cipher.
  final String? method;

  /// Transport: tcp, ws, grpc, httpupgrade, xhttp, h2, kcp, quic.
  final String network;

  /// tls, reality or null/none.
  final String? security;
  final String? sni;
  final String? fingerprint;
  final String? publicKey;
  final String? shortId;
  final String? spiderX;
  final String? flow;

  /// Comma-separated ALPN list as it appears in the link.
  final String? alpn;

  final String? path;
  final String? hostHeader;
  final String? serviceName;

  /// gRPC `multi` / XHTTP mode.
  final String? mode;

  final bool insecure;

  /// Hysteria2 obfuscation (salamander).
  final String? obfs;
  final String? obfsPassword;

  /// Hysteria2 port hopping: the UDP port range(s) the server answers on,
  /// as in the link's `mport` ("20000-30000" or "20000-25000,27000").
  /// The client moves between them every few seconds, so no single UDP
  /// flow lives long enough for a carrier to throttle or cut it.
  final String? portHopping;

  /// Hysteria2: SHA-256 of the server certificate (the link's `pinSHA256`,
  /// 64 hex digits). With it the client verifies the server by this hash
  /// instead of by name, so the SNI can be a neutral one — carriers drop
  /// the QUIC handshake by an SNI they recognise.
  final String? pinSha256;

  final int alterId;

  final String? congestionControl;
  final String? udpRelayMode;

  final String? privateKey;
  final String? peerPublicKey;
  final String? preSharedKey;
  final List<String> localAddresses;
  final int? mtu;
  final List<int>? reserved;

  /// Human label from the link's fragment (or vmess `ps`).
  final String remark;

  /// Hysteria2-only, cloak traffic-shape masking (see
  /// docs/CLOAK-TECHNICAL-OVERVIEW.md) — off by default; an ordinary
  /// hysteria2:// link with no `cloak` param is unaffected. Mirrors the
  /// Android app's bridge.go parseLink() handling of the same query params;
  /// on Windows it's read by WindowsVpnAdapter._maybeStartCloakProxy since
  /// sing-box (used there instead of the Android Go bridge) has no cloak
  /// awareness of its own.
  final bool cloak;
  final int? cloakMinSize;
  final int? cloakMaxSize;
  final int? cloakChaffMinMs;
  final int? cloakChaffMaxMs;

  /// Used only to redirect a cloak-enabled hysteria2 link's outbound config
  /// at a local cloak-client-proxy instead of the real server (Windows
  /// only — see WindowsVpnAdapter._maybeStartCloakProxy). Every other field
  /// is kept identical: critically `sni`/`credential`, since the proxy only
  /// wraps the outer UDP datagrams and never touches the inner QUIC/TLS
  /// handshake or auth, which still need to match the real server.
  ShareLink withHostPort(String newHost, int newPort,
          {bool clearPortHopping = false}) =>
      ShareLink(
        protocol: protocol,
        raw: raw,
        host: newHost,
        port: newPort,
        credential: credential,
        username: username,
        method: method,
        network: network,
        security: security,
        sni: sni,
        fingerprint: fingerprint,
        publicKey: publicKey,
        shortId: shortId,
        spiderX: spiderX,
        flow: flow,
        alpn: alpn,
        path: path,
        hostHeader: hostHeader,
        serviceName: serviceName,
        mode: mode,
        insecure: insecure,
        obfs: obfs,
        obfsPassword: obfsPassword,
        portHopping: clearPortHopping ? null : portHopping,
        pinSha256: pinSha256,
        alterId: alterId,
        congestionControl: congestionControl,
        udpRelayMode: udpRelayMode,
        privateKey: privateKey,
        peerPublicKey: peerPublicKey,
        preSharedKey: preSharedKey,
        localAddresses: localAddresses,
        mtu: mtu,
        reserved: reserved,
        remark: remark,
        cloak: cloak,
        cloakMinSize: cloakMinSize,
        cloakMaxSize: cloakMaxSize,
        cloakChaffMinMs: cloakChaffMinMs,
        cloakChaffMaxMs: cloakChaffMaxMs,
      );

  /// Schemes this parser recognizes, including aliases.
  static const knownSchemes = [
    'vless', 'vmess', 'trojan', 'ss', 'hysteria2', 'hy2', 'tuic',
    'wireguard', 'wg', 'socks', 'socks5', 'http', 'https',
  ];

  /// Whether [engine] can run this link as-is.
  bool supportedBy(TunnelEngine engine) => unsupportedReason(engine) == null;

  /// Null when supported; otherwise a short reason.
  String? unsupportedReason(TunnelEngine engine) {
    switch (engine) {
      case TunnelEngine.xray:
        if (protocol == LinkProtocol.tuic) return 'tuic';
        return null;
      case TunnelEngine.singBox:
        if (network == 'xhttp' || network == 'splithttp') return 'xhttp transport';
        if (network == 'kcp') return 'kcp transport';
        return null;
    }
  }

  static ShareLink? tryParse(String url) {
    try {
      return parse(url);
    } on FormatException {
      return null;
    }
  }

  /// Parses any supported share link. Throws [FormatException] for an
  /// unknown scheme or a malformed link.
  static ShareLink parse(String url) {
    final trimmed = url.trim();
    final schemeEnd = trimmed.indexOf('://');
    if (schemeEnd <= 0) throw const FormatException('not a share link');
    final scheme = trimmed.substring(0, schemeEnd).toLowerCase();
    switch (scheme) {
      case 'vmess':
        return _parseVmess(trimmed);
      case 'ss':
        return _parseShadowsocks(trimmed);
      case 'vless':
        return _parseUriLink(trimmed, LinkProtocol.vless);
      case 'trojan':
        return _parseUriLink(trimmed, LinkProtocol.trojan);
      case 'hysteria2':
      case 'hy2':
        return _parseUriLink(trimmed, LinkProtocol.hysteria2);
      case 'tuic':
        return _parseTuic(trimmed);
      case 'wireguard':
      case 'wg':
        return _parseWireguard(trimmed);
      case 'socks':
      case 'socks5':
        return _parseProxy(trimmed, LinkProtocol.socks);
      case 'http':
      case 'https':
        return _parseProxy(trimmed, LinkProtocol.http);
      default:
        throw FormatException('unsupported share link scheme: $scheme');
    }
  }

  static String _remark(Uri uri) {
    if (uri.fragment.isEmpty) return '';
    try {
      return Uri.decodeFull(uri.fragment.replaceAll('+', '%20'));
    } catch (_) {
      return uri.fragment;
    }
  }

  static String? _nonEmpty(String? v) => (v == null || v.isEmpty) ? null : v;

  /// "20000-30000" / "20000-25000,27000" when every part is a valid port
  /// or ascending range; anything else is ignored rather than handed to
  /// an engine that would reject the whole config.
  /// 64 hex digits (colons allowed, as Hysteria writes them), lowercase.
  static String? _sha256Hex(String? v) {
    final hex = (v ?? '').replaceAll(':', '').trim().toLowerCase();
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(hex) ? hex : null;
  }

  static String? _portRanges(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final parts = v.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    bool port(String s) {
      final n = int.tryParse(s);
      return n != null && n > 0 && n < 65536;
    }
    for (final p in parts) {
      final bounds = p.split('-');
      final ok = bounds.length == 1
          ? port(bounds[0])
          : bounds.length == 2 &&
              port(bounds[0]) &&
              port(bounds[1]) &&
              int.parse(bounds[0]) <= int.parse(bounds[1]);
      if (!ok) return null;
    }
    return parts.isEmpty ? null : parts.join(',');
  }

  static bool _truthy(String? v) =>
      v != null && (v == '1' || v.toLowerCase() == 'true');

  static ShareLink _parseUriLink(String url, LinkProtocol protocol) {
    final uri = Uri.tryParse(url);
    if (uri == null) throw const FormatException('malformed share link');
    if (uri.userInfo.isEmpty || uri.host.isEmpty) {
      throw const FormatException('share link is missing credentials or host');
    }
    final q = uri.queryParameters;
    // Percent-decoded, like Go's url.User.Username()/Password(): a
    // re-encoded userinfo would send the server a mangled password.
    final credential = Uri.decodeComponent(uri.userInfo);
    final isHysteria = protocol == LinkProtocol.hysteria2;
    return ShareLink(
      protocol: protocol,
      raw: url,
      host: uri.host,
      port: uri.hasPort ? uri.port : 443,
      credential: credential,
      network: _nonEmpty(q['type']) ?? 'tcp',
      // Hysteria2 is always TLS (QUIC); trojan defaults to TLS too.
      security: isHysteria
          ? 'tls'
          : _nonEmpty(q['security']) ??
              (protocol == LinkProtocol.trojan ? 'tls' : null),
      sni: _nonEmpty(q['sni']) ?? _nonEmpty(q['peer']),
      fingerprint: _nonEmpty(q['fp']),
      publicKey: _nonEmpty(q['pbk']),
      shortId: _nonEmpty(q['sid']),
      spiderX: _nonEmpty(q['spx']),
      flow: _nonEmpty(q['flow']),
      alpn: _nonEmpty(q['alpn']),
      path: _nonEmpty(q['path']),
      hostHeader: _nonEmpty(q['host']),
      serviceName: _nonEmpty(q['serviceName']),
      mode: _nonEmpty(q['mode']),
      insecure: _truthy(q['insecure']) || _truthy(q['allowInsecure']),
      obfs: _nonEmpty(q['obfs']),
      obfsPassword: _nonEmpty(q['obfs-password']),
      portHopping: isHysteria ? _portRanges(q['mport']) : null,
      pinSha256: isHysteria ? _sha256Hex(q['pinSHA256']) : null,
      cloak: isHysteria && _truthy(q['cloak']),
      cloakMinSize: isHysteria ? int.tryParse(q['cloak-min'] ?? '') : null,
      cloakMaxSize: isHysteria ? int.tryParse(q['cloak-max'] ?? '') : null,
      cloakChaffMinMs:
          isHysteria ? int.tryParse(q['cloak-chaff-min-ms'] ?? '') : null,
      cloakChaffMaxMs:
          isHysteria ? int.tryParse(q['cloak-chaff-max-ms'] ?? '') : null,
      remark: _remark(uri),
    );
  }

  static ShareLink _parseVmess(String url) {
    final hash = url.indexOf('#');
    final b64 = url.substring('vmess://'.length, hash < 0 ? url.length : hash);
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(base64.decode(base64.normalize(b64))))
          as Map<String, dynamic>;
    } catch (e) {
      throw FormatException('could not decode vmess:// payload: $e');
    }
    String? str(String key) => _nonEmpty(json[key]?.toString());
    final tlsOn = str('tls') == 'tls';
    return ShareLink(
      protocol: LinkProtocol.vmess,
      raw: url,
      host: str('add') ?? (throw const FormatException('vmess link missing add')),
      port: int.tryParse(str('port') ?? '') ?? 443,
      credential:
          str('id') ?? (throw const FormatException('vmess link missing id')),
      network: str('net') ?? 'tcp',
      security: tlsOn ? 'tls' : null,
      sni: str('sni') ?? (tlsOn ? str('host') : null),
      fingerprint: str('fp'),
      alpn: str('alpn'),
      path: str('path'),
      hostHeader: str('host'),
      serviceName: str('net') == 'grpc' ? str('path') : null,
      alterId: int.tryParse(str('aid') ?? '') ?? 0,
      remark: str('ps') ?? '',
    );
  }

  static ShareLink _parseShadowsocks(String url) {
    final withoutScheme = url.substring('ss://'.length);
    final hashIndex = withoutScheme.indexOf('#');
    final remark = hashIndex >= 0
        ? _remark(Uri(fragment: withoutScheme.substring(hashIndex + 1)))
        : '';
    var body =
        hashIndex >= 0 ? withoutScheme.substring(0, hashIndex) : withoutScheme;
    // SIP002 plugin/query parameters aren't used by either engine config.
    final queryIndex = body.indexOf('?');
    if (queryIndex >= 0) body = body.substring(0, queryIndex);
    if (body.endsWith('/')) body = body.substring(0, body.length - 1);

    String methodPass;
    String hostPort;
    final atIndex = body.lastIndexOf('@');
    if (atIndex > 0) {
      // SIP002: base64url(method:password)@host:port, or plain
      // percent-encoded method:password (SS2022 style).
      final userInfoRaw = body.substring(0, atIndex);
      hostPort = body.substring(atIndex + 1);
      try {
        methodPass = utf8.decode(base64.decode(base64.normalize(userInfoRaw)));
        if (!methodPass.contains(':')) throw const FormatException('');
      } catch (_) {
        methodPass = Uri.decodeComponent(userInfoRaw);
      }
    } else {
      // Legacy: base64(method:password@host:port).
      final String decoded;
      try {
        decoded = utf8.decode(base64.decode(base64.normalize(body)));
      } catch (e) {
        throw FormatException('could not decode ss:// payload: $e');
      }
      final legacyAt = decoded.lastIndexOf('@');
      if (legacyAt < 0) throw const FormatException('shadowsocks link missing host');
      methodPass = decoded.substring(0, legacyAt);
      hostPort = decoded.substring(legacyAt + 1);
    }
    final sep = methodPass.indexOf(':');
    if (sep < 0) {
      throw const FormatException('shadowsocks link missing method:password');
    }
    final hostPortUri = Uri.parse('ss://$hostPort');
    if (hostPortUri.host.isEmpty) {
      throw const FormatException('shadowsocks link missing host');
    }
    return ShareLink(
      protocol: LinkProtocol.shadowsocks,
      raw: url,
      host: hostPortUri.host,
      port: hostPortUri.hasPort ? hostPortUri.port : 8388,
      method: methodPass.substring(0, sep),
      credential: methodPass.substring(sep + 1),
      remark: remark,
    );
  }

  static ShareLink _parseTuic(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty || uri.userInfo.isEmpty) {
      throw const FormatException('tuic link is missing credentials or host');
    }
    final info = Uri.decodeComponent(uri.userInfo);
    final sep = info.indexOf(':');
    final q = uri.queryParameters;
    return ShareLink(
      protocol: LinkProtocol.tuic,
      raw: url,
      host: uri.host,
      port: uri.hasPort ? uri.port : 443,
      username: sep < 0 ? info : info.substring(0, sep),
      credential: sep < 0 ? null : info.substring(sep + 1),
      security: 'tls',
      sni: _nonEmpty(q['sni']),
      alpn: _nonEmpty(q['alpn']),
      insecure: _truthy(q['allow_insecure']) || _truthy(q['insecure']),
      congestionControl: _nonEmpty(q['congestion_control']),
      udpRelayMode: _nonEmpty(q['udp_relay_mode']),
      remark: _remark(uri),
    );
  }

  static ShareLink _parseWireguard(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty || uri.userInfo.isEmpty) {
      throw const FormatException('wireguard link is missing private key or host');
    }
    final q = uri.queryParameters;
    final peerKey = _nonEmpty(q['publickey']) ?? _nonEmpty(q['publicKey']);
    if (peerKey == null) {
      throw const FormatException('wireguard link is missing publickey');
    }
    final addresses = (_nonEmpty(q['address']) ?? _nonEmpty(q['ip']) ?? '')
        .split(',')
        .map((a) => a.trim())
        .where((a) => a.isNotEmpty)
        .map((a) => a.contains('/') ? a : (a.contains(':') ? '$a/128' : '$a/32'))
        .toList();
    final reserved = _nonEmpty(q['reserved'])
        ?.split(',')
        .map((v) => int.tryParse(v.trim()))
        .whereType<int>()
        .toList();
    return ShareLink(
      protocol: LinkProtocol.wireguard,
      raw: url,
      host: uri.host,
      port: uri.hasPort ? uri.port : 51820,
      privateKey: Uri.decodeComponent(uri.userInfo),
      peerPublicKey: peerKey,
      preSharedKey: _nonEmpty(q['presharedkey']) ?? _nonEmpty(q['psk']),
      localAddresses: addresses,
      mtu: int.tryParse(q['mtu'] ?? ''),
      reserved: (reserved == null || reserved.isEmpty) ? null : reserved,
      remark: _remark(uri),
    );
  }

  static ShareLink _parseProxy(String url, LinkProtocol protocol) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      throw const FormatException('proxy link is missing host');
    }
    String? user;
    String? pass;
    if (uri.userInfo.isNotEmpty) {
      var info = Uri.decodeComponent(uri.userInfo);
      if (!info.contains(':')) {
        // v2rayN style: socks://base64(user:pass)@host:port
        try {
          info = utf8.decode(base64.decode(base64.normalize(info)));
        } catch (_) {}
      }
      final sep = info.indexOf(':');
      user = sep < 0 ? info : info.substring(0, sep);
      pass = sep < 0 ? null : info.substring(sep + 1);
    }
    return ShareLink(
      protocol: protocol,
      raw: url,
      host: uri.host,
      port: uri.hasPort
          ? uri.port
          : (protocol == LinkProtocol.socks ? 1080 : (uri.scheme == 'https' ? 443 : 8080)),
      username: user,
      credential: pass,
      security: uri.scheme == 'https' ? 'tls' : null,
      remark: _remark(uri),
    );
  }
}
