// Adapted from flutter_v2ray (https://pub.dev/packages/flutter_v2ray),
// Copyright (c) 2022 Arshia Eihami, MIT licensed — the share-link parsing
// and Xray JSON config generation classes (V2RayURL and its subclasses),
// copied here so this app can keep building the exact same Xray config
// shape it always has without depending on flutter_v2ray's Android/iOS
// native platform code. That native code is what conflicted with this
// app's own gomobile-bound engine (native/hysteria_bridge) when both were
// loaded in one process — see android_multi_engine_adapter.dart's history
// for the full story. The generated JSON is fed to Bridge.startXray() in
// native_vpn_adapter.dart instead of flutter_v2ray's own startV2Ray().
import 'dart:convert';

abstract class V2RayURL {
  V2RayURL({required this.url});
  final String url;

  bool get allowInsecure => true;
  String get security => "auto";
  int get level => 8;
  int get port => 443;
  String get network => "tcp";
  String get address => '';
  String get remark => '';

  Map<String, dynamic> inbound = {
    "tag": "in_proxy",
    "port": 1080,
    "protocol": "socks",
    "listen": "127.0.0.1",
    "settings": {
      "auth": "noauth",
      "udp": true,
      "userLevel": 8,
      "address": null,
      "port": null,
      "network": null
    },
    "sniffing": {"enabled": false, "destOverride": null, "metadataOnly": null},
    "streamSettings": null,
    "allocate": null
  };

  Map<String, dynamic> log = {
    "access": "",
    "error": "",
    "loglevel": "error",
    "dnsLog": false,
  };

  Map<String, dynamic> get outbound1;

  Map<String, dynamic> outbound2 = {
    "tag": "direct",
    "protocol": "freedom",
    "settings": {
      "vnext": null,
      "servers": null,
      "response": null,
      "network": null,
      "address": null,
      "port": null,
      "domainStrategy": "UseIp",
      "redirect": null,
      "userLevel": null,
      "inboundTag": null,
      "secretKey": null,
      "peers": null
    },
    "streamSettings": null,
    "proxySettings": null,
    "sendThrough": null,
    "mux": null
  };

  Map<String, dynamic> outbound3 = {
    "tag": "blackhole",
    "protocol": "blackhole",
    "settings": {
      "vnext": null,
      "servers": null,
      "response": null,
      "network": null,
      "address": null,
      "port": null,
      "domainStrategy": null,
      "redirect": null,
      "userLevel": null,
      "inboundTag": null,
      "secretKey": null,
      "peers": null
    },
    "streamSettings": null,
    "proxySettings": null,
    "sendThrough": null,
    "mux": null
  };

  // MUST stay plain numeric IPs, never a "https://" DoH URL. This exact
  // list is also read on the Android side by the native tun2socks bridge
  // as the VPN's system-wide DNS servers (VpnService.Builder.addDnsServer
  // requires a bare IP) — a URL here previously crashed that natively.
  Map<String, dynamic> dns = {
    "servers": ["1.1.1.1", "8.8.8.8"]
  };

  // Xray-core's router picks the FIRST outbound (the proxy itself, see
  // outbound1) as the default catch-all when no rule matches. With
  // domainStrategy "UseIp", resolving ANY domain-name destination —
  // including the proxy outbound's own server address — requires a DNS
  // UDP query first, and that query is itself dispatched through this
  // same router. Without an explicit rule, the DNS query defaults to the
  // proxy outbound too: to open the proxy connection you need the DNS
  // answer, but to get the DNS answer you need the (not yet open) proxy
  // connection — a real deadlock. Confirmed on-device: a domain-based
  // custom server (IP-based ones never hit this) connected at the
  // TUN/SOCKS layer but passed zero traffic, and a protect-socket debug
  // log showed the registered outbound dialer controller was invoked
  // ZERO times for the whole session — Xray-core never even reached the
  // point of dialing the real server. Routing DNS (port 53) straight to
  // "direct" breaks the cycle: 1.1.1.1/8.8.8.8 are already plain IPs, so
  // that dial needs no resolution and proceeds immediately.
  Map<String, dynamic> routing = {
    "domainStrategy": "UseIp",
    "domainMatcher": null,
    "rules": [
      {
        "type": "field",
        "network": "udp,tcp",
        "port": "53",
        "outboundTag": "direct",
      }
    ],
    "balancers": []
  };

  Map<String, dynamic> get fullConfiguration => {
        "log": log,
        "inbounds": [inbound],
        "outbounds": [outbound1, outbound2, outbound3],
        "dns": dns,
        "routing": routing,
      };

  String getFullConfiguration({int indent = 2}) {
    return JsonEncoder.withIndent(' ' * indent).convert(
      removeNulls(
        Map.from(fullConfiguration),
      ),
    );
  }

  late Map<String, dynamic> streamSetting = {
    "network": network,
    "security": "",
    "tcpSettings": null,
    "kcpSettings": null,
    "wsSettings": null,
    "httpSettings": null,
    "tlsSettings": null,
    "quicSettings": null,
    "realitySettings": null,
    "grpcSettings": null,
    "dsSettings": null,
    "sockopt": null
  };

  String populateTransportSettings({
    required String transport,
    required String? headerType,
    required String? host,
    required String? path,
    required String? seed,
    required String? quicSecurity,
    required String? key,
    required String? mode,
    required String? serviceName,
  }) {
    String sni = '';
    streamSetting['network'] = transport;
    if (transport == 'tcp') {
      streamSetting['tcpSettings'] = {
        "header": <String, dynamic>{"type": "none", "request": null},
        "acceptProxyProtocol": null
      };
      if (headerType == 'http') {
        streamSetting['tcpSettings']['header']['type'] = 'http';
        if (host != "" || path != "") {
          streamSetting['tcpSettings']['header']['request'] = {
            "path": path == null ? ["/"] : path.split(","),
            "headers": {
              "Host": host == null ? "" : host.split(","),
              "User-Agent": [
                "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/53.0.2785.143 Safari/537.36",
                "Mozilla/5.0 (iPhone; CPU iPhone OS 10_0_2 like Mac OS X) AppleWebKit/601.1 (KHTML, like Gecko) CriOS/53.0.2785.109 Mobile/14A456 Safari/601.1.46",
              ],
              "Accept-Encoding": [
                "gzip, deflate",
              ],
              "Connection": [
                "keep-alive",
              ],
              "Pragma": "no-cache",
            },
            "version": "1.1",
            "method": "GET",
          };
          sni = streamSetting['tcpSettings']['header']['request']['headers']
                          ['Host']
                      .length >
                  0
              ? streamSetting['tcpSettings']['header']['request']['headers']
                  ['Host'][0]
              : sni;
        }
      } else {
        streamSetting['tcpSettings']['header']['type'] = 'none';
        sni = host != "" ? host ?? '' : '';
      }
    } else if (transport == 'kcp') {
      streamSetting['kcpSettings'] = {
        "mtu": 1350,
        "tti": 50,
        "uplinkCapacity": 12,
        "downlinkCapacity": 100,
        "congestion": false,
        "readBufferSize": 1,
        "writeBufferSize": 1,
        "header": {
          "type": headerType ?? "none",
        },
        "seed": (seed == null || seed == '') ? null : seed,
      };
    } else if (transport == 'ws') {
      streamSetting['wsSettings'] = {
        "path": path ?? ['/'],
        "headers": {"Host": host ?? ""},
        "maxEarlyData": null,
        "useBrowserForwarding": null,
        "acceptProxyProtocol": null,
      };
      sni = streamSetting['wsSettings']['headers']['Host'];
    } else if (transport == 'h2' || transport == 'http') {
      streamSetting['network'] = 'h2';
      streamSetting['h2Setting'] = {
        "host": host?.split(",") ?? "",
        "path": path ?? ['/'],
      };
      sni = streamSetting['h2Setting']['host'].length > 0
          ? streamSetting['h2Setting']['host'][0]
          : sni;
    } else if (transport == 'quic') {
      streamSetting['quicSettings'] = {
        "security": quicSecurity ?? 'none',
        "key": key ?? '',
        "header": {"type": headerType ?? "none"},
      };
    } else if (transport == 'grpc') {
      streamSetting['grpcSettings'] = {
        "serviceName": serviceName ?? "",
        "multiMode": mode == "multi",
      };
      sni = host ?? "";
    }
    return sni;
  }

  void populateTlsSettings({
    required String? streamSecurity,
    required bool allowInsecure,
    required String? sni,
    required String? fingerprint,
    required String? alpns,
    required String? publicKey,
    required String? shortId,
    required String? spiderX,
  }) {
    streamSetting['security'] = streamSecurity;
    // No "allowInsecure" here on purpose: current Xray-core hard-rejects
    // any config containing it at all (a time-gated removal baked into
    // its own JSON parser, effective 2026-06-01 — confirmed via its
    // source). Its replacement, pinnedPeerCertSha256, is filled in by
    // native_vpn_adapter.dart's connect() instead — it fetches whatever
    // cert the server actually presents (TOFU) and pins that, which
    // covers the same "don't fail on a self-signed/unverifiable cert"
    // case allowInsecure used to.
    Map<String, dynamic> tlsSetting = {
      "serverName": sni,
      "alpn": alpns == '' ? null : alpns?.split(','),
      "minVersion": null,
      "maxVersion": null,
      "preferServerCipherSuites": null,
      "cipherSuites": null,
      "fingerprint": fingerprint,
      "certificates": null,
      "disableSystemRoot": null,
      "enableSessionResumption": null,
      "show": false,
      "publicKey": publicKey,
      "shortId": shortId,
      "spiderX": spiderX,
    };
    if (streamSecurity == 'tls') {
      streamSetting['realitySettings'] = null;
      streamSetting['tlsSettings'] = tlsSetting;
    } else if (streamSecurity == 'reality') {
      streamSetting['tlsSettings'] = null;
      streamSetting['realitySettings'] = tlsSetting;
    }
  }

  dynamic removeNulls(dynamic params) {
    if (params is Map) {
      var map = {};
      params.forEach((key, value) {
        var value0 = removeNulls(value);
        if (value0 != null) {
          map[key] = value0;
        }
      });
      if (map.isNotEmpty) {
        return map;
      }
    } else if (params is List) {
      var list = [];
      for (var val in params) {
        var value = removeNulls(val);
        if (value != null) {
          list.add(value);
        }
      }
      if (list.isNotEmpty) return list;
    } else if (params != null) {
      return params;
    }
    return null;
  }
}

class VlessURL extends V2RayURL {
  VlessURL({required super.url}) {
    if (!url.startsWith('vless://')) {
      throw ArgumentError('url is invalid');
    }
    final temp = Uri.tryParse(url);
    if (temp == null) {
      throw ArgumentError('url is invalid');
    }
    uri = temp;
    var sni = super.populateTransportSettings(
      transport: uri.queryParameters["type"] ?? "tcp",
      headerType: uri.queryParameters["headerType"],
      host: uri.queryParameters["host"],
      path: uri.queryParameters["path"],
      seed: uri.queryParameters["seed"],
      quicSecurity: uri.queryParameters["quicSecurity"],
      key: uri.queryParameters["key"],
      mode: uri.queryParameters["mode"],
      serviceName: uri.queryParameters["serviceName"],
    );
    super.populateTlsSettings(
      streamSecurity: uri.queryParameters["security"] ?? "",
      allowInsecure: allowInsecure,
      sni: uri.queryParameters["sni"] ?? sni,
      fingerprint: uri.queryParameters["fp"] ??
          streamSetting['tlsSettings']?['fingerprint'],
      alpns: uri.queryParameters["alpn"],
      publicKey: uri.queryParameters["pbk"] ?? "",
      shortId: uri.queryParameters["sid"] ?? "",
      spiderX: uri.queryParameters["spx"] ?? "",
    );
  }

  @override
  String get address => uri.host;

  @override
  int get port => uri.hasPort ? uri.port : super.port;

  @override
  String get remark => Uri.decodeFull(uri.fragment.replaceAll('+', '%20'));

  late final Uri uri;

  @override
  Map<String, dynamic> get outbound1 => {
        "tag": "proxy",
        "protocol": "vless",
        "settings": {
          "vnext": [
            {
              "address": address,
              "port": port,
              "users": [
                {
                  "id": uri.userInfo,
                  "alterId": null,
                  "security": security,
                  "level": level,
                  "encryption": uri.queryParameters["encryption"] ?? "none",
                  "flow": uri.queryParameters["flow"] ?? "",
                }
              ]
            }
          ],
          "servers": null,
          "response": null,
          "network": null,
          "address": null,
          "port": null,
          "domainStrategy": null,
          "redirect": null,
          "userLevel": null,
          "inboundTag": null,
          "secretKey": null,
          "peers": null
        },
        "streamSettings": streamSetting,
        "proxySettings": null,
        "sendThrough": null,
        "mux": {
          "enabled": false,
          "concurrency": 8,
        },
      };
}

class VmessURL extends V2RayURL {
  VmessURL({required super.url}) {
    if (!url.startsWith('vmess://')) {
      throw ArgumentError('url is invalid');
    }
    String raw = url.substring(8);
    if (raw.length % 4 > 0) {
      raw += "=" * (4 - raw.length % 4);
    }
    try {
      rawConfig = jsonDecode(utf8.decode(base64Decode(raw)));
    } catch (_) {
      throw ArgumentError('url is invalid');
    }
    var sni = super.populateTransportSettings(
      transport: rawConfig['net'],
      headerType: rawConfig['type'],
      host: rawConfig['host'],
      path: rawConfig['path'],
      seed: rawConfig['path'],
      quicSecurity: rawConfig['host'],
      key: rawConfig['path'],
      mode: rawConfig['type'],
      serviceName: rawConfig['path'],
    );
    String? fingerprint = (rawConfig['fp'] != null && rawConfig['fp'] != '')
        ? rawConfig['fp']
        : streamSetting['tlsSettings']?['fingerprint'];
    super.populateTlsSettings(
      streamSecurity: rawConfig['tls'],
      allowInsecure: allowInsecure,
      sni: sni,
      fingerprint: fingerprint,
      alpns: rawConfig['alpn'],
      publicKey: null,
      shortId: null,
      spiderX: null,
    );
  }
  late final Map<String, dynamic> rawConfig;

  @override
  String get remark => rawConfig['ps'];

  @override
  String get address => rawConfig['add'] ?? '';

  @override
  int get port => int.tryParse(rawConfig['port'].toString()) ?? super.port;

  @override
  Map<String, dynamic> get outbound1 => {
        "tag": "proxy",
        "protocol": "vmess",
        "settings": {
          "vnext": [
            {
              "address": address,
              "port": port,
              "users": [
                {
                  "id": rawConfig['id'] ?? '',
                  "alterId": int.tryParse(rawConfig['aid'].toString()) ?? 0,
                  "security": (rawConfig['scy']?.isEmpty ?? true)
                      ? security
                      : rawConfig['scy'],
                  "level": level,
                  "encryption": "",
                  "flow": ""
                }
              ]
            }
          ],
          "servers": null,
          "response": null,
          "network": null,
          "address": null,
          "port": null,
          "domainStrategy": null,
          "redirect": null,
          "userLevel": null,
          "inboundTag": null,
          "secretKey": null,
          "peers": null
        },
        "streamSettings": streamSetting,
        "proxySettings": null,
        "sendThrough": null,
        "mux": {
          "enabled": false,
          "concurrency": 8,
        }
      };
}

class TrojanURL extends V2RayURL {
  TrojanURL({required super.url}) {
    if (!url.startsWith('trojan://')) {
      throw ArgumentError('url is invalid');
    }
    final temp = Uri.tryParse(url);
    if (temp == null) {
      throw ArgumentError('url is invalid');
    }
    uri = temp;
    if (uri.queryParameters.isNotEmpty) {
      var sni = super.populateTransportSettings(
        transport: uri.queryParameters['type'] ?? "tcp",
        headerType: uri.queryParameters['headerType'],
        host: uri.queryParameters["host"],
        path: uri.queryParameters["path"],
        seed: uri.queryParameters["seed"],
        quicSecurity: uri.queryParameters["quicSecurity"],
        key: uri.queryParameters["key"],
        mode: uri.queryParameters["mode"],
        serviceName: uri.queryParameters["serviceName"],
      );

      super.populateTlsSettings(
        streamSecurity: uri.queryParameters['security'] ?? 'tls',
        allowInsecure: allowInsecure,
        sni: uri.queryParameters["sni"] ?? sni,
        fingerprint:
            streamSetting['tlsSettings']?['fingerprint'] ?? "randomized",
        alpns: uri.queryParameters['alpn'],
        publicKey: null,
        shortId: null,
        spiderX: null,
      );
      flow = uri.queryParameters["flow"] ?? "";
    } else {
      super.populateTlsSettings(
        streamSecurity: 'tls',
        allowInsecure: allowInsecure,
        sni: '',
        fingerprint:
            streamSetting['tlsSettings']?['fingerprint'] ?? "randomized",
        alpns: null,
        publicKey: null,
        shortId: null,
        spiderX: null,
      );
    }
  }
  String flow = "";

  @override
  String get address => uri.host;

  @override
  int get port => uri.hasPort ? uri.port : super.port;

  @override
  String get remark => Uri.decodeFull(uri.fragment.replaceAll('+', '%20'));

  late final Uri uri;

  @override
  Map<String, dynamic> get outbound1 => {
        "tag": "proxy",
        "protocol": "trojan",
        "settings": {
          "vnext": null,
          "servers": [
            {
              "address": address,
              "method": "chacha20-poly1305",
              "ota": false,
              "password": uri.userInfo,
              "port": port,
              "level": level,
              "email": null,
              "flow": flow,
              "ivCheck": null,
              "users": null
            }
          ],
          "response": null,
          "network": null,
          "address": null,
          "port": null,
          "domainStrategy": null,
          "redirect": null,
          "userLevel": null,
          "inboundTag": null,
          "secretKey": null,
          "peers": null
        },
        "streamSettings": streamSetting,
        "proxySettings": null,
        "sendThrough": null,
        "mux": {"enabled": false, "concurrency": 8}
      };
}

class ShadowSocksURL extends V2RayURL {
  ShadowSocksURL({required super.url}) {
    if (!url.startsWith('ss://')) {
      throw ArgumentError('url is invalid');
    }
    final temp = Uri.tryParse(url);
    if (temp == null) {
      throw ArgumentError('url is invalid');
    }
    uri = temp;
    if (uri.userInfo.isNotEmpty) {
      String raw = uri.userInfo;
      if (raw.length % 4 > 0) {
        raw += "=" * (4 - raw.length % 4);
      }
      try {
        final methodpass = utf8.decode(base64Decode(raw));
        method = methodpass.split(':')[0];
        password = methodpass.substring(method.length + 1);
      } catch (_) {}
    }

    if (uri.queryParameters.isNotEmpty) {
      var sni = super.populateTransportSettings(
        transport: uri.queryParameters['type'] ?? "tcp",
        headerType: uri.queryParameters['headerType'],
        host: uri.queryParameters["host"],
        path: uri.queryParameters["path"],
        seed: uri.queryParameters["seed"],
        quicSecurity: uri.queryParameters["quicSecurity"],
        key: uri.queryParameters["key"],
        mode: uri.queryParameters["mode"],
        serviceName: uri.queryParameters["serviceName"],
      );
      super.populateTlsSettings(
        streamSecurity: uri.queryParameters['security'] ?? '',
        allowInsecure: allowInsecure,
        sni: uri.queryParameters["sni"] ?? sni,
        fingerprint: streamSetting['tlsSettings']?['fingerprint'],
        alpns: uri.queryParameters['alpn'],
        publicKey: null,
        shortId: null,
        spiderX: null,
      );
    }
  }

  @override
  String get address => uri.host;

  @override
  int get port => uri.hasPort ? uri.port : super.port;

  @override
  String get remark => Uri.decodeFull(uri.fragment.replaceAll('+', '%20'));

  late final Uri uri;

  String method = "none";

  String password = "";

  @override
  Map<String, dynamic> get outbound1 => {
        "tag": "proxy",
        "protocol": "shadowsocks",
        "settings": {
          "vnext": null,
          "servers": [
            {
              "address": address,
              "method": method,
              "ota": false,
              "password": password,
              "port": port,
              "level": level,
              "email": null,
              "flow": null,
              "ivCheck": null,
              "users": null
            }
          ],
          "response": null,
          "network": null,
          "address": null,
          "port": null,
          "domainStrategy": null,
          "redirect": null,
          "userLevel": null,
          "inboundTag": null,
          "secretKey": null,
          "peers": null
        },
        "streamSettings": streamSetting,
        "proxySettings": null,
        "sendThrough": null,
        "mux": {"enabled": false, "concurrency": 8}
      };
}

class SocksURL extends V2RayURL {
  SocksURL({required super.url}) {
    if (!url.startsWith('socks://')) {
      throw ArgumentError('url is invalid');
    }
    final temp = Uri.tryParse(url);
    if (temp == null) {
      throw ArgumentError('url is invalid');
    }
    uri = temp;
    if (uri.userInfo.isNotEmpty) {
      final String userpass = utf8.decode(base64Decode(uri.userInfo));
      username = userpass.split(':')[0];
      password = userpass.substring(username!.length + 1);
    } else {
      username = null;
      password = null;
    }
  }

  late final String? username;
  late final String? password;
  late final Uri uri;

  @override
  String get address => uri.host;

  @override
  int get port => uri.hasPort ? uri.port : super.port;

  @override
  String get remark => Uri.decodeFull(uri.fragment.replaceAll('+', '%20'));

  @override
  Map<String, dynamic> get outbound1 => {
        "protocol": "socks",
        "settings": {
          "servers": [
            {
              "address": address,
              "level": level,
              "method": "chacha20-poly1305",
              "ota": false,
              "password": "",
              "port": port,
              "users": [
                {"level": level, "user": username, "pass": password}
              ]
            }
          ]
        },
        "streamSettings": streamSetting,
        "tag": "proxy",
        "mux": {"concurrency": 8, "enabled": false},
      };
}

/// Parses a share link into the [V2RayURL] subclass that knows how to
/// build its Xray outbound config. Mirrors FlutterV2ray.parseFromURL.
V2RayURL parseShareLink(String url) {
  switch (url.split("://")[0].toLowerCase()) {
    case 'vmess':
      return VmessURL(url: url);
    case 'vless':
      return VlessURL(url: url);
    case 'trojan':
      return TrojanURL(url: url);
    case 'ss':
      return ShadowSocksURL(url: url);
    case 'socks':
      return SocksURL(url: url);
    default:
      throw ArgumentError('url is invalid');
  }
}

/// Applies Core's `smart-routing-v1` policy (see
/// docs/mobile-desktop-api.md — `GET /v1/access/grants/{id}/config`'s
/// `routing_policy`) to a parsed share link's Xray routing table: RU
/// domains/IPs and private/local networks go out "direct" (bypassing the
/// tunnel), everything else keeps falling through to the proxy outbound —
/// the router's existing default when nothing matches (see `routing`'s own
/// comment above for why that default, not an explicit rule, is what
/// actually sends unmatched traffic through the proxy). Xray-core resolves
/// `geosite:`/`geoip:` rules from geoip.dat/geosite.dat via the
/// XRAY_LOCATION_ASSET directory (see native/hysteria_bridge/geoassets.go
/// — WaveEngineVpnService.kt points it there before every Xray start), so
/// this only needs to emit the rule references, not the underlying data.
///
/// A plain share link handed to a third-party client (Happ, etc.) never
/// carries this — Core's own comment on the field is explicit that it's
/// WAVEBREAK-client-only, not encodable into the link itself.
void applySmartRoutingPolicy(V2RayURL parsed, Map<String, dynamic>? policy) {
  if (policy == null) return;
  if (policy['mode'] != 'smart_split') return;
  final direct = policy['direct'];
  if (direct is! Map) return;

  final rules = (parsed.routing['rules'] as List).toList();

  if (direct['private_networks'] == true) {
    rules.add({
      'type': 'field',
      'ip': ['geoip:private'],
      'outboundTag': 'direct',
    });
  }
  final suffixes = direct['domain_suffixes'];
  if (suffixes is List && suffixes.isNotEmpty) {
    rules.add({
      'type': 'field',
      // Xray's `domain:` prefix is a label-boundary suffix match (matches
      // "example.ru" and "www.example.ru", not merely any string ending
      // in "ru") — exactly what a leading-dot suffix like ".ru" means here,
      // just without Xray's own leading-dot spelling.
      'domain': [
        for (final s in suffixes)
          'domain:${s.toString().startsWith('.') ? s.toString().substring(1) : s}',
      ],
      'outboundTag': 'direct',
    });
  }
  final geosite = direct['geosite'];
  if (geosite is List && geosite.isNotEmpty) {
    rules.add({
      'type': 'field',
      'domain': [for (final g in geosite) 'geosite:$g'],
      'outboundTag': 'direct',
    });
  }
  final geoip = direct['geoip'];
  if (geoip is List && geoip.isNotEmpty) {
    rules.add({
      'type': 'field',
      'ip': [for (final g in geoip) 'geoip:$g'],
      'outboundTag': 'direct',
    });
  }

  parsed.routing = {...parsed.routing, 'rules': rules};
}
