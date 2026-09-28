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
//
// Moved unchanged into wavebreak_links (previously identical copies in
// wavebreak-mobile and wavebreak-pc lib/services/vpn/share_link_config.dart);
// Hysteria2URL/WireguardURL and their parseShareLink cases are additions.
import 'dart:convert';

import 'share_link.dart';

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

  /// Outbounds beyond proxy/direct/blackhole — the smart-routing policy's
  /// `dns-out` (see [applySmartRoutingPolicy]).
  List<Map<String, dynamic>> extraOutbounds = [];

  Map<String, dynamic> get fullConfiguration => {
        "log": log,
        "inbounds": [inbound],
        "outbounds": [outbound1, outbound2, outbound3, ...extraOutbounds],
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
    "xhttpSettings": null,
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
    } else if (transport == 'xhttp' || transport == 'splithttp') {
      // XHTTP (formerly SplitHTTP): the session travels as ordinary HTTP
      // requests. Xray-core only; sing-box has no such transport.
      streamSetting['network'] = 'xhttp';
      streamSetting['xhttpSettings'] = {
        "path": (path == null || path.isEmpty) ? '/' : path,
        "host": (host == null || host.isEmpty) ? null : host,
        "mode": (mode == null || mode.isEmpty) ? 'auto' : mode,
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

  /// Off unless a policy turns it on (see [applySmartRoutingPolicy]).
  Map<String, dynamic> mux = {"enabled": false, "concurrency": 8};

  /// The link's `flow` (Vision can't be multiplexed).
  String get flow => uri.queryParameters["flow"] ?? "";

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
        "mux": mux,
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

/// Hysteria2 through Xray-core's own client (outbound `hysteria`,
/// transport `hysteria`, version 2) instead of the separate apernet
/// bridge. Verified 2026-09-27 against the pilot server (apernet 2.12.3):
/// 3/3 HTTP 204 through the tunnel, exit IP = the node.
///
/// Certificate is verified normally by SNI — no TOFU pin: the node's TCP
/// 443 is nginx with a different certificate, so pinning over TCP would
/// pin the wrong cert.
class Hysteria2URL extends V2RayURL {
  Hysteria2URL({required super.url}) {
    final l = ShareLink.parse(url);
    if (l.protocol != LinkProtocol.hysteria2) {
      throw ArgumentError('url is invalid');
    }
    link = l;
    streamSetting = {
      "network": "hysteria",
      "security": "tls",
      "tlsSettings": {
        "serverName": l.sni ?? l.host,
        "alpn": (l.alpn ?? 'h3').split(','),
      },
      "hysteriaSettings": {
        "version": 2,
        "auth": l.credential,
      },
      // BBR for uploads (the server ignores client bandwidth and runs its
      // own BBR for downloads), receive windows sized for one long
      // download over a 100–300 ms mobile path, and keep-alives often
      // enough that a carrier NAT doesn't drop an idle session.
      "finalmask": {
        "quicParams": {
          "congestion": "bbr",
          "initStreamReceiveWindow": 8388608,
          "maxStreamReceiveWindow": 16777216,
          "initConnectionReceiveWindow": 20971520,
          "maxConnectionReceiveWindow": 41943040,
          "keepAlivePeriod": 10,
          "maxIdleTimeout": 30,
        },
      },
    };
  }

  late final ShareLink link;

  @override
  String get address => link.host;

  @override
  int get port => link.port;

  @override
  String get remark => link.remark;

  @override
  Map<String, dynamic> get outbound1 => {
        "tag": "proxy",
        "protocol": "hysteria",
        "settings": {"version": 2, "address": address, "port": port},
        "streamSettings": streamSetting,
      };
}

/// WireGuard through Xray-core's `wireguard` outbound.
class WireguardURL extends V2RayURL {
  WireguardURL({required super.url}) {
    final l = ShareLink.parse(url);
    if (l.protocol != LinkProtocol.wireguard) {
      throw ArgumentError('url is invalid');
    }
    link = l;
  }

  late final ShareLink link;

  @override
  String get address => link.host;

  @override
  int get port => link.port;

  @override
  String get remark => link.remark;

  @override
  Map<String, dynamic> get outbound1 => {
        "tag": "proxy",
        "protocol": "wireguard",
        "settings": {
          "secretKey": link.privateKey,
          "address": link.localAddresses,
          if (link.mtu != null) "mtu": link.mtu,
          if (link.reserved != null) "reserved": link.reserved,
          "peers": [
            {
              "publicKey": link.peerPublicKey,
              if (link.preSharedKey != null) "preSharedKey": link.preSharedKey,
              "endpoint": "${link.host}:${link.port}",
            }
          ],
        },
      };
}

/// Parses a share link into the [V2RayURL] subclass that knows how to
/// build its Xray outbound config. Mirrors FlutterV2ray.parseFromURL.
/// Throws [UnsupportedByEngineException] for protocols Xray can't run.
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
    case 'hysteria2':
    case 'hy2':
      return Hysteria2URL(url: url);
    case 'wireguard':
    case 'wg':
      return WireguardURL(url: url);
    case 'tuic':
      throw UnsupportedByEngineException(LinkProtocol.tuic, TunnelEngine.xray);
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
///
/// Also used by the apps themselves for WAVEBREAK's own locations
/// ([kClientSmartRoutingPolicy]), which additionally carry:
///   * `proxy.geosite` — lists that must go through the tunnel even when a
///     `direct` rule would match (blocked Russian media and trackers that
///     sit in `.ru` or on Russian IPs);
///   * `dns.via_tunnel` — apps' DNS goes to Xray's own resolver
///     (`dns-out`) instead of straight out through the carrier, which
///     often intercepts or rewrites it; `direct_resolver` answers the
///     direct domains (a Russian resolver, so Russian CDNs pick Russian
///     servers), the `tunnel_resolvers` everything else, through the
///     tunnel.
void applySmartRoutingPolicy(V2RayURL parsed, Map<String, dynamic>? policy) {
  if (policy == null) return;
  if (policy['mode'] != 'smart_split') return;
  final direct = policy['direct'];
  if (direct is! Map) return;

  // Domain rules match the domain sniffed from the TLS/HTTP/QUIC
  // handshake; routeOnly keeps the connection on the IP the app dialed.
  parsed.inbound = {
    ...parsed.inbound,
    'sniffing': {
      'enabled': true,
      'destOverride': ['http', 'tls', 'quic'],
      'routeOnly': true,
    },
  };

  final directDomains = <String>[
    for (final s in (direct['domain_suffixes'] as List? ?? const []))
      'domain:${_asciiSuffix(s.toString())}',
    for (final g in (direct['geosite'] as List? ?? const []))
      'geosite:${_geositeTag(g.toString())}',
  ];
  final directIps = [
    for (final g in (direct['geoip'] as List? ?? const [])) 'geoip:$g',
  ];
  final proxyPolicy = policy['proxy'];
  final proxyDomains = [
    if (proxyPolicy is Map)
      for (final g in (proxyPolicy['geosite'] as List? ?? const []))
        'geosite:${_geositeTag(g.toString())}',
  ];

  final existing = (parsed.routing['rules'] as List).toList();
  final dnsRules = <Map<String, dynamic>>[];
  final dnsPolicy = policy['dns'];
  if (dnsPolicy is Map && dnsPolicy['via_tunnel'] == true) {
    final directResolver = dnsPolicy['direct_resolver']?.toString();
    final tunnelResolvers = [
      for (final r in (dnsPolicy['tunnel_resolvers'] as List? ?? const ['1.1.1.1']))
        r.toString(),
    ];
    parsed.dns = {
      'tag': 'dns-internal',
      'queryStrategy': 'UseIPv4',
      // A known name is answered from cache at once, even past its TTL,
      // and refreshed in the background: a lookup through the tunnel
      // costs a round trip, which every page load used to wait for.
      'serveStale': true,
      'serveExpiredTTL': 86400,
      'servers': [
        if (directResolver != null && directDomains.isNotEmpty)
          {
            'address': directResolver,
            'domains': directDomains,
            'skipFallback': true,
          },
        ...tunnelResolvers,
      ],
    };
    parsed.extraOutbounds = [
      ...parsed.extraOutbounds.where((o) => o['tag'] != 'dns-out'),
      {'tag': 'dns-out', 'protocol': 'dns'},
    ];
    dnsRules.addAll([
      // Apps' DNS (through the TUN into the SOCKS inbound) -> Xray's DNS.
      {
        'type': 'field',
        'inboundTag': [parsed.inbound['tag']],
        'port': '53',
        'outboundTag': 'dns-out',
      },
      // Xray's own queries: the Russian resolver directly, the rest
      // through the tunnel.
      if (directResolver != null)
        {
          'type': 'field',
          'inboundTag': ['dns-internal'],
          'ip': [directResolver],
          'outboundTag': 'direct',
        },
      {
        'type': 'field',
        'inboundTag': ['dns-internal'],
        'outboundTag': 'proxy',
      },
    ]);
  }

  final rules = <Map<String, dynamic>>[
    ...dnsRules,
    ...existing.cast<Map<String, dynamic>>(),
    if (direct['private_networks'] == true)
      {'type': 'field', 'ip': ['geoip:private'], 'outboundTag': 'direct'},
    // Before the direct rules: a blocked site in .ru must still go
    // through the tunnel.
    if (proxyDomains.isNotEmpty)
      {'type': 'field', 'domain': proxyDomains, 'outboundTag': 'proxy'},
    if (directDomains.isNotEmpty)
      {'type': 'field', 'domain': directDomains, 'outboundTag': 'direct'},
    if (directIps.isNotEmpty)
      {'type': 'field', 'ip': directIps, 'outboundTag': 'direct'},
  ];

  // `transport.mux_websocket`: VLESS over WebSocket (Direct-TLS) opens a
  // TLS + WebSocket handshake per connection — 2–3 round trips before the
  // first byte, for every one of the many connections a page or
  // Telegram's media downloads open. Multiplexed, they share already-open
  // connections. Not with Vision (REALITY), which can't be muxed; QUIC
  // (UDP/443) over mux is rejected so apps fall back to TCP.
  final transport = policy['transport'];
  if (transport is Map &&
      transport['mux_websocket'] == true &&
      parsed is VlessURL &&
      parsed.streamSetting['network'] == 'ws' &&
      parsed.flow.isEmpty) {
    parsed.mux = {
      'enabled': true,
      'concurrency': 8,
      'xudpConcurrency': 16,
      'xudpProxyUDP443': 'reject',
    };
  }

  // Match domain rules first and resolve only when none did (for the
  // geoip ones), rather than resolving every destination up front.
  parsed.routing = {
    ...parsed.routing,
    'domainStrategy': 'IPIfNonMatch',
    'rules': rules,
  };
}

/// The policy WAVEBREAK's apps apply to their own locations (personal and
/// shared ones — never a user's own server): Russian sites straight from
/// the device (sites that block foreign IPs, faster), sites blocked in
/// Russia and everything else through the tunnel, and DNS through the
/// tunnel so the carrier can't rewrite answers.
const Map<String, dynamic> kClientSmartRoutingPolicy = {
  'mode': 'smart_split',
  'direct': {
    'private_networks': true,
    'domain_suffixes': ['.ru', '.su', '.рф'],
    'geosite': ['category-ru'],
    'geoip': ['ru'],
  },
  'proxy': {
    // Lists present in the bundled geosite.dat (an unknown tag makes Xray
    // reject the whole config): blocked Russian media and trackers.
    'geosite': ['category-media-ru-blocked', 'rutracker'],
  },
  'dns': {
    'via_tunnel': true,
    'direct_resolver': '77.88.8.8',
    'tunnel_resolvers': ['1.1.1.1', '8.8.8.8'],
  },
  'transport': {
    'mux_websocket': true,
  },
};

/// ".ru" -> "ru"; ".рф" -> "xn--p1ai" (domains travel as punycode in
/// SNI and DNS, so a Cyrillic suffix would never match).
String _asciiSuffix(String suffix) {
  final bare = suffix.startsWith('.') ? suffix.substring(1) : suffix;
  return const {'рф': 'xn--p1ai'}[bare] ?? bare;
}

/// The bundled geosite.dat has no "ru" list; Core's policy says "ru" for
/// what the file calls "category-ru" (an unknown tag makes Xray refuse
/// the whole config).
String _geositeTag(String tag) => tag.toLowerCase() == 'ru' ? 'category-ru' : tag;
