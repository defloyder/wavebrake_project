import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../../core/logging/app_logger.dart';
import '../core_api/models.dart';
import 'vpn_adapter.dart';

/// Loopback-only port for sing-box's Clash-API-compatible control server
/// (`experimental.clash_api` below) — enables a live `PUT /configs` reload
/// (re-dials outbounds without tearing down the TUN interface/routes) as
/// the preferred automatic-recovery path, before falling back to a full
/// process restart. Bound to 127.0.0.1 only, never 0.0.0.0 — this must
/// never need a firewall exception or be reachable from the network.
/// Fixed rather than ephemeral: nothing hands the assigned port back once
/// sing-box picks one, so the adapter has to agree on it up front with the
/// generated config.
const _kClashApiPort = 47983;

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
  Timer? _rivalVpnWatch;

  // Set right before we ourselves kill `_process` (a user disconnect(), or
  // the kill-then-relaunch step of an automatic restart) and checked in the
  // exitCode handler below — an exit we asked for is routine cleanup, not
  // evidence sing-box crashed and needs automatic recovery.
  bool _expectedExit = false;

  // The link an automatic restart relaunches with — connect()'s caller only
  // ever hands the adapter a profile at the start of a manual connect, so a
  // later crash/network-change recovery has nothing to rebuild sing-box's
  // args from unless it's cached here. The config file itself is always
  // freshly rewritten from this before a restart (see
  // _restartSingBoxProcess) rather than reusing the path from last time.
  ShareLink? _lastLink;

  // --- Automatic recovery (network-change + health-check driven) ---
  //
  // Windows has no equivalent of Android's separate TUN/engine layers (see
  // this file's class doc) — sing-box owns both together, so "restart just
  // the engine" isn't possible here. Two recovery paths instead, tried in
  // priority order per attempt (see _attemptOneRecovery):
  //   1. sing-box's Clash API `PUT /configs` reload (_kClashApiPort) —
  //      genuinely non-disruptive when it works: same process, same TUN
  //      interface/routes, just re-dials outbounds. Skipped outright when
  //      sing-box itself has exited (nothing to reload).
  //   2. A full kill + relaunch of sing-box.exe with the same config —
  //      identical to what disconnect()+connect() already do today, just
  //      triggered automatically instead of requiring the user to notice.
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _networkDebounceTimer;
  Timer? _healthCheckTimer;
  int _consecutiveHealthFailures = 0;

  // Bumped on every new recovery trigger and on disconnect() — lets a
  // superseded recovery loop (a newer trigger fired, or the user/system
  // disconnected while one was running) recognize itself as stale and stop,
  // the same pattern _generation already uses for connect()/disconnect().
  int _recoveryGeneration = 0;
  bool _recoveryInProgress = false;

  // Per-attempt "did this resolve in time" timer. Explicitly cancelled by
  // every exit path of _attemptOneRecovery — success AND this attempt's own
  // failure — never left to just get superseded by the generation check.
  // This mirrors a real bug already fixed on the mobile side: a
  // connect-watchdog Timer there was only ever cancelled implicitly via a
  // staleness check, and a deferred-under-load firing after a successful
  // connection tore down an otherwise healthy tunnel. Guarding on
  // generation alone only protects against a NEWER attempt superseding an
  // OLDER one — it does nothing to stop THIS SAME attempt's own timer from
  // firing after THIS SAME attempt already succeeded, which is exactly what
  // happened there.
  Timer? _recoveryWatchdog;

  static const _networkChangeDebounce = Duration(milliseconds: 1200);
  static const _healthCheckInterval = Duration(seconds: 20);
  static const _maxConsecutiveHealthFailures = 2;
  static const _reloadSettleDelay = Duration(seconds: 3);
  // Bounds a single recovery attempt (reload-then-probe, or a full
  // relaunch). Set above connect()'s own 25s ready-timeout so a
  // legitimately slow-but-succeeding relaunch (a lossy path's Hysteria2/
  // QUIC handshake — see that timeout's own comment) isn't mistaken for a
  // failed attempt and retried on top of itself.
  static const _recoveryAttemptTimeout = Duration(seconds: 30);
  // Same schedule as the mobile resilience layer's connect-watchdog
  // backoff, reused here for consistency rather than re-derived — the
  // failure modes it's smoothing over (a flaky path needing a moment
  // before a retry actually has a chance of working) are the same shape on
  // both platforms.
  static const _recoveryBackoff = [
    Duration(seconds: 3),
    Duration(seconds: 6),
    Duration(seconds: 12),
    Duration(seconds: 20),
  ];

  static const _recoveryReasonNetworkChange = 'network change';
  static const _recoveryReasonHealthCheckFailed = 'health check failed';
  static const _recoveryReasonProcessExited = 'sing-box exited unexpectedly';

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
    _lastLink = link;

    try {
      await _launchAndAwaitReady(exePath, configPath, generation);
    } catch (e) {
      throw StateError('$e');
    }
  }

  /// Starts sing-box.exe with [configPath] and waits for it to report the
  /// TUN interface + routes are up, emitting states along the way. Shared
  /// by [connect] (a fresh, user-initiated attempt) and
  /// [_restartSingBoxProcess] (an automatic-recovery relaunch) — both need
  /// the exact same "start it, watch its logs for readiness, bound the
  /// wait, wire up the exit handler" sequence, just from different
  /// callers with different [generation] provenance.
  Future<void> _launchAndAwaitReady(
      String exePath, String configPath, int generation) async {
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
        // A newer connect()/restart (or a disconnect()) already moved on
        // while sing-box was launching — this attempt is stale. Kill it
        // now rather than leaving it running alongside whatever
        // superseded it; there is nothing left here that should touch
        // `_process` or emit a state for this generation.
        process.kill(ProcessSignal.sigterm);
        return;
      }
      _process = process;
      _expectedExit = false;

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
          _startRivalVpnWatch();
          _startResilience();
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
            completer.completeError(
                StateError('sing-box exited early (code $code)'));
          }
          return;
        }
        if (_expectedExit) {
          // A kill we ourselves asked for (disconnect(), or the
          // kill-then-relaunch step of an automatic restart) — routine
          // cleanup, not evidence sing-box crashed.
          _emit(code == 0 ? VpnNativeState.idle : VpnNativeState.failed);
          return;
        }
        // sing-box was connected and up and exited entirely on its own —
        // a real crash. Not recoverable via the Clash API (there's no
        // process left to send a reload to); go straight to the
        // full-restart fallback for this failure mode.
        AppLogger.warn(
            'sing-box exited unexpectedly while connected (code $code)');
        _stopRivalVpnWatch();
        _stopResilience();
        _process = null;
        _beginRecovery(_recoveryReasonProcessExited);
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
        // A plain kill, not the full disconnect() — disconnect() also
        // aborts any in-flight automatic-recovery loop (_abortRecovery()),
        // which would wrongly cancel *this* recovery attempt's own retry
        // schedule when this helper is called from
        // [_restartSingBoxProcess] rather than [connect].
        await _killProcessOnly();
        _emit(VpnNativeState.failed);
      }
      throw StateError('sing-box did not report ready in time');
    }
  }

  @override
  Future<void> disconnect() async {
    _stopRivalVpnWatch();
    _stopResilience();
    _abortRecovery();
    await _killProcessOnly();
  }

  /// Kills the current sing-box process (if any) and tears down its pipe
  /// subscriptions, without touching recovery/resilience state — the part
  /// of the old `disconnect()` body that both the real, public
  /// `disconnect()` and an automatic restart's "kill the old one before
  /// relaunching" step need, but only the former should also abort a
  /// recovery loop or stop the resilience timers (an automatic restart is
  /// running *from inside* that loop and those timers get re-armed the
  /// moment the relaunch succeeds anyway).
  Future<void> _killProcessOnly() async {
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    final process = _process;
    _process = null;
    if (process != null) {
      _expectedExit = true;
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

  // --- Network-change detection ---

  void _startResilience() {
    _stopResilience();
    _consecutiveHealthFailures = 0;
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
    _healthCheckTimer = Timer.periodic(
      _healthCheckInterval,
      (_) => unawaited(_runHealthCheck()),
    );
  }

  void _stopResilience() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _networkDebounceTimer?.cancel();
    _networkDebounceTimer = null;
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (_process == null) return;
    // Debounced so a rapid down/up flap (an adapter briefly re-negotiating
    // DHCP, a laptop's Wi-Fi/Ethernet handoff) doesn't fire two separate
    // recovery attempts back to back — 1200ms matches the mobile
    // resilience layer's own debounce for the same reason: comfortably
    // longer than a routine flap, still short enough that a genuine
    // network change gets noticed quickly.
    _networkDebounceTimer?.cancel();
    _networkDebounceTimer = Timer(_networkChangeDebounce, () {
      if (_process == null) return;
      if (results.every((r) => r == ConnectivityResult.none)) {
        // Fully offline right now — nothing to nudge until connectivity
        // actually returns; that return is itself a future
        // onConnectivityChanged event, which re-enters this same path.
        AppLogger.debug(
            'Network reported fully offline — waiting for it to return before attempting recovery');
        return;
      }
      AppLogger.warn('Network change detected ($results)');
      _beginRecovery(_recoveryReasonNetworkChange);
    });
  }

  // --- Health check ---

  /// Verifies the tunnel is actually passing traffic, not just that
  /// sing-box.exe is still a live PID — a raw TCP connect through the
  /// tunnel to a reliable external host, mirroring the mobile resilience
  /// layer's protected-socket probe. Windows has no VpnService-style
  /// self-routing loop to protect against here (there's no "protect()" to
  /// call): the app's own traffic already rides the system TUN like
  /// everything else, which is exactly what needs verifying. 1.1.1.1:443
  /// is already a trusted, always-up dependency of this same adapter (see
  /// the DNS server in [ShareLink.toSingBoxConfig]), so a failure here
  /// that succeeds outside the tunnel is unambiguous evidence the tunnel
  /// itself — not the wider internet — is the problem.
  Future<bool> _probeTunnel() async {
    Socket? socket;
    try {
      socket = await Socket.connect('1.1.1.1', 443,
          timeout: const Duration(seconds: 5));
      return true;
    } catch (e) {
      AppLogger.debug('Tunnel health probe failed: $e');
      return false;
    } finally {
      socket?.destroy();
    }
  }

  Future<void> _runHealthCheck() async {
    if (_process == null) return;
    if (await _probeTunnel()) {
      _consecutiveHealthFailures = 0;
      return;
    }
    _consecutiveHealthFailures++;
    AppLogger.warn(
        'Tunnel health probe failed ($_consecutiveHealthFailures/$_maxConsecutiveHealthFailures)');
    // Requires back-to-back failures, not just one: a single dropped probe
    // is well within normal noise for a real network (one lossy TCP
    // handshake) and shouldn't itself trigger a recovery cycle.
    if (_consecutiveHealthFailures >= _maxConsecutiveHealthFailures) {
      _consecutiveHealthFailures = 0;
      _beginRecovery(_recoveryReasonHealthCheckFailed);
    }
  }

  // --- Recovery orchestration ---

  void _beginRecovery(String reason) {
    if (_lastLink == null) return; // never actually connected
    if (_recoveryInProgress) {
      AppLogger.debug('Recovery already in progress, ignoring: $reason');
      return;
    }
    unawaited(_runRecoveryLoop(reason));
  }

  void _abortRecovery() {
    _recoveryGeneration++;
    _recoveryInProgress = false;
    _recoveryWatchdog?.cancel();
    _recoveryWatchdog = null;
  }

  Future<void> _runRecoveryLoop(String reason) async {
    final generation = ++_recoveryGeneration;
    _recoveryInProgress = true;
    AppLogger.warn('Automatic recovery starting ($reason)');
    _emit(VpnNativeState.reconnecting);

    for (var attempt = 0; attempt <= _recoveryBackoff.length; attempt++) {
      if (generation != _recoveryGeneration) return;
      final success = await _attemptOneRecovery(
          reason: reason, attempt: attempt, generation: generation);
      if (generation != _recoveryGeneration) return;
      if (success) {
        AppLogger.info(
            'Automatic recovery succeeded on attempt ${attempt + 1} ($reason)');
        _recoveryInProgress = false;
        return;
      }
      if (attempt == _recoveryBackoff.length) break;
      final delay = _recoveryBackoff[attempt];
      AppLogger.warn(
          'Recovery attempt ${attempt + 1} failed ($reason), retrying in ${delay.inSeconds}s');
      await Future<void>.delayed(delay);
    }
    if (generation == _recoveryGeneration) {
      _recoveryInProgress = false;
      AppLogger.error(
          'Automatic recovery exhausted retries ($reason) — surfacing failure');
      _emit(VpnNativeState.failed);
    }
  }

  /// One recovery attempt: prefer the Clash API reload (non-disruptive —
  /// same process, TUN interface and routes stay up) unless sing-box
  /// itself has already exited, in which case there's nothing to reload
  /// and this goes straight to a full restart. Bounded by
  /// [_recoveryAttemptTimeout] via [_recoveryWatchdog], which is
  /// unconditionally cancelled on every exit from this method — see that
  /// field's own doc for why that has to be unconditional rather than
  /// relying on the generation check alone.
  Future<bool> _attemptOneRecovery({
    required String reason,
    required int attempt,
    required int generation,
  }) async {
    AppLogger.info(
        'Recovery attempt ${attempt + 1}/${_recoveryBackoff.length + 1} ($reason)');

    final completer = Completer<bool>();
    _recoveryWatchdog?.cancel();
    _recoveryWatchdog = Timer(_recoveryAttemptTimeout, () {
      if (!completer.isCompleted) completer.complete(false);
    });

    void finish(bool result) {
      // Unconditional: cancels this attempt's watchdog whether it just
      // succeeded or just failed on its own terms, not only when a newer
      // generation supersedes it.
      _recoveryWatchdog?.cancel();
      _recoveryWatchdog = null;
      if (!completer.isCompleted) completer.complete(result);
    }

    unawaited(() async {
      try {
        final processCrashed =
            reason == _recoveryReasonProcessExited || _process == null;
        if (!processCrashed) {
          final reloaded = await _tryClashApiReload();
          if (reloaded && generation == _recoveryGeneration) {
            await Future<void>.delayed(_reloadSettleDelay);
            if (generation == _recoveryGeneration && await _probeTunnel()) {
              AppLogger.info('Recovery via Clash API reload succeeded');
              if (generation == _recoveryGeneration) {
                _emit(VpnNativeState.connected);
              }
              finish(true);
              return;
            }
          }
        }
        if (generation != _recoveryGeneration) {
          finish(false);
          return;
        }
        AppLogger.warn(
            'Clash API reload unavailable or insufficient — falling back to a full sing-box restart');
        final restarted = await _restartSingBoxProcess(generation: generation);
        finish(generation == _recoveryGeneration && restarted);
      } catch (e) {
        AppLogger.warn('Recovery attempt threw: $e');
        finish(false);
      }
    }());

    return completer.future;
  }

  /// Sends sing-box's Clash-API-compatible `PUT /configs` with an empty
  /// body — its documented "reload from the same config sing-box was
  /// started with" call (equivalent to sending it SIGHUP). Since this
  /// adapter's config file at [_lastConfigPath] doesn't change between
  /// attempts, this is used purely as a non-disruptive nudge to make
  /// sing-box re-dial its outbounds, not to hand it new config content.
  Future<bool> _tryClashApiReload() async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final request = await client
          .putUrl(Uri.parse('http://127.0.0.1:$_kClashApiPort/configs'))
          .timeout(const Duration(seconds: 3));
      request.headers.contentType = ContentType.json;
      request.write('{}');
      final response = await request.close().timeout(const Duration(seconds: 5));
      await response.drain<void>();
      final ok = response.statusCode == 204 || response.statusCode == 200;
      AppLogger.debug(
          'Clash API reload ${ok ? 'accepted' : 'rejected'} (status ${response.statusCode})');
      return ok;
    } catch (e) {
      AppLogger.debug('Clash API reload unreachable: $e');
      return false;
    } finally {
      client?.close(force: true);
    }
  }

  /// Kills the current sing-box process (if any — it may already be dead,
  /// e.g. after a crash) and relaunches it with the same link/config this
  /// adapter last connected with. The full-restart fallback for when the
  /// Clash API reload can't help (sing-box itself has exited) or didn't
  /// actually fix the tunnel.
  Future<bool> _restartSingBoxProcess({required int generation}) async {
    final link = _lastLink;
    if (link == null) return false;

    await _killProcessOnly();
    if (generation != _recoveryGeneration) return false;

    final exePath = await _singBoxPath();
    if (exePath == null) {
      AppLogger.error(
          'sing-box.exe not found next to the app during automatic recovery');
      return false;
    }

    String configPath;
    try {
      configPath = await _writeConfig(link);
    } catch (e) {
      AppLogger.error('Failed to rewrite sing-box config during recovery: $e');
      return false;
    }

    if (generation != _recoveryGeneration) return false;
    final launchGeneration = ++_generation;

    try {
      await _launchAndAwaitReady(exePath, configPath, launchGeneration);
    } catch (e) {
      AppLogger.warn('Recovery restart failed to relaunch sing-box: $e');
      return false;
    }
    return launchGeneration == _generation && generation == _recoveryGeneration;
  }

  // Real gap this exists to fix: unlike Android (where establishing a new
  // VpnService from another app automatically revokes this one —
  // WaveEngineVpnService.onRevoke(), already handled), Windows has no OS
  // -level exclusivity between VPN adapters at all. Two tunnels racing
  // for the default route causes real problems (traffic split
  // unpredictably between them, or a "connected" tunnel that's actually
  // being starved by the other one) — WaveBreak needs to notice another
  // VPN coming up on its own and get out of the way rather than silently
  // staying in a stale "connected" state alongside it.
  //
  // No Windows API surfaced through dart:io exposes "is this adapter a
  // VPN" directly (NetworkInterface only gives a name + addresses, not
  // the IF_TYPE_PPP/IF_TYPE_TUNNEL flags GetAdaptersAddresses has at the
  // Win32 level) — this is a heuristic on adapter NAME instead, checked
  // periodically while connected. Real vendors' adapters reliably show
  // up under recognizable names (see _rivalVpnNamePattern), and our own
  // tunnel is always named exactly "wavebreak" (interface_name in
  // _buildConfig above), so excluding that one name is precise, not
  // itself a heuristic.
  static const _rivalVpnCheckInterval = Duration(seconds: 8);

  static final _rivalVpnNamePattern = RegExp(
    r'\b(vpn|tap-windows|tap0|wintun|openvpn|wireguard|nordlynx|'
    r'pptp|l2tp|ipsec|tunnelbear|protonvpn|expressvpn|surfshark|'
    r'nordvpn|cisco anyconnect|globalprotect|forticlient|zerotier|tailscale)\b',
    caseSensitive: false,
  );

  void _startRivalVpnWatch() {
    _rivalVpnWatch?.cancel();
    _rivalVpnWatch = Timer.periodic(
      _rivalVpnCheckInterval,
      (_) => unawaited(_checkForRivalVpn()),
    );
  }

  void _stopRivalVpnWatch() {
    _rivalVpnWatch?.cancel();
    _rivalVpnWatch = null;
  }

  Future<void> _checkForRivalVpn() async {
    if (_process == null) return;
    try {
      final interfaces = await NetworkInterface.list(includeLoopback: false);
      final rival = interfaces.any((iface) {
        final name = iface.name.toLowerCase();
        if (name.contains('wavebreak')) return false;
        return _rivalVpnNamePattern.hasMatch(name);
      });
      if (rival && _process != null) {
        AppLogger.warn(
            'Another VPN adapter detected while connected — disconnecting to avoid two tunnels racing for the default route');
        await disconnect();
        _emit(VpnNativeState.idle);
      }
    } catch (e) {
      // Best-effort — a failed interface enumeration (a transient WMI/
      // network-stack hiccup) isn't itself evidence of a rival VPN and
      // shouldn't disconnect anything on its own.
      AppLogger.debug('Rival VPN check failed: $e');
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
      json = jsonDecode(utf8.decode(base64.decode(base64.normalize(b64))))
          as Map<String, dynamic>;
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
      credential:
          str('id') ?? (throw const FormatException('vmess link missing id')),
      host:
          str('add') ?? (throw const FormatException('vmess link missing add')),
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
    final body =
        hashIndex >= 0 ? withoutScheme.substring(0, hashIndex) : withoutScheme;

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
      if (sep < 0) {
        throw const FormatException('shadowsocks link missing method:password');
      }
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
    if (legacyAt < 0) {
      throw const FormatException('shadowsocks link missing host');
    }
    final methodPass = decoded.substring(0, legacyAt);
    final hostPort = decoded.substring(legacyAt + 1);
    final sep = methodPass.indexOf(':');
    if (sep < 0) {
      throw const FormatException('shadowsocks link missing method:password');
    }
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
      'outbounds': [
        _outbound(),
        {'type': 'direct', 'tag': 'direct'}
      ],
      // No separate DNS outbound/rule — that pattern was removed in
      // sing-box 1.13 (a "dns" outbound type is a hard config error now).
      // DNS queries just ride the tunnel like everything else via
      // `final: proxy` below, which also avoids leaking them outside it.
      'route': {
        'auto_detect_interface': true,
        'final': 'proxy',
      },
      // Enables sing-box's Clash-API-compatible control server so
      // WindowsVpnAdapter's automatic-recovery loop can try a live
      // `PUT /configs` reload (re-dials outbounds without tearing down
      // the TUN interface/routes) before falling back to a full process
      // restart. 127.0.0.1 only — see _kClashApiPort's doc for why this
      // must never bind 0.0.0.0 or need a firewall exception.
      'experimental': {
        'clash_api': {
          'external_controller': '127.0.0.1:$_kClashApiPort',
        },
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
      if (fingerprint != null)
        'utls': {'enabled': true, 'fingerprint': fingerprint},
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
    final effectiveFlow =
        network == 'tcp' && security == 'reality' ? flow : null;
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
