import 'share_link.dart';

/// sing-box (Windows client) config pieces for a [ShareLink].
///
/// The vless/vmess/trojan/shadowsocks/hysteria2 shapes are carried over
/// unchanged from wavebreak-pc's windows_vpn_adapter.dart; grpc,
/// httpupgrade, tuic, wireguard, socks and http are additions.
class SingBoxProxy {
  SingBoxProxy._(this.entry, {required this.isEndpoint});

  /// The outbound (or, for WireGuard, the endpoint) object, tagged [tag].
  final Map<String, dynamic> entry;

  /// sing-box 1.11+ models WireGuard as an `endpoints[]` entry rather than
  /// an outbound; both are valid `route.final` targets by tag.
  final bool isEndpoint;

  static const tag = 'proxy';

  /// Throws [UnsupportedByEngineException] for links sing-box can't run.
  factory SingBoxProxy.fromLink(ShareLink link) {
    final reason = link.unsupportedReason(TunnelEngine.singBox);
    if (reason != null) {
      throw UnsupportedByEngineException(link.protocol, TunnelEngine.singBox, reason);
    }
    switch (link.protocol) {
      case LinkProtocol.vless:
        return SingBoxProxy._(_vless(link), isEndpoint: false);
      case LinkProtocol.vmess:
        return SingBoxProxy._(_vmess(link), isEndpoint: false);
      case LinkProtocol.trojan:
        return SingBoxProxy._(_trojan(link), isEndpoint: false);
      case LinkProtocol.shadowsocks:
        return SingBoxProxy._(_shadowsocks(link), isEndpoint: false);
      case LinkProtocol.hysteria2:
        return SingBoxProxy._(_hysteria2(link), isEndpoint: false);
      case LinkProtocol.tuic:
        return SingBoxProxy._(_tuic(link), isEndpoint: false);
      case LinkProtocol.wireguard:
        return SingBoxProxy._(_wireguard(link), isEndpoint: true);
      case LinkProtocol.socks:
        return SingBoxProxy._(_socks(link), isEndpoint: false);
      case LinkProtocol.http:
        return SingBoxProxy._(_http(link), isEndpoint: false);
    }
  }

  static Map<String, dynamic> _tls(ShareLink l) => {
        'enabled': true,
        if (l.sni != null) 'server_name': l.sni,
        if (l.insecure) 'insecure': true,
        if (l.fingerprint != null)
          'utls': {'enabled': true, 'fingerprint': l.fingerprint},
        if (l.security == 'reality' && l.publicKey != null)
          'reality': {
            'enabled': true,
            'public_key': l.publicKey,
            if (l.shortId != null) 'short_id': l.shortId,
          },
      };

  static Map<String, dynamic>? _transport(ShareLink l) {
    switch (l.network) {
      case 'ws':
        return {
          'type': 'ws',
          'path': l.path ?? '/',
          if (l.hostHeader != null) 'headers': {'Host': l.hostHeader},
        };
      case 'grpc':
        return {'type': 'grpc', 'service_name': l.serviceName ?? ''};
      case 'httpupgrade':
        return {
          'type': 'httpupgrade',
          'path': l.path ?? '/',
          if (l.hostHeader != null) 'host': l.hostHeader,
        };
      default:
        return null;
    }
  }

  static Map<String, dynamic> _vless(ShareLink l) {
    // Same condition as the original PC adapter: Vision flow only on
    // raw-TCP REALITY.
    final effectiveFlow =
        l.network == 'tcp' && l.security == 'reality' ? l.flow : null;
    final transport = _transport(l);
    return {
      'type': 'vless',
      'tag': tag,
      'server': l.host,
      'server_port': l.port,
      'uuid': l.credential,
      if (effectiveFlow != null) 'flow': effectiveFlow,
      'tls': _tls(l),
      if (transport != null) 'transport': transport,
    };
  }

  static Map<String, dynamic> _vmess(ShareLink l) {
    final transport = _transport(l);
    return {
      'type': 'vmess',
      'tag': tag,
      'server': l.host,
      'server_port': l.port,
      'uuid': l.credential,
      'security': 'auto',
      'alter_id': l.alterId,
      if (l.security == 'tls') 'tls': _tls(l),
      if (transport != null) 'transport': transport,
    };
  }

  static Map<String, dynamic> _trojan(ShareLink l) {
    final transport = _transport(l);
    return {
      'type': 'trojan',
      'tag': tag,
      'server': l.host,
      'server_port': l.port,
      'password': l.credential,
      'tls': _tls(l),
      if (transport != null) 'transport': transport,
    };
  }

  static Map<String, dynamic> _shadowsocks(ShareLink l) => {
        'type': 'shadowsocks',
        'tag': tag,
        'server': l.host,
        'server_port': l.port,
        'method': l.method,
        'password': l.credential,
      };

  static Map<String, dynamic> _hysteria2(ShareLink l) => {
        'type': 'hysteria2',
        'tag': tag,
        'server': l.host,
        'server_port': l.port,
        'password': l.credential,
        'tls': _tls(l),
        if (l.obfs != null)
          'obfs': {
            'type': l.obfs,
            if (l.obfsPassword != null) 'password': l.obfsPassword,
          },
      };

  static Map<String, dynamic> _tuic(ShareLink l) => {
        'type': 'tuic',
        'tag': tag,
        'server': l.host,
        'server_port': l.port,
        'uuid': l.username,
        if (l.credential != null) 'password': l.credential,
        if (l.congestionControl != null) 'congestion_control': l.congestionControl,
        if (l.udpRelayMode != null) 'udp_relay_mode': l.udpRelayMode,
        'tls': _tls(l),
      };

  static Map<String, dynamic> _wireguard(ShareLink l) => {
        'type': 'wireguard',
        'tag': tag,
        'address': l.localAddresses,
        'private_key': l.privateKey,
        if (l.mtu != null) 'mtu': l.mtu,
        'peers': [
          {
            'address': l.host,
            'port': l.port,
            'public_key': l.peerPublicKey,
            if (l.preSharedKey != null) 'pre_shared_key': l.preSharedKey,
            'allowed_ips': ['0.0.0.0/0', '::/0'],
            if (l.reserved != null) 'reserved': l.reserved,
          },
        ],
      };

  static Map<String, dynamic> _socks(ShareLink l) => {
        'type': 'socks',
        'tag': tag,
        'server': l.host,
        'server_port': l.port,
        if (l.username != null) 'username': l.username,
        if (l.credential != null) 'password': l.credential,
      };

  static Map<String, dynamic> _http(ShareLink l) => {
        'type': 'http',
        'tag': tag,
        'server': l.host,
        'server_port': l.port,
        if (l.username != null) 'username': l.username,
        if (l.credential != null) 'password': l.credential,
        if (l.security == 'tls') 'tls': _tls(l),
      };
}
