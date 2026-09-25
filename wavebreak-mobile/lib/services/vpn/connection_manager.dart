import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env/app_env.dart';
import '../../core/errors/app_exception.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/logging/app_logger.dart';
import '../../core/storage/prefs_store.dart';
import '../../core/storage/secure_store.dart';
import '../../features/shared/data_providers.dart';
import '../analytics/analytics.dart';
import '../core_api/models.dart';
import '../device/device_service.dart';
import 'connection_test_service.dart';
import '../providers.dart';
import 'native_vpn_adapter.dart';
import 'platform_vpn_adapter.dart';
import 'speed_test_service.dart';
import 'vpn_adapter.dart';
import 'vpn_notification_meta.dart';
import 'windows_vpn_adapter.dart';

enum ConnectionStatus {
  idle,
  requestingProfile,
  connecting,
  // A grant was created but Core's config endpoint hasn't returned
  // `config_status: "ready"` yet — real WireGuard material doesn't exist
  // server-side yet (see docs/vpn-config-contract.md). The app must not
  // hand anything to the native tunnel in this state.
  configPending,
  connected,
  disconnecting,
  error,
}

class WbConnectionState {
  const WbConnectionState({
    required this.status,
    this.connectedAt,
    this.error,
    this.location = LocationItem.auto,
    this.grantId,
  });

  final ConnectionStatus status;
  final DateTime? connectedAt;
  final AppException? error;
  final LocationItem location;

  /// The active access grant backing the current/pending connection, if
  /// any — needed so disconnecting can revoke it on Core rather than just
  /// dropping the local tunnel.
  final String? grantId;

  bool get isBusy =>
      status == ConnectionStatus.requestingProfile ||
      status == ConnectionStatus.connecting ||
      status == ConnectionStatus.disconnecting;

  WbConnectionState copyWith({
    ConnectionStatus? status,
    DateTime? connectedAt,
    AppException? error,
    LocationItem? location,
    String? grantId,
    bool clearError = false,
    bool clearConnectedAt = false,
    bool clearGrantId = false,
  }) {
    return WbConnectionState(
      status: status ?? this.status,
      connectedAt: clearConnectedAt ? null : (connectedAt ?? this.connectedAt),
      error: clearError ? null : (error ?? this.error),
      location: location ?? this.location,
      grantId: clearGrantId ? null : (grantId ?? this.grantId),
    );
  }
}

final vpnAdapterProvider = Provider<VpnAdapter>((ref) {
  if (AppEnv.useSimulatedVpn) return SimulatedVpnAdapter();
  // The pilot's actual protocol is VLESS REALITY, which has a real native
  // tunnel per platform: an embedded Xray-core (plus Hysteria2 for custom
  // links, see native_vpn_adapter.dart) on Android, a bundled sing-box on
  // Windows (see windows_vpn_adapter.dart). WireGuard's PlatformVpnAdapter
  // stays the fallback for a backend that still speaks the older WireGuard
  // contract, whose native side isn't implemented yet.
  if (AppEnv.accessProtocol == 'vless') {
    if (Platform.isWindows) {
      final adapter = WindowsVpnAdapter();
      ref.onDispose(adapter.dispose);
      return adapter;
    }
    final adapter = NativeVpnAdapter();
    ref.onDispose(adapter.dispose);
    return adapter;
  }
  final adapter = PlatformVpnAdapter();
  ref.onDispose(adapter.dispose);
  return adapter;
});

final connectionManagerProvider =
    NotifierProvider<ConnectionManager, WbConnectionState>(
  ConnectionManager.new,
);

class ConnectionManager extends Notifier<WbConnectionState> {
  StreamSubscription<VpnNativeState>? _sub;
  final _analytics = const Analytics();

  /// Keeps polling `grantConfig` in the background while the UI sits on
  /// `configPending`, well past the first quick retry window — the
  /// pilot's node-agent can take longer than that to ack a fresh grant.
  /// Guarded on [_pendingGrantId] so a stale timer from an abandoned
  /// attempt can never resurrect a connection the user already left.
  Timer? _pendingConfigPoll;
  String? _pendingGrantId;

  /// Bumped at the start of every [connect] call and checked after each
  /// `await` inside it — lets [cancelConnect] make an in-flight attempt's
  /// own eventual success/failure a no-op instead of it clobbering
  /// whatever state a user-initiated cancel already moved to. Dart has no
  /// way to actually abort an in-flight Future, so this is the standard
  /// stand-in for that.
  int _connectGeneration = 0;

  @override
  WbConnectionState build() {
    final adapter = ref.watch(vpnAdapterProvider);
    _sub?.cancel();
    _sub = adapter.states.listen(_onNative);
    ref.onDispose(() {
      _sub?.cancel();
      _cancelPendingPoll();
    });

    final savedId = PrefsStore.getString(PrefsStore.lastLocationId);
    return WbConnectionState(
      status: ConnectionStatus.idle,
      // This placeholder only lives until hydrateLocations() swaps in the
      // real item once the actual location list has loaded — it carries
      // no country code of its own on purpose. A custom/BYO server's id is
      // a random UUID (see share_link_parsing.dart), not a "REGION-..."
      // style code, so guessing a country from its first hyphen-delimited
      // segment (the old approach here) fed accentColorFor() garbage like
      // "A8128415" — which still hashes to *some* color, so the very first
      // frame after a restart would flash a wrong, essentially random
      // flag-colored tint (confirmed on-device: looked like Turkey's flag
      // for one custom Netherlands server) until hydration corrected it a
      // moment later. An empty code reads as the neutral brand color
      // instead (see flag_colors.dart's `_generatedAccentFor`), which is
      // the right default for "don't actually know yet".
      location: savedId == null || savedId == LocationItem.auto.id
          ? LocationItem.auto
          : LocationItem(
              id: savedId,
              countryCode: '',
              country: '',
              city: '',
              available: true,
            ),
    );
  }

  /// Picks a location. If we're currently connected (or mid-connect) to a
  /// *different* server, this is really a request to switch servers, not
  /// just to change what's selected for next time — so it tears down the
  /// old tunnel and opens a fresh one to the new location, with its own
  /// new access profile and a `connectedAt` that reflects the new session
  /// rather than leaving the old server's stale connect time on screen.
  ///
  /// That teardown is deliberately silent — no visible `disconnecting`
  /// step. Surfacing "Disconnected" for a moment while switching servers
  /// reads as if the connection dropped; a switch should read as one
  /// continuous "connecting to the new location" instead.
  Future<void> selectLocation(
    LocationItem location, {
    bool subscriptionActive = false,
  }) async {
    final previous = state.location;
    state = state.copyWith(location: location);
    unawaited(PrefsStore.setString(PrefsStore.lastLocationId, location.id));

    final switchingServers = previous.id != location.id &&
        (state.status == ConnectionStatus.connected ||
            state.status == ConnectionStatus.configPending ||
            state.status == ConnectionStatus.connecting ||
            state.status == ConnectionStatus.requestingProfile);
    if (!switchingServers) return;

    state = state.copyWith(
        status: ConnectionStatus.requestingProfile, clearError: true);
    // Deliberately NOT _teardownTunnel() first. That sends an explicit
    // disconnect, which on Android tears down the whole WaveEngineVpnService
    // (stopSelf()) and immediately starts a new one for the reconnect —
    // and if the old process hadn't actually finished dying yet, the new
    // one's protect socket server could fail to bind its Unix domain
    // socket at all ("Address already in use"). Confirmed on-device: once
    // that happened, the OLD process's binding never got released for the
    // rest of the session (no amount of retrying helped), silently
    // breaking protect() — and therefore real traffic — for every
    // connection attempted afterward, not just the one mid-switch.
    // connect() below sends a plain "connect" call that reuses the
    // ALREADY-RUNNING service instance; WaveEngineVpnService.kt's Go-side
    // self-healing (stopXrayLocked/stopLocked/stopTun2SocksLocked, called
    // defensively from Start when already running) and Android's own
    // VpnService.Builder().establish() (which atomically swaps the old TUN
    // fd for the new one within the same process) already handle
    // switching the live engine over — no process restart needed, so
    // there's no socket to lose in the first place.
    await connect(subscriptionActive: subscriptionActive);
  }

  void hydrateLocations(List<LocationItem> locations) {
    if (state.location.isAuto) return;
    final match = locations.where((l) => l.id == state.location.id);
    if (match.isNotEmpty) {
      state = state.copyWith(location: match.first);
    }
  }

  Future<void> toggle({required bool subscriptionActive}) async {
    if (state.isBusy) {
      // requestingProfile/connecting: a long grant/handshake wait is
      // exactly when a user is most likely to tap again wanting out, and
      // until now that tap was silently swallowed. disconnecting is left
      // alone — cancelling a disconnect already in flight isn't a
      // meaningful action.
      if (state.status == ConnectionStatus.requestingProfile ||
          state.status == ConnectionStatus.connecting) {
        await cancelConnect();
      }
      return;
    }
    if (state.status == ConnectionStatus.connected ||
        state.status == ConnectionStatus.configPending) {
      await disconnect();
      return;
    }
    await connect(subscriptionActive: subscriptionActive);
  }

  /// Backs out of an in-flight [connect] — see [_connectGeneration].
  Future<void> cancelConnect() async {
    _connectGeneration++;
    unawaited(HapticFeedback.lightImpact());
    _cancelPendingPoll();
    await _teardownTunnel();
    state = state.copyWith(
      status: ConnectionStatus.idle,
      clearConnectedAt: true,
      clearError: true,
      clearGrantId: true,
    );
  }

  Future<void> connect({required bool subscriptionActive}) async {
    _cancelPendingPoll();
    final generation = ++_connectGeneration;
    final location = state.location;
    // Custom (external) servers are the user's own — no WAVEBREAK
    // subscription is required to use them.
    if (!location.isCustom && !subscriptionActive) {
      state = state.copyWith(
        status: ConnectionStatus.error,
        error: AppException(AppErrorKind.subscriptionRequired),
      );
      return;
    }

    _analytics.event('connect_button_pressed');
    unawaited(HapticFeedback.lightImpact());
    state = state.copyWith(
      status: ConnectionStatus.requestingProfile,
      clearError: true,
    );

    try {
      // Resolved BEFORE branching on isCustom: Auto isn't itself custom,
      // but it can resolve to one of WAVEBREAK's own bundled pilot nodes
      // (see bundled_locations.dart), which ARE isCustom (they connect via
      // a raw share link, not a Core-managed nodeId) — deciding the branch
      // off the original `location` instead of the resolved `target` sent
      // a bundled pick straight into createAccessGrant with its random
      // UUID as if it were a real Core nodeId, which Core would just
      // reject.
      //
      // For a manually-picked location this is always a single-item list
      // (unchanged behavior: exactly one attempt, exactly one error on
      // failure). For Auto it's up to [_maxAutoCandidates] candidates
      // ranked fastest-first — a real handshake attempt against the top
      // candidate is what actually verifies a location works, not just
      // that its port answers a TCP SYN (see _rankCandidates's doc for why
      // that distinction matters: REALITY/DPI-adjacent failures accept the
      // TCP connect and then go nowhere). If that real attempt throws —
      // [NativeVpnAdapter.connect]'s own 20s timeout already tears itself
      // down cleanly on failure — silently try the next-best candidate
      // instead of leaving the user connected to nothing.
      final candidates = await _rankCandidates(location);
      Object lastError = AppException(AppErrorKind.locationUnavailable);
      // Only Auto with more than one candidate to actually pick between
      // goes on to the throughput probe below — a manual pick (or an Auto
      // resolution that only had one online candidate) keeps the exact
      // pre-existing behavior: one real handshake, done.
      final probeCandidates = location.isAuto && candidates.length > 1;
      LocationItem? bestProbedTarget;
      double bestProbedMbps = -1;
      for (var i = 0; i < candidates.length; i++) {
        if (generation != _connectGeneration) return;
        try {
          await _attemptConnect(candidates[i], generation: generation);
        } catch (error) {
          if (generation != _connectGeneration) return;
          lastError = error;
          final isLastCandidate = i == candidates.length - 1;
          if (isLastCandidate) {
            // A later, higher-ranked-by-latency candidate failed outright,
            // but an earlier one already proved out a real handshake and
            // (if we got that far) a throughput sample — reconnect to that
            // rather than ending on a hard failure when a working server
            // is available.
            if (bestProbedTarget != null) {
              try {
                await _attemptConnect(bestProbedTarget, generation: generation);
                return;
              } catch (_) {}
            }
            break;
          }
          AppLogger.warn('Auto-connect candidate failed, trying next');
          // Best-effort: don't leave a half-created grant from the failed
          // candidate sitting active on Core while trying the next one.
          final staleGrantId = state.grantId;
          if (staleGrantId != null) {
            try {
              await ref
                  .read(coreGatewayProvider)
                  .revokeAccessGrant(staleGrantId);
            } catch (_) {}
          }
          state = state.copyWith(
              clearGrantId: true, status: ConnectionStatus.requestingProfile);
          continue;
        }

        // A real handshake just succeeded. For a manual pick (or a
        // single-candidate Auto resolution) that's the whole job, same as
        // before this change.
        if (!probeCandidates) return;
        if (generation != _connectGeneration) return;

        // Auto with real alternatives to weigh: "it connected" isn't the
        // same question as "it's actually fast" — a REALITY/Hysteria
        // server can complete a genuine handshake and still crawl under
        // load (congested uplink, an overloaded box, etc.), which a bare
        // latency ranking or a successful-connect check can never see.
        // Sample real throughput through the tunnel that's live right
        // now, via the same quick probe the dedicated speed-test tab
        // uses, just far smaller/faster (see SpeedTestService.
        // quickDownloadProbeMbps's own doc) since this runs inline in the
        // connect flow, once per candidate, up to _maxAutoCandidates times.
        double? probedMbps;
        try {
          probedMbps = await SpeedTestService().quickDownloadProbeMbps();
        } catch (_) {
          probedMbps = null;
        }
        if (generation != _connectGeneration) return;
        final mbps = probedMbps ?? 0.0;
        AppLogger.warn(
            'Auto-connect candidate throughput: ${mbps.toStringAsFixed(1)} Mbps');

        if (mbps >= _goodEnoughAutoMbps) {
          // Fast enough — stop here rather than running the full sweep of
          // every ranked candidate the coordinator explicitly wanted
          // avoided.
          return;
        }

        if (mbps > bestProbedMbps) {
          bestProbedMbps = mbps;
          bestProbedTarget = candidates[i];
        }

        final isLastCandidate = i == candidates.length - 1;
        if (isLastCandidate) {
          // None of the probed candidates cleared the bar. Stay connected
          // rather than tearing down a working (if not probed-fastest)
          // tunnel — but if an earlier candidate measured faster than
          // this last one, reconnect to that instead of just settling for
          // whichever happened to be tried last.
          if (bestProbedTarget != null &&
              bestProbedTarget.id != candidates[i].id) {
            try {
              await _attemptConnect(bestProbedTarget, generation: generation);
            } catch (_) {
              // Already connected to the current (last-tried) candidate —
              // falling back to that is still a real, working connection,
              // not a hard failure.
            }
          }
          return;
        }

        // Below the "good enough" bar with more candidates left to try —
        // tear this one down and move to the next-ranked candidate rather
        // than settling this early.
        await _teardownTunnel();
        if (generation != _connectGeneration) return;
        state = state.copyWith(
            clearGrantId: true, status: ConnectionStatus.requestingProfile);
      }
      throw lastError;
    } catch (error) {
      if (generation != _connectGeneration) return;
      AppLogger.warn('Connection failed');
      _analytics.event('connection_error');
      final mapped = error is AppException
          ? error
          : AppException(AppErrorKind.connectionFailed);
      state = state.copyWith(
        status: ConnectionStatus.error,
        error: mapped,
        clearConnectedAt: true,
      );
    }
  }

  /// One attempt against a single resolved [target] — everything
  /// [connect] used to do inline before it needed to retry across
  /// multiple Auto candidates. Throws on failure (including a
  /// [_finishConnecting] failure, via `rethrowOnError: true`) rather than
  /// landing on `error` state itself, so [connect]'s loop can decide
  /// whether to surface it or fall through to the next candidate.
  Future<void> _attemptConnect(LocationItem target,
      {required int generation}) async {
    if (target.isCustom) {
      final profile = ConnectionProfile(target.rawLink ?? '');
      await SecureStore.write(SecureStore.connectionProfile, profile.rawJson);
      if (generation != _connectGeneration) return;
      state = state.copyWith(status: ConnectionStatus.connecting);
      unawaited(VpnNotificationMeta.update(target, ref.read(stringsProvider)));
      await ref.read(vpnAdapterProvider).connect(profile);
      if (generation != _connectGeneration) return;
      state = state.copyWith(
        status: ConnectionStatus.connected,
        connectedAt: DateTime.now(),
        clearError: true,
      );
      // Repeated, not just the one before connect(): that first call
      // races the native service actually starting (WaveEngineVpnService.
      // instance is still null until MainActivity's "connect" case
      // launches it), so on the very first connect since install it can
      // land as a no-op and leave the notification on its English
      // fallback strings. This one is guaranteed to land on a live
      // instance, so the notification that actually persists while
      // connected is always right even if the fleeting "connecting"
      // frame briefly wasn't.
      unawaited(VpnNotificationMeta.update(target, ref.read(stringsProvider)));
      unawaited(HapticFeedback.mediumImpact());
      _analytics.event('connection_success');
      return;
    }

    final gateway = ref.read(coreGatewayProvider);
    final deviceId = await DeviceService(gateway).deviceId();
    if (generation != _connectGeneration) return;

    final grant = await gateway.createAccessGrant(
      nodeId: target.id,
      deviceId: deviceId,
      protocol: AppEnv.accessProtocol,
    );
    if (generation != _connectGeneration) return;
    state = state.copyWith(grantId: grant.id);

    // The pilot's node-agent can take anywhere from a couple seconds to
    // (occasionally) closer to a minute to ack a fresh grant
    // (`config_status: "pending_node_ack"`) — docs say to show a brief
    // preparing state and just retry, not treat it as stuck the way the
    // older `pending_runtime_config` (no backend pass yet at all) is. A
    // short bounded poll covers the common fast case inline; anything
    // slower hands off to a background poll below instead of just
    // giving up with no way out.
    var config = await gateway.grantConfig(grant.id);
    var attempts = 0;
    while (!config.isReady && attempts < 5) {
      if (generation != _connectGeneration) return;
      state = state.copyWith(status: ConnectionStatus.configPending);
      await Future<void>.delayed(const Duration(seconds: 2));
      if (generation != _connectGeneration) return;
      config = await gateway.grantConfig(grant.id);
      attempts++;
    }
    if (generation != _connectGeneration) return;
    if (!config.isReady) {
      state = state.copyWith(status: ConnectionStatus.configPending);
      _analytics.event('connection_config_pending');
      _schedulePendingPoll(grant.id);
      return;
    }

    await _finishConnecting(grant.id, config,
        generation: generation, rethrowOnError: true);
  }

  /// Builds the native profile from a ready config and hands it to the
  /// adapter — the shared tail end of both the inline-ready path in
  /// [connect] and the background poll in [_schedulePendingPoll], so
  /// there's exactly one place that decides how a [VpnConfigResponse]
  /// becomes a [ConnectionProfile].
  ///
  /// [rethrowOnError]: the background poll path (no caller left to react
  /// to a throw) wants the old behavior — land straight on `error` state.
  /// [connect]'s own Auto-candidate loop wants the opposite: it needs the
  /// failure as a real exception so it can try the next-best candidate
  /// instead of the first one's failure becoming the user-visible result.
  Future<void> _finishConnecting(String grantId, VpnConfigResponse config,
      {int? generation, bool rethrowOnError = false}) async {
    final wireguard = config.wireguard;
    final Map<String, dynamic> payload;
    if (wireguard != null && wireguard.hasUsablePeer) {
      payload = {
        'grant_id': grantId,
        'wireguard': {
          'interface': {
            'private_key': wireguard.interface.privateKey,
            'address': wireguard.interface.address,
            'dns': wireguard.interface.dns,
            'mtu': wireguard.interface.mtu,
          },
          'peer': {
            'public_key': wireguard.peer.publicKey,
            'preshared_key': wireguard.peer.presharedKey,
            'endpoint': wireguard.peer.endpoint,
            'allowed_ips': wireguard.peer.allowedIps,
            'persistent_keepalive': wireguard.peer.persistentKeepalive,
          },
        },
      };
    } else {
      // VLESS REALITY (the pilot's actual protocol), consumed by
      // V2RayVpnAdapter / WindowsVpnAdapter — see connection_profile
      // shape there. Core's top-level connectionUrl now defaults to the
      // CDN-fronted WebSocket+TLS fallback (see docs/vpn-config-
      // contract.md's `vless_cdn`) — the direct link (plain TCP +
      // REALITY, no WebSocket framing) is preferred here whenever it's
      // present: fewer moving parts, no dependency on the CDN hostname
      // staying up, and it's the shape actually confirmed end-to-end
      // (real proxied HTTP traffic) during testing — the WS variant is
      // suspected of tripping up UDP/DNS relaying through some native
      // VPN clients even though the tunnel itself connects.
      payload = {
        'grant_id': grantId,
        'vless': {
          'connection_url': config.vless?.uri ?? config.connectionUrl,
          'client_id': config.vless?.clientId,
          'server': config.vless?.server,
          'port': config.vless?.port,
          'security': config.vless?.security,
          'network': config.vless?.network,
          'flow': config.vless?.flow,
        },
        if (config.routingPolicy != null)
          'routing_policy': config.routingPolicy,
      };
    }
    final profile = ConnectionProfile(jsonEncode(payload));
    await SecureStore.write(SecureStore.connectionProfile, profile.rawJson);
    if (generation != null && generation != _connectGeneration) return;

    state = state.copyWith(status: ConnectionStatus.connecting);
    unawaited(
        VpnNotificationMeta.update(state.location, ref.read(stringsProvider)));
    try {
      await ref.read(vpnAdapterProvider).connect(profile);
      if (generation != null && generation != _connectGeneration) return;
      state = state.copyWith(
        status: ConnectionStatus.connected,
        connectedAt: DateTime.now(),
        clearError: true,
      );
      // See the identical call/comment in connect()'s isCustom branch.
      unawaited(VpnNotificationMeta.update(
          state.location, ref.read(stringsProvider)));
      unawaited(HapticFeedback.mediumImpact());
      _analytics.event('connection_success');
    } catch (error) {
      if (generation != null && generation != _connectGeneration) return;
      AppLogger.warn('Connection failed');
      _analytics.event('connection_error');
      final mapped = error is AppException
          ? error
          : AppException(AppErrorKind.connectionFailed);
      if (rethrowOnError) throw mapped;
      state = state.copyWith(
        status: ConnectionStatus.error,
        error: mapped,
        clearConnectedAt: true,
      );
    }
  }

  /// Keeps checking `grantConfig` every few seconds well past the quick
  /// inline retry window in [connect] — the pilot's node-agent ack can
  /// occasionally take closer to a minute. Gives up with a real `error`
  /// state (so the user gets a Retry button) instead of leaving
  /// `configPending` showing forever with no way out.
  void _schedulePendingPoll(String grantId) {
    _cancelPendingPoll();
    _pendingGrantId = grantId;
    final deadline = DateTime.now().add(const Duration(seconds: 40));
    _pendingConfigPoll =
        Timer.periodic(const Duration(seconds: 3), (timer) async {
      // The user disconnected, switched servers, or retried manually
      // since this timer was scheduled — this attempt is stale, stop.
      if (_pendingGrantId != grantId || state.grantId != grantId) {
        timer.cancel();
        return;
      }
      if (DateTime.now().isAfter(deadline)) {
        timer.cancel();
        _pendingConfigPoll = null;
        _pendingGrantId = null;
        state = state.copyWith(
          status: ConnectionStatus.error,
          error: AppException(AppErrorKind.connectionFailed),
        );
        return;
      }
      try {
        final config = await ref.read(coreGatewayProvider).grantConfig(grantId);
        if (_pendingGrantId != grantId || state.grantId != grantId) {
          timer.cancel();
          return;
        }
        if (config.isReady) {
          timer.cancel();
          _pendingConfigPoll = null;
          _pendingGrantId = null;
          await _finishConnecting(grantId, config);
        }
      } catch (_) {
        // Transient — keep trying until the deadline above.
      }
    });
  }

  void _cancelPendingPoll() {
    _pendingConfigPoll?.cancel();
    _pendingConfigPoll = null;
    _pendingGrantId = null;
  }

  /// Bounds how many of Auto's ranked candidates [connect] will actually
  /// try a real handshake against before giving up — each attempt beyond
  /// the first is a real grant creation (for a Core-managed candidate)
  /// plus a real tunnel handshake, not a cheap probe, so this stays small.
  static const _maxAutoCandidates = 3;

  /// A quick-probed candidate at or above this throughput is treated as
  /// "fast enough" and Auto stops right there instead of burning through
  /// the rest of [_maxAutoCandidates] — the point is picking a candidate
  /// that's genuinely usable, not chasing the single fastest one available
  /// at the cost of a slower connect flow every time. 8 Mbps comfortably
  /// covers video calls and standard-definition streaming, the kind of
  /// use this pilot is actually validating; a candidate below it is
  /// probably fine for basic browsing too, which is why a below-threshold
  /// result still keeps the best of what was actually measured (see the
  /// loop in [connect]) rather than treating it as a failure.
  static const _goodEnoughAutoMbps = 8.0;

  /// Auto has no server-side meaning in Core's API — it's a client
  /// convenience over whatever `/v1/locations` last returned. Ranks every
  /// online candidate by a real TCP-connect timing (same as the location
  /// picker's own ping test) and returns them fastest-first — a static
  /// [LocationItem.pingMs] sort used to sit here instead, but Core never
  /// populates that field for a real location (see
  /// connection_test_service.dart's own comment on this), so every
  /// candidate compared equal and "Auto" just connected to whatever
  /// happened to be first in the list, never actually the fastest one.
  ///
  /// A fast TCP connect is necessary but not sufficient for "this location
  /// actually works" — a REALITY/DPI-adjacent server can accept the TCP
  /// SYN and then go nowhere on the real TLS handshake, and Direct-TLS's
  /// own WebSocket upgrade can fail for reasons a bare TCP connect never
  /// sees. [connect] is what does the real verification (a genuine
  /// handshake through [NativeVpnAdapter.connect]) and falls through this
  /// list on failure — ranking by latency here just decides the order to
  /// try them in, not whether any one of them is treated as "confirmed
  /// working" before that real attempt happens.
  ///
  /// Tested one at a time, not all in parallel — these probes run through
  /// the same native protect() path every real Xray-core/Hysteria dial
  /// does, and firing a whole batch of them at once turned out to be
  /// exactly the kind of burst that pushed the protect socket server
  /// toward running out of file descriptors on-device (see
  /// connection_test_service.dart's timeout comment for the full story).
  /// Sequential keeps at most one of these test sockets open at a time.
  Future<List<LocationItem>> _rankCandidates(LocationItem location) async {
    if (!location.isAuto) return [location];
    final all =
        ref.read(locationsProvider).asData?.value ?? const <LocationItem>[];
    final online = all.where((l) => l.available).toList();
    if (online.isEmpty) {
      throw AppException(AppErrorKind.locationUnavailable);
    }
    const test = ConnectionTestService();
    final pings = <LocationItem, int>{};
    for (final candidate in online) {
      pings[candidate] = await test.testLocation(candidate) ?? (1 << 30);
    }
    online.sort((a, b) => pings[a]!.compareTo(pings[b]!));
    return online.take(_maxAutoCandidates).toList();
  }

  Future<void> disconnect() async {
    unawaited(HapticFeedback.lightImpact());
    state = state.copyWith(status: ConnectionStatus.disconnecting);
    final grantId = state.grantId;
    if (grantId != null && !state.location.isCustom) {
      try {
        await ref.read(coreGatewayProvider).revokeAccessGrant(grantId);
      } catch (_) {
        // Best-effort — the local tunnel/state still tears down below
        // even if the revoke call itself failed (e.g. already revoked).
      }
    }
    await _teardownTunnel();
    state = state.copyWith(
      status: ConnectionStatus.idle,
      clearConnectedAt: true,
      clearError: true,
      clearGrantId: true,
    );
  }

  /// Stops the native tunnel and clears the stored profile without
  /// touching [state] — the two callers (a user-initiated [disconnect], a
  /// silent teardown mid-[selectLocation]) each decide what status that
  /// should show as, if anything.
  Future<void> _teardownTunnel() async {
    _cancelPendingPoll();
    try {
      await ref.read(vpnAdapterProvider).disconnect();
    } catch (_) {}
    await SecureStore.delete(SecureStore.connectionProfile);
  }

  /// Disconnects and reconnects to the same location. Only meaningful once
  /// a connection has been attempted at least once.
  Future<void> restart({required bool subscriptionActive}) async {
    if (state.status == ConnectionStatus.connected ||
        state.status == ConnectionStatus.configPending) {
      await disconnect();
    }
    await connect(subscriptionActive: subscriptionActive);
  }

  static const _systemVpnChannel = MethodChannel('app.wavebreak/vpn_state');

  /// Android's real VpnService tunnel runs in its own process and survives
  /// the Flutter/UI process being killed — so a cold relaunch after the
  /// user swiped the app away with a connection still up used to always
  /// show `idle` (build() has no way to know better), reading as
  /// disconnected — guests even saw "add your own link" — while the
  /// system tunnel was genuinely still running underneath. Call once,
  /// after locations/custom servers are available to resolve the saved
  /// location's real details (see home_screen.dart's initState).
  Future<void> reconcileWithSystem() async {
    if (!Platform.isAndroid || AppEnv.useSimulatedVpn) return;
    if (state.status != ConnectionStatus.idle) return;
    if (state.location.isAuto) return;
    try {
      final active =
          await _systemVpnChannel.invokeMethod<bool>('isSystemVpnActive') ??
              false;
      if (!active) return;
    } catch (_) {
      return;
    }
    if (state.status != ConnectionStatus.idle) return;
    state = state.copyWith(
        status: ConnectionStatus.connected, connectedAt: DateTime.now());
  }

  void _onNative(VpnNativeState native) {
    // VpnNativeState.reconnecting (WaveEngineVpnService.kt's engine-only,
    // TUN-preserving reconnect — see its own class doc) is deliberately
    // NOT handled here: falling through with no status change is exactly
    // the point. The whole fix it belongs to exists so the native tunnel
    // recovers from a network flap/health-check failure without the TUN
    // interface, foreground notification, OR this app's own `connected`
    // status ever flickering — reacting to it here (even just logging a
    // visible transition) would reintroduce that flicker one layer up.
    if (native == VpnNativeState.failed &&
        state.status != ConnectionStatus.error) {
      state = state.copyWith(
        status: ConnectionStatus.error,
        error: AppException(AppErrorKind.connectionFailed),
      );
      return;
    }
    // The native tunnel dropped on its own without us calling disconnect()
    // — most commonly Android revoking the VpnService because the user
    // switched to a different VPN app (VpnService.onRevoke() on the
    // V2Ray/Xray side), but any native-side crash/kill lands here too.
    // Previously only `failed` was handled, so this case fell through
    // silently: the UI kept showing "Connected" forever with no real
    // tunnel underneath it, since nothing ever moved `state.status` back
    // off `connected`.
    if (native == VpnNativeState.idle &&
        (state.status == ConnectionStatus.connected ||
            state.status == ConnectionStatus.configPending)) {
      state = state.copyWith(
        status: ConnectionStatus.idle,
        clearConnectedAt: true,
        clearGrantId: true,
      );
    }
  }
}
