import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:wavebreak_links/wavebreak_links.dart';

import '../../core/logging/app_logger.dart';
import '../../core/logging/file_log.dart';
import '../core_api/models.dart';
import 'conflicting_vpn_closer.dart';
import 'vpn_adapter.dart';
import 'windows_tunnel.dart';

/// Xray's SOCKS inbound for the health probe and the latency figure, and
/// its metrics (stats) endpoint — loopback only, next to sing-box's Clash
/// API port (47983).
const kXrayProbePort = 47984;
const kXrayMetricsPort = 47985;

/// The Windows tunnel on Xray-core (handoff docs/HANDOFF-pc-xray-migration.md,
/// phase 1): xray.exe as a child process that owns the Wintun adapter and
/// the routes itself (`tun` inbound, `autoSystemRoutingTable`,
/// `autoOutboundsInterface: auto`), with the Android app's own outbound,
/// DNS and smart-routing config. Same shape as the sing-box adapter —
/// a process next to the app, recovered by restarting it — but the
/// engine is the real Xray: XHTTP, Vision, REALITY as on the phone.
///
/// Only for links Xray runs as they are ([supports]); the rest (cloak,
/// TUIC, a self-signed third-party server) stay on sing-box — see
/// [WindowsEngineSwitch].
class WindowsXrayAdapter implements VpnAdapter, WindowsTunnel {
  final _controller = StreamController<VpnNativeState>.broadcast();
  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _healthTimer;
  Timer? _networkDebounce;
  String? _lastConfigPath;
  bool _expectedExit = false;
  bool _recovering = false;
  int _generation = 0;
  int _healthFailures = 0;
  DateTime _upAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastProxyDown = -1;

  static const _readyTimeout = Duration(seconds: 25);
  static const _healthInterval = Duration(seconds: 20);
  static const _maxHealthFailures = 3;
  static const _networkGrace = Duration(seconds: 15);

  /// Whether this link goes to Xray: it parses for Xray, isn't a cloak
  /// link (only sing-box + cloak-client-proxy wrap those), and isn't a
  /// third-party server asking to skip certificate checks (Xray rejects
  /// allowInsecure; Android pins the cert on first use — not done here
  /// yet).
  /// xray.exe ships next to the app (optional, see CMakeLists).
  static bool get installed => File(
          '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}xray.exe')
      .existsSync();

  static bool supports(String url) {
    final link = ShareLink.tryParse(url);
    if (link == null || !link.supportedBy(TunnelEngine.xray)) return false;
    if (link.cloak || link.insecure) return false;
    try {
      parseShareLink(url);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<VpnNativeState> get states => _controller.stream;

  @override
  Future<void> connect(ConnectionProfile profile) async {
    final generation = ++_generation;
    await disconnect();
    if (generation != _generation) return;

    final url = windowsProfileUrl(profile.rawJson);
    if (url == null || !supports(url)) {
      _emit(VpnNativeState.failed);
      throw StateError('link not runnable on Xray');
    }
    final parsed = parseShareLink(url);
    applySmartRoutingPolicy(
        parsed, windowsProfileRoutingPolicy(profile.rawJson));
    // The server's address while the system DNS is still the plain one —
    // see xray_config.dart's windowsTunConfiguration (DNS deadlock).
    final serverHosts = await _resolveServer(ShareLink.tryParse(url)?.host);
    if (generation != _generation) return;
    final config = parsed.getWindowsTunConfiguration(
        probePort: kXrayProbePort,
        metricsPort: kXrayMetricsPort,
        serverHosts: serverHosts);
    AppLogger.info(
        'Connecting on Xray (${ShareLink.tryParse(url)?.protocol.name})');

    _emit(VpnNativeState.connecting);
    await const ConflictingVpnCloser().closeAll();
    if (generation != _generation) return;

    final exe = await _xrayPath();
    if (generation != _generation) return;
    if (exe == null) {
      _emit(VpnNativeState.failed);
      throw StateError('xray.exe not found next to the app');
    }
    // Next to sing-box's own config (wavebreak_singbox.json).
    final path =
        '${Directory.systemTemp.path}${Platform.pathSeparator}wavebreak_xray.json';
    await File(path).writeAsString(config);
    if (generation != _generation) return;
    _lastConfigPath = path;
    await _launch(exe, path, generation);
  }

  /// {host: [IPv4…]} for a server named by a domain; empty for an IP or
  /// when it can't be resolved (Xray then resolves it itself, as before).
  static Future<Map<String, List<String>>> _resolveServer(String? host) async {
    if (host == null || host.isEmpty || InternetAddress.tryParse(host) != null) {
      return const {};
    }
    try {
      final found = await InternetAddress.lookup(host,
              type: InternetAddressType.IPv4)
          .timeout(const Duration(seconds: 5));
      final ips = [for (final a in found) a.address];
      AppLogger.info('Xray: $host resolved before the tunnel (${ips.length})');
      return ips.isEmpty ? const {} : {host: ips};
    } catch (e) {
      AppLogger.warn('Xray: could not resolve $host before the tunnel: $e');
      return const {};
    }
  }

  Future<void> _launch(String exe, String configPath, int generation,
      {bool reportFailure = true}) async {
    final process = await Process.start(
      exe,
      ['run', '-c', configPath],
      workingDirectory: File(exe).parent.path,
      // geoip.dat / geosite.dat sit next to xray.exe.
      environment: {'XRAY_LOCATION_ASSET': File(exe).parent.path},
    );
    if (generation != _generation) {
      process.kill();
      return;
    }
    _process = process;
    _expectedExit = false;
    void onLine(String line) => FileLog.write('[xray] $line');
    _stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onLine);
    _stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onLine);
    var exited = false;
    unawaited(process.exitCode.then((code) {
      exited = true;
      if (generation != _generation || _expectedExit) return;
      AppLogger.warn('xray exited on its own (code $code)');
      _process = null;
      unawaited(_recover('xray exited'));
    }));

    // Ready = a real request through the tunnel's outbound answers — not a
    // log line (the sing-box path matches "sing-box started", which the
    // handoff calls fragile).
    final deadline = DateTime.now().add(_readyTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (generation != _generation) return;
      if (exited) break;
      if (await measureTunnelLatency() != null) {
        if (generation != _generation) return;
        _upAt = DateTime.now();
        _emit(VpnNativeState.connected);
        _startResilience();
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    if (generation != _generation) return;
    await _killProcess();
    if (reportFailure) _emit(VpnNativeState.failed);
    throw StateError(
        exited ? 'xray exited early' : 'xray did not get ready in time');
  }

  @override
  Future<void> disconnect() async {
    _stopResilience();
    await _killProcess();
  }

  Future<void> _killProcess() async {
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    final p = _process;
    _process = null;
    if (p == null) return;
    _expectedExit = true;
    p.kill();
    // Xray removes its routes and the adapter on exit.
    try {
      await p.exitCode.timeout(const Duration(seconds: 5));
    } catch (_) {
      p.kill(ProcessSignal.sigkill);
    }
  }

  // --- Resilience: health probe, network changes, crash -> restart ---

  void _startResilience() {
    _stopResilience();
    _healthFailures = 0;
    _lastProxyDown = -1;
    _healthTimer = Timer.periodic(_healthInterval, (_) => unawaited(_health()));
    _connectivitySub = Connectivity().onConnectivityChanged.listen((_) {
      if (DateTime.now().difference(_upAt) < _networkGrace) return;
      _networkDebounce?.cancel();
      _networkDebounce = Timer(const Duration(milliseconds: 1200),
          () => unawaited(_recover('network change')));
    });
  }

  void _stopResilience() {
    _healthTimer?.cancel();
    _healthTimer = null;
    _networkDebounce?.cancel();
    _networkDebounce = null;
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  Future<void> _health() async {
    if (_process == null || _recovering) return;
    final totals = await trafficTotals();
    // Data still arriving through the proxy means it works, whatever a
    // fresh probe connection does (see the sing-box adapter, 12.10).
    final flowing =
        totals != null && _lastProxyDown >= 0 && totals.down > _lastProxyDown;
    if (totals != null) _lastProxyDown = totals.down;
    if (await measureTunnelLatency() != null || flowing) {
      _healthFailures = 0;
      return;
    }
    _healthFailures++;
    AppLogger.warn(
        'xray health probe failed ($_healthFailures/$_maxHealthFailures)');
    if (_healthFailures >= _maxHealthFailures) {
      _healthFailures = 0;
      await _recover('health check failed');
    }
  }

  /// No reload in Xray: a restart, with the same config — the adapter and
  /// routes come back with it. Up to four tries, then failed.
  Future<void> _recover(String reason) async {
    final path = _lastConfigPath;
    if (path == null || _recovering) return;
    _recovering = true;
    final generation = _generation;
    _emit(VpnNativeState.reconnecting);
    AppLogger.warn('xray recovery ($reason)');
    try {
      for (final delay in const [0, 3, 6, 12]) {
        if (generation != _generation) return;
        if (delay > 0) await Future<void>.delayed(Duration(seconds: delay));
        _stopResilience();
        await _killProcess();
        final exe = await _xrayPath();
        if (exe == null || generation != _generation) return;
        try {
          await _launch(exe, path, generation, reportFailure: false);
          if (_process != null) return;
        } catch (e) {
          AppLogger.warn('xray recovery attempt failed: $e');
        }
      }
      if (generation == _generation) _emit(VpnNativeState.failed);
    } finally {
      _recovering = false;
    }
  }

  // --- Measurements ---

  /// A real HEAD http://www.gstatic.com/generate_204 through the proxy
  /// outbound, via the loopback SOCKS inbound (the name resolved on the
  /// far side) — the same round trip Android measures.
  @override
  Future<int?> measureTunnelLatency() async {
    if (_process == null) return null;
    final sw = Stopwatch()..start();
    Socket? s;
    try {
      s = await Socket.connect(InternetAddress.loopbackIPv4, kXrayProbePort,
          timeout: const Duration(seconds: 2));
      final reader = _SocketReader(s);
      const host = 'www.gstatic.com';
      s.add([5, 1, 0]);
      if (!_eq(await reader.take(2), [5, 0])) return null;
      s.add([5, 1, 0, 3, host.length, ...ascii.encode(host), 0, 80]);
      final head = await reader.take(4);
      if (head[1] != 0) return null;
      final skip = switch (head[3]) {
        1 => 6,
        4 => 18,
        3 => (await reader.take(1))[0] + 2,
        _ => 0,
      };
      await reader.take(skip);
      s.add(ascii.encode(
          'HEAD /generate_204 HTTP/1.1\r\nHost: $host\r\nConnection: close\r\n\r\n'));
      final status = await reader.line();
      return status.contains(' 204') ? sw.elapsedMilliseconds : null;
    } catch (_) {
      return null;
    } finally {
      s?.destroy();
    }
  }

  /// Bytes through the `proxy` outbound since xray started (Xray metrics:
  /// stats.outbound.proxy).
  @override
  Future<({int up, int down})?> trafficTotals() async {
    if (_process == null) return null;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 2)
      ..findProxy = (_) => 'DIRECT';
    try {
      final req = await client
          .getUrl(Uri.parse('http://127.0.0.1:$kXrayMetricsPort/debug/vars'));
      final res = await req.close().timeout(const Duration(seconds: 3));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) return null;
      final stats = (jsonDecode(body) as Map)['stats'] as Map?;
      final proxy = ((stats?['outbound'] as Map?)?['proxy']) as Map?;
      if (proxy == null) return (up: 0, down: 0);
      return (
        up: (proxy['uplink'] as num? ?? 0).toInt(),
        down: (proxy['downlink'] as num? ?? 0).toInt(),
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<int?> pingMs() => measureTunnelLatency();

  Future<String?> _xrayPath() async {
    final dir = File(Platform.resolvedExecutable).parent.path;
    final exe = '$dir${Platform.pathSeparator}xray.exe';
    return await File(exe).exists() ? exe : null;
  }

  void _emit(VpnNativeState s) {
    if (!_controller.isClosed) _controller.add(s);
  }

  void dispose() {
    unawaited(disconnect());
    _controller.close();
  }
}

bool _eq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Reads exact byte counts / a line from a socket, with a timeout.
class _SocketReader {
  _SocketReader(Socket s) {
    _sub = s.listen((d) {
      _buf.addAll(d);
      _wake?.complete();
      _wake = null;
    }, onDone: () {
      _done = true;
      _wake?.complete();
      _wake = null;
    }, onError: (_) {
      _done = true;
      _wake?.complete();
      _wake = null;
    });
  }

  late final StreamSubscription<List<int>> _sub;
  final _buf = <int>[];
  Completer<void>? _wake;
  bool _done = false;
  static const _timeout = Duration(seconds: 6);

  Future<void> _more() {
    if (_done) throw const SocketException('closed');
    _wake = Completer<void>();
    return _wake!.future.timeout(_timeout);
  }

  Future<List<int>> take(int n) async {
    while (_buf.length < n) {
      await _more();
    }
    final out = _buf.sublist(0, n);
    _buf.removeRange(0, n);
    return out;
  }

  Future<String> line() async {
    while (true) {
      final i = _buf.indexOf(10);
      if (i >= 0) {
        final out = ascii.decode(_buf.sublist(0, i), allowInvalid: true);
        _buf.removeRange(0, i + 1);
        unawaited(_sub.cancel());
        return out;
      }
      await _more();
    }
  }
}
