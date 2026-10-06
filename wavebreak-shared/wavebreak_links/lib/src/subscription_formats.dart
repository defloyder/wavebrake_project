import 'dart:convert';

import 'mini_yaml.dart';
import 'subscription.dart';

/// What a subscription body turned out to be.
enum SubscriptionFormat { shareLinks, base64Links, clash, singBox, unknown }

/// A node the profile lists that can't be expressed as a share link we
/// run (an unknown proxy type, a missing field) — shown greyed out.
class UnsupportedNode {
  const UnsupportedNode(this.name, this.type);
  final String name;
  final String type;
}

/// A subscription body read in whichever format it came: every node as a
/// share link (Clash and sing-box entries are converted), plus the nodes
/// that couldn't be.
class ParsedSubscription {
  const ParsedSubscription(this.format, this.links, [this.unsupported = const []]);
  final SubscriptionFormat format;
  final List<String> links;
  final List<UnsupportedNode> unsupported;

  bool get isEmpty => links.isEmpty && unsupported.isEmpty;
}

/// Reads a subscription body: share links one per line, base64 of those,
/// a Clash/Mihomo YAML profile (`proxies:`) or a sing-box JSON config
/// (`outbounds`).
ParsedSubscription parseSubscription(String body) {
  final text = body.trim();
  if (text.isEmpty) return const ParsedSubscription(SubscriptionFormat.unknown, []);
  if (text.startsWith('{')) {
    final singBox = _trySingBox(text);
    if (singBox != null) return singBox;
  }
  if (RegExp(r'^proxies\s*:', multiLine: true).hasMatch(text)) {
    final clash = _tryClash(text);
    if (clash != null) return clash;
  }
  final links = extractShareLinks(text);
  if (links.isNotEmpty) {
    return ParsedSubscription(
        text.contains('://')
            ? SubscriptionFormat.shareLinks
            : SubscriptionFormat.base64Links,
        links);
  }
  return const ParsedSubscription(SubscriptionFormat.unknown, []);
}

// ---- subscription headers --------------------------------------------

/// `subscription-userinfo: upload=…; download=…; total=…; expire=…`.
class SubscriptionUserInfo {
  const SubscriptionUserInfo({this.upload, this.download, this.total, this.expire});

  final int? upload;
  final int? download;

  /// Traffic limit in bytes; null or 0 = unlimited.
  final int? total;

  /// Null = no end date.
  final DateTime? expire;

  int get used => (upload ?? 0) + (download ?? 0);

  static SubscriptionUserInfo? parse(String? header) {
    if (header == null || header.trim().isEmpty) return null;
    final values = <String, int>{};
    for (final part in header.split(';')) {
      final eq = part.indexOf('=');
      if (eq <= 0) continue;
      final key = part.substring(0, eq).trim().toLowerCase();
      final value = num.tryParse(part.substring(eq + 1).trim());
      if (value != null) values[key] = value.toInt();
    }
    if (values.isEmpty) return null;
    final expire = values['expire'];
    return SubscriptionUserInfo(
      upload: values['upload'],
      download: values['download'],
      total: values['total'],
      expire: expire == null || expire <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expire * 1000, isUtc: true),
    );
  }
}

/// `profile-title`, plain or `base64:…`.
String? decodeProfileTitle(String? header) {
  if (header == null) return null;
  var title = header.trim();
  if (title.toLowerCase().startsWith('base64:')) {
    try {
      title = utf8.decode(base64.decode(base64.normalize(title.substring(7).trim())));
    } catch (_) {
      return null;
    }
  }
  title = title.trim();
  return title.isEmpty ? null : title;
}

/// `profile-update-interval` in hours (1..720), else null.
int? parseUpdateIntervalHours(String? header) {
  final hours = int.tryParse(header?.trim() ?? '');
  if (hours == null || hours < 1) return null;
  return hours > 720 ? 720 : hours;
}

// ---- Clash / Mihomo ----------------------------------------------------

ParsedSubscription? _tryClash(String text) {
  final Object? doc;
  try {
    doc = parseMiniYaml(text);
  } on FormatException {
    return null;
  }
  if (doc is! Map) return null;
  final proxies = doc['proxies'];
  if (proxies is! List) return null;
  final links = <String>[];
  final unsupported = <UnsupportedNode>[];
  for (final p in proxies.whereType<Map>()) {
    final node = p.cast<String, Object?>();
    final link = clashProxyToLink(node);
    if (link != null) {
      links.add(link);
    } else {
      unsupported.add(UnsupportedNode(_str(node['name']) ?? '?', _str(node['type']) ?? '?'));
    }
  }
  return ParsedSubscription(SubscriptionFormat.clash, links, unsupported);
}

/// One Clash/Mihomo proxy entry as a share link; null for types and
/// shapes we don't run.
String? clashProxyToLink(Map<String, Object?> p) {
  final type = _str(p['type'])?.toLowerCase();
  final name = _str(p['name']) ?? '';
  final server = _str(p['server']);
  final port = _int(p['port']);
  if (type == null || server == null || port == null) return null;
  final network = _str(p['network']) ?? 'tcp';
  final ws = _map(p['ws-opts']);
  final grpc = _map(p['grpc-opts']);
  final h2 = _map(p['h2-opts']);
  final http = _map(p['http-opts']);
  final reality = _map(p['reality-opts']);
  final alpn = _list(p['alpn']);
  final insecure = p['skip-cert-verify'] == true;

  Map<String, String?> transport() => {
        'type': network,
        'path': _str(ws?['path']) ?? _str(h2?['path']) ?? _firstOrSelf(http?['path']),
        'host': _str(_map(ws?['headers'])?['Host']) ??
            _firstOrSelf(h2?['host']) ??
            _firstOrSelf(_map(http?['headers'])?['Host']),
        'serviceName': _str(grpc?['grpc-service-name']),
      };

  switch (type) {
    case 'vless':
      final uuid = _str(p['uuid']);
      if (uuid == null) return null;
      final tls = p['tls'] == true || reality != null;
      return _uriLink('vless', uuid, server, port, name, {
        ...transport(),
        'encryption': 'none',
        'security': reality != null ? 'reality' : (tls ? 'tls' : null),
        'sni': _str(p['servername']) ?? _str(p['sni']),
        'fp': _str(p['client-fingerprint']),
        'pbk': _str(reality?['public-key']),
        'sid': _str(reality?['short-id']),
        'flow': _str(p['flow']),
        'alpn': alpn,
        'allowInsecure': insecure ? '1' : null,
      });
    case 'trojan':
      final password = _str(p['password']);
      if (password == null) return null;
      return _uriLink('trojan', password, server, port, name, {
        ...transport(),
        'security': reality != null ? 'reality' : 'tls',
        'sni': _str(p['sni']) ?? _str(p['servername']),
        'fp': _str(p['client-fingerprint']),
        'pbk': _str(reality?['public-key']),
        'sid': _str(reality?['short-id']),
        'alpn': alpn,
        'allowInsecure': insecure ? '1' : null,
      });
    case 'vmess':
      final uuid = _str(p['uuid']);
      if (uuid == null) return null;
      final t = transport();
      return _vmessLink(
        name: name,
        server: server,
        port: port,
        uuid: uuid,
        alterId: _int(p['alterId']) ?? 0,
        network: network,
        tls: p['tls'] == true,
        sni: _str(p['servername']),
        host: t['host'],
        path: network == 'grpc' ? t['serviceName'] : t['path'],
        fp: _str(p['client-fingerprint']),
        alpn: alpn,
      );
    case 'ss':
      final cipher = _str(p['cipher']);
      final password = _str(p['password']);
      if (cipher == null || password == null || p['plugin'] != null) return null;
      return _ssLink(cipher, password, server, port, name);
    case 'hysteria2':
    case 'hy2':
      final password = _str(p['password']) ?? _str(p['auth']);
      if (password == null) return null;
      return _uriLink('hysteria2', password, server, port, name, {
        'sni': _str(p['sni']),
        'obfs': _str(p['obfs']),
        'obfs-password': _str(p['obfs-password']),
        'mport': _str(p['ports']),
        'alpn': alpn,
        'insecure': insecure ? '1' : null,
      });
    case 'tuic':
      final uuid = _str(p['uuid']);
      final password = _str(p['password']);
      if (uuid == null || password == null) return null;
      return _uriLink('tuic', '$uuid:$password', server, port, name, {
        'sni': _str(p['sni']),
        'alpn': alpn,
        'congestion_control': _str(p['congestion-controller']),
        'udp_relay_mode': _str(p['udp-relay-mode']),
        'allow_insecure': insecure ? '1' : null,
      });
    case 'wireguard':
      final key = _str(p['private-key']);
      final peer = _str(p['public-key']);
      if (key == null || peer == null) return null;
      return _uriLink('wireguard', key, server, port, name, {
        'publickey': peer,
        'presharedkey': _str(p['pre-shared-key']),
        'address': [_str(p['ip']), _str(p['ipv6'])].whereType<String>().join(','),
        'mtu': _int(p['mtu'])?.toString(),
        'reserved': _list(p['reserved']),
      });
    case 'socks5':
      final user = _str(p['username']);
      final pass = _str(p['password']);
      return _uriLink('socks', user == null ? null : (pass == null ? user : '$user:$pass'),
          server, port, name, const {});
  }
  return null;
}

// ---- sing-box ----------------------------------------------------------

const _singBoxServiceTypes = {
  'direct', 'block', 'dns', 'selector', 'urltest', 'tor',
};

ParsedSubscription? _trySingBox(String text) {
  final Object? doc;
  try {
    doc = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (doc is! Map || doc['outbounds'] is! List) return null;
  final links = <String>[];
  final unsupported = <UnsupportedNode>[];
  for (final o in (doc['outbounds'] as List).whereType<Map>()) {
    final out = o.cast<String, Object?>();
    final type = _str(out['type'])?.toLowerCase() ?? '';
    if (_singBoxServiceTypes.contains(type)) continue;
    final link = singBoxOutboundToLink(out);
    if (link != null) {
      links.add(link);
    } else {
      unsupported.add(UnsupportedNode(_str(out['tag']) ?? '?', type));
    }
  }
  return ParsedSubscription(SubscriptionFormat.singBox, links, unsupported);
}

/// One sing-box outbound as a share link; null for what we don't run.
String? singBoxOutboundToLink(Map<String, Object?> o) {
  final type = _str(o['type'])?.toLowerCase();
  final name = _str(o['tag']) ?? '';
  final server = _str(o['server']);
  final port = _int(o['server_port']);
  if (type == null || server == null || port == null) return null;
  final tls = _map(o['tls']);
  final tlsOn = tls?['enabled'] == true;
  final reality = _map(tls?['reality']);
  final realityOn = reality?['enabled'] == true;
  final transport = _map(o['transport']);
  final network = switch (_str(transport?['type'])) {
    null => 'tcp',
    'http' => 'h2',
    final t => t,
  };
  final headers = _map(transport?['headers']);
  final common = <String, String?>{
    'type': network,
    'path': _str(transport?['path']),
    'host': _firstOrSelf(headers?['Host']) ?? _firstOrSelf(transport?['host']),
    'serviceName': _str(transport?['service_name']),
    'sni': _str(tls?['server_name']),
    'fp': _str(_map(tls?['utls'])?['fingerprint']),
    'alpn': _list(tls?['alpn']),
    'allowInsecure': tls?['insecure'] == true ? '1' : null,
  };

  switch (type) {
    case 'vless':
      final uuid = _str(o['uuid']);
      if (uuid == null) return null;
      return _uriLink('vless', uuid, server, port, name, {
        ...common,
        'encryption': 'none',
        'security': realityOn ? 'reality' : (tlsOn ? 'tls' : null),
        'pbk': _str(reality?['public_key']),
        'sid': _str(reality?['short_id']),
        'flow': _str(o['flow']),
      });
    case 'trojan':
      final password = _str(o['password']);
      if (password == null) return null;
      return _uriLink('trojan', password, server, port, name, {
        ...common,
        'security': realityOn ? 'reality' : 'tls',
        'pbk': _str(reality?['public_key']),
        'sid': _str(reality?['short_id']),
      });
    case 'vmess':
      final uuid = _str(o['uuid']);
      if (uuid == null) return null;
      return _vmessLink(
        name: name,
        server: server,
        port: port,
        uuid: uuid,
        alterId: _int(o['alter_id']) ?? 0,
        network: network,
        tls: tlsOn,
        sni: common['sni'],
        host: common['host'],
        path: network == 'grpc' ? common['serviceName'] : common['path'],
        fp: common['fp'],
        alpn: common['alpn'],
      );
    case 'shadowsocks':
      final method = _str(o['method']);
      final password = _str(o['password']);
      if (method == null || password == null || o['plugin'] != null) return null;
      return _ssLink(method, password, server, port, name);
    case 'hysteria2':
      final password = _str(o['password']);
      if (password == null) return null;
      final obfs = _map(o['obfs']);
      return _uriLink('hysteria2', password, server, port, name, {
        'sni': common['sni'],
        'alpn': common['alpn'],
        'insecure': tls?['insecure'] == true ? '1' : null,
        'obfs': _str(obfs?['type']),
        'obfs-password': _str(obfs?['password']),
      });
    case 'tuic':
      final uuid = _str(o['uuid']);
      final password = _str(o['password']);
      if (uuid == null || password == null) return null;
      return _uriLink('tuic', '$uuid:$password', server, port, name, {
        'sni': common['sni'],
        'alpn': common['alpn'],
        'congestion_control': _str(o['congestion_control']),
        'udp_relay_mode': _str(o['udp_relay_mode']),
        'allow_insecure': tls?['insecure'] == true ? '1' : null,
      });
    case 'wireguard':
      final key = _str(o['private_key']);
      final peer = _str(o['peer_public_key']);
      if (key == null || peer == null) return null;
      return _uriLink('wireguard', key, server, port, name, {
        'publickey': peer,
        'presharedkey': _str(o['pre_shared_key']),
        'address': _list(o['local_address']),
        'mtu': _int(o['mtu'])?.toString(),
        'reserved': _list(o['reserved']),
      });
    case 'socks':
      final user = _str(o['username']);
      final pass = _str(o['password']);
      return _uriLink('socks', user == null ? null : (pass == null ? user : '$user:$pass'),
          server, port, name, const {});
  }
  return null;
}

// ---- link builders -----------------------------------------------------

String _uriLink(String scheme, String? userInfo, String host, int port,
    String name, Map<String, String?> params) {
  final query = params.entries
      .where((e) => e.value != null && e.value!.isNotEmpty)
      .where((e) => !(e.key == 'type' && e.value == 'tcp'))
      .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value!)}')
      .join('&');
  final hostPart = host.contains(':') && !host.startsWith('[') ? '[$host]' : host;
  final user = userInfo == null ? '' : '${Uri.encodeComponent(userInfo).replaceAll('%3A', ':')}@';
  final fragment = name.isEmpty ? '' : '#${Uri.encodeComponent(name)}';
  return '$scheme://$user$hostPart:$port${query.isEmpty ? '' : '?$query'}$fragment';
}

String _vmessLink({
  required String name,
  required String server,
  required int port,
  required String uuid,
  required int alterId,
  required String network,
  required bool tls,
  String? sni,
  String? host,
  String? path,
  String? fp,
  String? alpn,
}) {
  final json = <String, Object?>{
    'v': '2',
    'ps': name,
    'add': server,
    'port': '$port',
    'id': uuid,
    'aid': '$alterId',
    'net': network,
    'type': 'none',
    'tls': tls ? 'tls' : '',
    if (sni != null) 'sni': sni,
    if (host != null) 'host': host,
    if (path != null) 'path': path,
    if (fp != null) 'fp': fp,
    if (alpn != null) 'alpn': alpn,
  };
  return 'vmess://${base64.encode(utf8.encode(jsonEncode(json)))}';
}

String _ssLink(String method, String password, String host, int port, String name) {
  final user = base64Url.encode(utf8.encode('$method:$password')).replaceAll('=', '');
  final hostPart = host.contains(':') && !host.startsWith('[') ? '[$host]' : host;
  final fragment = name.isEmpty ? '' : '#${Uri.encodeComponent(name)}';
  return 'ss://$user@$hostPart:$port$fragment';
}

// ---- value helpers -----------------------------------------------------

String? _str(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

int? _int(Object? v) => v is int ? v : int.tryParse(v?.toString().trim() ?? '');

Map<String, Object?>? _map(Object? v) => v is Map ? v.cast<String, Object?>() : null;

/// A list (or a single value) as "a,b".
String? _list(Object? v) {
  if (v is List) {
    final parts = v.map(_str).whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(',');
  }
  return _str(v);
}

String? _firstOrSelf(Object? v) => v is List ? (v.isEmpty ? null : _str(v.first)) : _str(v);
