import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/logging/app_logger.dart';
import '../core_api/models.dart';
import 'vpn_adapter.dart';

/// Real system-level VPN tunnel for Windows, via a bundled sing-box.exe
/// (see windows/runtime_deps and windows/runner/CMakeLists.txt for how it
/// and wintun.dll land next to the built exe) driven with a generated
/// "tun" inbound + share-link outbound config. sing-box needs to create a
/// TUN adapter and change routes, which needs admin rights —
/// runner.exe.manifest requests elevation for the whole app for exactly
/// this reason.
class WindowsVpnAdapter implements VpnAdapter {
  final _controller = StreamController<VpnNativeState>.broadcast();
  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  // Bumped at the top of every connect() call and checked after each
  // `await` inside it — switching locations while a connect is still in
  // flight (a slow DNS-over-HTTPS lookup, a slow Hysteria2/QUIC handshake,
  // or just a user clicking a second server before the first one
  // resolved) used to run two connect() calls concurrently. Both raced to
  // set `_process`, so `disconnect()` could only ever kill whichever one
  // won that race — the other's sing-box.exe was leaked, still holding
  // the "wavebreak" TUN interface, and fighting the new attempt over that
  // same interface name is exactly what turned into either an indefinite
  // "Подключение..." or an immediate "Не удалось подключиться" depending
  // on which process lost the race. Every state mutation below is guarded
  // by comparing against this generation, so a superseded call becomes a
  // no-op (and kills its own process immediately once started) instead of
  // clobbering the newer one's state.
  int _generation = 0;

  @override
  Stream<VpnNativeState> get states => _controller.stream;

  @override
  Future<void> connect(ConnectionProfile profile) async {
    final generation = ++_generation;
    await disconnect();
    if (generation != _generation) return;

    final url = _extractUrl(profile.rawJson);
    if (url == null || url.isEmpty) {
      if (generation == _generation) _emit(VpnNativeState.failed);
      throw StateError('profile has no usable share link');
    }

    final ShareLink link;
    try {
      link = ShareLink.parse(url);
    } catch (e) {
      AppLogger.warn('Could not parse share link for sing-box: $e');
      if (generation == _generation) _emit(VpnNativeState.failed);
      throw StateError('unsupported share link');
    }

    if (generation == _generation) _emit(VpnNativeState.connecting);

    final exePath = await _singBoxPath();
    if (generation != _generation) return;
    if (exePath == null) {
      _emit(VpnNativeState.failed);
      throw StateError('sing-box.exe not found next to the app');
    }

    final configPath = await _writeConfig(link);
    if (generation != _generation) return;
    final completer = Completer<void>();
    var resolved = false;

    try {
      final process = await Process.start(
        exePath,
        ['run', '-c', configPath],
        workingDirectory: File(exePath).parent.path,
        runInShell: false,
      );
      if (generation != _generation) {
        // A newer connect() (or a disconnect()) already moved on while
        // sing-box was launching — this attempt is stale. Kill it now
        // rather than leaving it running alongside whatever superseded
        // it; there is nothing left here that should touch `_process` or
        // emit a state for this generation.
        process.kill(ProcessSignal.sigterm);
        return;
      }
      _process = process;

      void onLine(String line, void Function(String) log) {
        log('[sing-box] $line');
        if (generation != _generation) return;
        // sing-box logs this once the tun interface + routes are up —
        // there is no separate "ready" event to wait for otherwise.
        // Confirmed by running sing-box.exe directly: it writes its
        // entire log output — including this line — to stderr, never
        // stdout. Watching stdout alone meant `resolved` never flipped,
        // so every connection sat until the 25s timeout killed it and
        // reported "Connection failed" regardless of whether the tunnel
        // itself had already come up and was passing real traffic.
        if (!resolved && line.contains('sing-box started')) {
          resolved = true;
          _emit(VpnNativeState.connected);
          completer.complete();
        }
      }

      _stdoutSub = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => onLine(line, AppLogger.debug));
      _stderrSub = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => onLine(line, AppLogger.warn));

      unawaited(process.exitCode.then((code) {
        if (generation != _generation) return;
        if (!resolved) {
          resolved = true;
          _emit(VpnNativeState.failed);
          if (!completer.isCompleted) {
            completer.completeError(StateError('sing-box exited early (code $code)'));
          }
        } else if (code != 0) {
          _emit(VpnNativeState.failed);
        } else {
          _emit(VpnNativeState.idle);
        }
      }));
    } catch (e) {
      if (generation == _generation) _emit(VpnNativeState.failed);
      throw StateError('failed to launch sing-box: $e');
    }

    try {
      // Was 15s — too tight for a Hysteria2/QUIC handshake over a slow or
      // lossy path (confirmed this session: real RTT to the pilot node
      // alone can run into the hundreds of ms, before sing-box's own
      // DNS-over-HTTPS lookup and the handshake itself), and every
      // timeout here was indistinguishable from a real failure in the UI.
      await completer.future.timeout(const Duration(seconds: 25));
    } on TimeoutException {
      if (generation == _generation) {
        await disconnect();
        _emit(VpnNativeState.failed);
      }
      throw StateError('sing-box did not report ready in time');
    }
  }

  @override
  Future<void> disconnect() async {
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    final process = _process;
    _process = null;
    if (process != null) {
      process.kill(ProcessSignal.sigterm);
      // sing-box tears the TUN adapter + routes down on a clean exit —
      // give it a moment before a caller might turn around and relaunch.
      try {
        await process.exitCode.timeout(const Duration(seconds: 5));
      } catch (_) {
        process.kill(ProcessSignal.sigkill);
      }
    }
  }

  @override
  Future<int?> pingMs() async => null;

  void _emit(VpnNativeState state) {
    if (!_controller.isClosed) _controller.add(state);
  }

  Future<String?> _singBoxPath() async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidate = '$exeDir\\sing-box.exe';
    if (await File(candidate).exists()) return candidate;
    return null;
  }

  Future<String> _writeConfig(ShareLink link) async {
    final dir = Directory.systemTemp;
    final file = File('${dir.path}\\wavebreak_singbox.json');
    await file.writeAsString(jsonEncode(link.toSingBoxConfig()));
    return file.path;
  }

  /// Mirrors [ConnectionManager]'s two profile shapes — see
  /// V2RayVpnAdapter's identical helper for the full rationale.
  String? _extractUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.contains('://') && !trimmed.startsWith('{')) {
      return trimmed;
    }
    try {
      final payload = jsonDecode(trimmed) as Map<String, dynamic>;
      final vless = payload['vless'] as Map<String, dynamic>?;
      final url = vless?['connection_url'] as String?;
      return (url != null && url.isNotEmpty) ? url : null;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    unawaited(disconnect());
    unawaited(_controller.close());
  }
}

/// A parsed share link — `vless://`, `vmess://`, `trojan://`, `ss://`, or
/// `hysteria2://` / `hy2://` — narrowly scoped to what a sing-box "tun"
/// outbound config needs for each. WAVEBREAK's own grants are always
/// VLESS (REALITY direct, or the CDN-fronted WebSocket+TLS fallback —
/// see docs/vpn-config-contract.md's `vless_cdn`/`trojan_cdn`); the rest
/// matter for a *custom* link the user pastes themselves — sing-box
/// supports all five natively, so there's no reason to only handle one.
class ShareLink {
  const ShareLink({
    required this.scheme,
    required this.credential,
    required this.host,
    required this.port,
    this.flow,
    this.sni,
    this.fingerprint,
    this.publicKey,
    this.shortId,
    this.network = 'tcp',
    this.security,
    this.wsHost,
    this.wsPath,
    this.insecure = false,
    this.obfs,
    this.obfsPassword,
    this.alterId = 0,
    this.method,
  });

  /// `vless`, `vmess`, `trojan`, `shadowsocks`, or `hysteria2`.
  final String scheme;

  /// The link's core secret — a UUID for VLESS/VMess, a password for
  /// Trojan/Hysteria2/Shadowsocks.
  final String credential;

  final String host;
  final int port;

  // VLESS/REALITY-only.
  final String? flow;
  final String? fingerprint;
  final String? publicKey;
  final String? shortId;

  // Shared TLS fields (VLESS, VMess, Trojan).
  final String? sni;
  final String? security;
  final bool insecure;

  /// Transport for VLESS/VMess/Trojan: `tcp` (direct) or `ws`
  /// (CDN-fronted). `grpc`/`httpupgrade` pass straight through too, but
  /// only `ws` needs the extra host/path handled specially.
  final String network;
  final String? wsHost;
  final String? wsPath;

  // Hysteria2-only.
  final String? obfs;
  final String? obfsPassword;

  // VMess-only.
  final int alterId;

  // Shadowsocks-only.
  final String? method;

  factory ShareLink.parse(String url) {
    final trimmed = url.trim();
    if (trimmed.startsWith('vmess://')) return _parseVmess(trimmed);
    if (trimmed.startsWith('ss://')) return _parseShadowsocks(trimmed);

    final uri = Uri.parse(trimmed);
    final scheme = uri.scheme == 'hy2' ? 'hysteria2' : uri.scheme;
    if (!['vless', 'trojan', 'hysteria2'].contains(scheme)) {
      throw FormatException('unsupported share link scheme: ${uri.scheme}');
    }
    if (uri.userInfo.isEmpty || uri.host.isEmpty) {
      throw const FormatException('share link is missing credentials or host');
    }
    final q = uri.queryParameters;
    // Hysteria2 links never carry a `type` param at all (it's a VLESS/
    // VMess/Trojan-only transport selector) — the old
    // `(q['type'] ?? 'tcp').isEmpty ? 'tcp' : q['type']!` checked the
    // *defaulted* value's emptiness but then re-read the original
    // (still-null) `q['type']` in the false branch, crashing with a null
    // check error on every single Hysteria2 link. Confirmed: this is why
    // the Windows client never even got as far as launching sing-box for
    // Hysteria2 — ShareLink.parse() threw before any of that.
    final rawType = q['type'];
    final network = (rawType == null || rawType.isEmpty) ? 'tcp' : rawType;
    return ShareLink(
      scheme: scheme,
      credential: uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : 443,
      flow: (q['flow'] ?? '').isEmpty ? null : q['flow'],
      sni: q['sni'] ?? q['peer'],
      fingerprint: q['fp'],
      publicKey: q['pbk'],
      shortId: q['sid'],
      network: network,
      security: q['security'],
      wsHost: q['host'],
      wsPath: q['path'],
      insecure: q['insecure'] == '1' || q['allowInsecure'] == '1',
      obfs: q['obfs'],
      obfsPassword: q['obfs-password'],
    );
  }

  /// `vmess://base64(JSON)` — a completely different shape from the
  /// others (no query-string params at all; every field lives in the
  /// encoded JSON blob). See the (long-standing, if never formally
  /// standardized) v2rayN-style schema most vmess generators emit.
  static ShareLink _parseVmess(String url) {
    final b64 = url.substring('vmess://'.length);
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(base64.decode(base64.normalize(b64)))) as Map<String, dynamic>;
    } catch (e) {
      throw FormatException('could not decode vmess:// payload: $e');
    }
    String? str(String key) {
      final v = json[key];
      if (v == null) return null;
      final s = v.toString();
      return s.isEmpty ? null : s;
    }
    final tlsOn = str('tls') == 'tls';
    return ShareLink(
      scheme: 'vmess',
      credential: str('id') ?? (throw const FormatException('vmess link missing id')),
      host: str('add') ?? (throw const FormatException('vmess link missing add')),
      port: int.tryParse(str('port') ?? '') ?? 443,
      network: str('net') ?? 'tcp',
      sni: str('sni') ?? (tlsOn ? str('host') : null),
      security: tlsOn ? 'tls' : null,
      wsHost: str('host'),
      wsPath: str('path'),
      alterId: int.tryParse(str('aid') ?? '') ?? 0,
    );
  }

  /// `ss://base64(method:password)@host:port#label` (SIP002) or the
  /// legacy `ss://base64(method:password@host:port)#label` — try SIP002
  /// first since it's what every current generator emits, fall back to
  /// the legacy whole-URI encoding.
  static ShareLink _parseShadowsocks(String url) {
    final withoutScheme = url.substring('ss://'.length);
    final hashIndex = withoutScheme.indexOf('#');
    final body = hashIndex >= 0 ? withoutScheme.substring(0, hashIndex) : withoutScheme;

    final atIndex = body.lastIndexOf('@');
    if (atIndex > 0) {
      final userInfoRaw = body.substring(0, atIndex);
      final hostPort = body.substring(atIndex + 1);
      String userInfo;
      try {
        userInfo = utf8.decode(base64.decode(base64.normalize(userInfoRaw)));
      } catch (_) {
        userInfo = Uri.decodeComponent(userInfoRaw);
      }
      final sep = userInfo.indexOf(':');
      if (sep < 0) throw const FormatException('shadowsocks link missing method:password');
      final hostPortUri = Uri.parse('ss://$hostPort');
      return ShareLink(
        scheme: 'shadowsocks',
        method: userInfo.substring(0, sep),
        credential: userInfo.substring(sep + 1),
        host: hostPortUri.host,
        port: hostPortUri.hasPort ? hostPortUri.port : 8388,
      );
    }

    // Legacy: the whole `method:password@host:port` is base64-encoded.
    String decoded;
    try {
      decoded = utf8.decode(base64.decode(base64.normalize(body)));
    } catch (e) {
      throw FormatException('could not decode ss:// payload: $e');
    }
    final legacyAt = decoded.lastIndexOf('@');
    if (legacyAt < 0) throw const FormatException('shadowsocks link missing host');
    final methodPass = decoded.substring(0, legacyAt);
    final hostPort = decoded.substring(legacyAt + 1);
    final sep = methodPass.indexOf(':');
    if (sep < 0) throw const FormatException('shadowsocks link missing method:password');
    final hostPortUri = Uri.parse('ss://$hostPort');
    return ShareLink(
      scheme: 'shadowsocks',
      method: methodPass.substring(0, sep),
      credential: methodPass.substring(sep + 1),
      host: hostPortUri.host,
      port: hostPortUri.hasPort ? hostPortUri.port : 8388,
    );
  }

  Map<String, dynamic> toSingBoxConfig() {
    return {
      'log': {'level': 'info', 'timestamp': true},
      // Without this, sing-box falls back to the system's raw DNS
      // resolver for the outbound server's own hostname — which silently
      // times out on any network that blocks/intercepts plain UDP/TCP
      // DNS (confirmed locally: the plain lookup hung for 10s and failed
      // outright, while DoH on 443 resolved in ~500ms). Doing this over
      // HTTPS is also just more robust in general, not merely a
      // workaround for one network.
      // No explicit `detour` on the DNS server: sing-box already resolves
      // it sensibly by default, and setting one to the "direct" outbound
      // here (added, then reverted, after testing) makes sing-box treat
      // "direct" as unused/"empty" and refuse to start outright — it's
      // otherwise only ever the DNS path, never a real routed outbound.
      'dns': {
        'servers': [
          {'type': 'https', 'tag': 'remote', 'server': '1.1.1.1'},
        ],
        'final': 'remote',
        'strategy': 'prefer_ipv4',
      },
      'inbounds': [
        {
          'type': 'tun',
          'interface_name': 'wavebreak',
          'address': ['172.19.0.1/30'],
          'mtu': 1400,
          'auto_route': true,
          'strict_route': true,
          'stack': 'system',
        },
      ],
      'outbounds': [_outbound(), {'type': 'direct', 'tag': 'direct'}],
      // No separate DNS outbound/rule — that pattern was removed in
      // sing-box 1.13 (a "dns" outbound type is a hard config error now).
      // DNS queries just ride the tunnel like everything else via
      // `final: proxy` below, which also avoids leaking them outside it.
      'route': {
        'auto_detect_interface': true,
        'final': 'proxy',
      },
    };
  }

  Map<String, dynamic> _outbound() {
    switch (scheme) {
      case 'vless':
        return _vlessOutbound();
      case 'vmess':
        return _vmessOutbound();
      case 'trojan':
        return _trojanOutbound();
      case 'shadowsocks':
        return _shadowsocksOutbound();
      case 'hysteria2':
        return _hysteria2Outbound();
      default:
        throw StateError('unreachable: unhandled scheme $scheme');
    }
  }

  /// REALITY (the direct link, `security=reality`) and plain TLS (the
  /// CDN link — no reality/pbk/sid at all) both need `tls.enabled`, but
  /// only one of them ever carries a reality block.
  Map<String, dynamic> _tls() {
    return {
      'enabled': true,
      if (sni != null) 'server_name': sni,
      if (insecure) 'insecure': true,
      if (fingerprint != null) 'utls': {'enabled': true, 'fingerprint': fingerprint},
      if (security == 'reality' && publicKey != null)
        'reality': {
          'enabled': true,
          'public_key': publicKey,
          if (shortId != null) 'short_id': shortId,
        },
    };
  }

  Map<String, dynamic>? _transport() {
    if (network != 'ws') return null;
    return {
      'type': 'ws',
      'path': wsPath ?? '/',
      if (wsHost != null) 'headers': {'Host': wsHost},
    };
  }

  Map<String, dynamic> _vlessOutbound() {
    // XTLS flow only ever applies to a raw-tcp REALITY outbound — sending
    // it alongside a websocket transport is a hard error in sing-box.
    final effectiveFlow = network == 'tcp' && security == 'reality' ? flow : null;
    final transport = _transport();
    return {
      'type': 'vless',
      'tag': 'proxy',
      'server': host,
      'server_port': port,
      'uuid': credential,
      if (effectiveFlow != null) 'flow': effectiveFlow,
      'tls': _tls(),
      if (transport != null) 'transport': transport,
    };
  }

  Map<String, dynamic> _vmessOutbound() {
    final transport = _transport();
    return {
      'type': 'vmess',
      'tag': 'proxy',
      'server': host,
      'server_port': port,
      'uuid': credential,
      'security': 'auto',
      'alter_id': alterId,
      // Unlike VLESS/Trojan, plain vmess (no `tls=tls` in the link) is
      // common and valid — only attach TLS when the link actually asked
      // for it.
      if (security == 'tls') 'tls': _tls(),
      if (transport != null) 'transport': transport,
    };
  }

  Map<String, dynamic> _shadowsocksOutbound() {
    return {
      'type': 'shadowsocks',
      'tag': 'proxy',
      'server': host,
      'server_port': port,
      'method': method,
      'password': credential,
    };
  }

  Map<String, dynamic> _trojanOutbound() {
    final transport = _transport();
    return {
      'type': 'trojan',
      'tag': 'proxy',
      'server': host,
      'server_port': port,
      'password': credential,
      'tls': _tls(),
      if (transport != null) 'transport': transport,
    };
  }

  Map<String, dynamic> _hysteria2Outbound() {
    return {
      'type': 'hysteria2',
      'tag': 'proxy',
      'server': host,
      'server_port': port,
      'password': credential,
      'tls': _tls(),
      if (obfs != null)
        'obfs': {
          'type': obfs,
          if (obfsPassword != null) 'password': obfsPassword,
        },
    };
  }
}
