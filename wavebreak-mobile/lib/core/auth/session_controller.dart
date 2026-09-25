import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../features/shared/data_providers.dart';
import '../../services/core_api/models.dart';
import '../../services/device/device_service.dart';
import '../../services/providers.dart';
import '../errors/app_exception.dart';
import '../logging/app_logger.dart';
import '../storage/prefs_store.dart';
import '../storage/secure_store.dart';

enum SessionPhase {
  booting,
  unauthenticated,
  authenticated,
  // No WAVEBREAK account at all, by choice — someone who only ever
  // pastes their own subscription link. Never touches Core: this exists
  // specifically so that if our backend is unreachable, a person using
  // their own server isn't blocked from opening the app at all.
  guest,
  updateRequired,
  maintenance,
}

/// Set right before an *involuntary* logout (session expired, device
/// revoked) so the Login screen can explain why the user landed there —
/// a manual logout leaves this null.
final forcedLogoutReasonProvider = StateProvider<AppErrorKind?>((ref) => null);

class SessionState {
  const SessionState({
    required this.phase,
    this.user,
    this.config = ClientConfig.fallback,
  });

  final SessionPhase phase;
  final UserProfile? user;
  final ClientConfig config;

  SessionState copyWith({
    SessionPhase? phase,
    UserProfile? user,
    ClientConfig? config,
    bool clearUser = false,
  }) {
    return SessionState(
      phase: phase ?? this.phase,
      user: clearUser ? null : (user ?? this.user),
      config: config ?? this.config,
    );
  }
}

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

class SessionController extends Notifier<SessionState> {
  bool _refreshing = false;
  bool _loggingOut = false;

  @override
  SessionState build() {
    final bindings = ref.read(apiAuthBindingsProvider);
    bindings.refreshSession = refreshTokens;
    bindings.onAuthLost = () {
      ref.read(forcedLogoutReasonProvider.notifier).state =
          AppErrorKind.sessionExpired;
      return forceLogout();
    };
    Future<void>.microtask(_bootstrapSessionGuarded);
    return const SessionState(phase: SessionPhase.booting);
  }

  // The splash screen (see router.dart's redirect) shows for exactly as
  // long as `state.phase` stays `booting` — there is no other way off it.
  // bootstrapSession() below now flips out of `booting` as soon as it has
  // read the stored tokens (going straight to `authenticated` on cached
  // data for a returning user — see its own doc comment); the Core calls
  // that used to sit in between run afterward, in the background, via
  // _validateSessionInBackground, and are no longer on the path this
  // timeout needs to bound. What's left in bootstrapSession() before it
  // returns is just the SecureStore reads, but nothing bounded even THAT
  // much before this existed. Confirmed as a real trap, not just a
  // theoretical one: a device migration/APK-sharing report described the
  // exact symptom — permanently stuck on "Preparing your connection…" on
  // one specific phone while working fine on another with the identical
  // build. flutter_secure_storage's Android backend generates/uses an
  // Android Keystore-backed key that is hardware-tied to the device it was
  // created on; anything that hands this app a data directory whose
  // encrypted values were written under a DIFFERENT device's key (a full
  // app-data clone/"phone clone" tool, not just the bare .apk) leaves
  // SecureStore.read() reading real ciphertext it can't decrypt — and
  // depending on the platform channel plugin's own behavior, that can
  // throw or hang rather than cleanly returning null. Whatever the exact
  // cause on a given device, this method must never be able to leave
  // `state` stuck at its initial `booting` value forever — an outer
  // timeout plus a safe fallback phase guarantees the splash screen always
  // resolves to something the user can actually act on.
  Future<void> _bootstrapSessionGuarded() async {
    try {
      await bootstrapSession().timeout(const Duration(seconds: 20));
    } catch (e) {
      AppLogger.warn(
          'bootstrapSession did not complete in time, falling back: $e');
      if (state.phase == SessionPhase.booting) {
        // A corrupt/undecryptable secure-storage entry is exactly the kind
        // of thing that would keep failing the same way on every future
        // launch too — clearing it here is what actually lets a retry (or
        // just relaunching the app) succeed instead of hitting this same
        // timeout forever.
        try {
          await SecureStore.clearSession();
        } catch (_) {}
        state = state.copyWith(
            phase: SessionPhase.unauthenticated, clearUser: true);
      }
    }
  }

  Future<void> bootstrapSession() async {
    // A returning guest never touches Core at all — not even the startup
    // config/version check. That's the whole point: someone using their
    // own server must never be blocked behind our backend being
    // reachable.
    if (PrefsStore.getBool(PrefsStore.guestMode)) {
      state = state.copyWith(phase: SessionPhase.guest, clearUser: true);
      return;
    }

    // Nothing to restore, so nothing to check with Core either — a fresh
    // install (or someone who signed out) must reach the "sign in / use
    // my own link" decision instantly, not sit on a splash screen waiting
    // on a network call it doesn't even need yet. clientConfig() only
    // matters once there's an actual session to validate below.
    String? access;
    String? refresh;
    try {
      access = await SecureStore.read(SecureStore.accessToken);
      refresh = await SecureStore.read(SecureStore.refreshToken);
    } catch (e) {
      // See _bootstrapSessionGuarded's doc comment — an undecryptable
      // entry (or any other secure-storage failure) reads as "no session"
      // rather than propagating and leaving the caller to rely solely on
      // the outer timeout for what a fast, clean path should handle
      // directly.
      AppLogger.warn('SecureStore read failed during bootstrap: $e');
      state =
          state.copyWith(phase: SessionPhase.unauthenticated, clearUser: true);
      return;
    }
    if (access == null || refresh == null) {
      state =
          state.copyWith(phase: SessionPhase.unauthenticated, clearUser: true);
      return;
    }

    // A returning user with tokens that at least look valid gets in
    // immediately on whatever we last knew about their account — no
    // waiting on Core. clientConfig()/me()/ensureRegistered() (maintenance,
    // force-update, session-revoked, and the fresh profile/prefetch) all
    // still run, just as a background reconciliation after the fact
    // (_validateSessionInBackground) instead of gating entry — the same
    // "trust first, reconcile after" shape _completePostAuth already uses
    // for a just-completed login. If there's no cached profile yet (e.g.
    // this is the very first cold start after that login, before a cache
    // write ever landed), `user` is simply null until the background pass
    // fills it in — screens that read it already null-check (see
    // AccountScreen).
    state = state.copyWith(
      phase: SessionPhase.authenticated,
      user: _readCachedUser(),
    );
    unawaited(_validateSessionInBackground());
  }

  /// Reconciles a cold-start entry that was granted on cached data (see
  /// bootstrapSession) against what Core actually says right now. Runs
  /// after the user is already in the app — never blocks entry. A genuine
  /// maintenance window, force-update gate, or session revocation still
  /// takes effect, just a moment later: the router (app/router.dart)
  /// redirects off whatever's currently showing the instant `state.phase`
  /// changes, same as it always has. A transient failure (offline, Core
  /// unreachable, timeout) leaves the cached snapshot in place untouched —
  /// individual screens already retry via data_providers.dart's own
  /// cached-fallback providers once connectivity returns.
  Future<void> _validateSessionInBackground() async {
    try {
      // 8s used to cut every one of these off well before ApiClient's own
      // GET-request retry (api_client.dart's `get()` always retries a
      // connection-level failure now — up to ~23s worst case across 3
      // attempts) ever got a chance to land a second try — real-device
      // logcat showed exactly this: "Background session validation
      // failed: TimeoutException after 0:00:08.000000" firing before a
      // retry could even complete its first attempt. These all run in
      // the background, after the user is already past the splash
      // screen/already signed in (see this method's own class doc and
      // _completePostAuth's) — nothing here blocks a spinner the user is
      // staring at, so there's no UX cost to matching
      // data_providers.dart's own 26s ceiling instead of racing under it.
      final config = await ref
          .read(coreGatewayProvider)
          .clientConfig()
          .timeout(const Duration(seconds: 26));
      if (config.maintenance) {
        state = state.copyWith(phase: SessionPhase.maintenance, config: config);
        return;
      }
      if (await _isBelowMinimum(config.minimumSupportedVersion)) {
        state = state.copyWith(
          phase: SessionPhase.updateRequired,
          config: config,
        );
        return;
      }

      try {
        final user = await ref
            .read(coreGatewayProvider)
            .me()
            .timeout(const Duration(seconds: 26));
        await DeviceService(ref.read(coreGatewayProvider))
            .ensureRegistered()
            .timeout(const Duration(seconds: 26));
        state = state.copyWith(
          phase: SessionPhase.authenticated,
          user: user,
          config: config,
        );
        await _cacheUser(user);
        await _prefetchEssentials();
      } on AppException catch (error) {
        if (error.kind == AppErrorKind.sessionExpired) {
          // refreshTokens() already ends the session itself (see its own
          // doc comment) if Core genuinely rejected the refresh token —
          // `false` here can also just mean the refresh attempt itself
          // hit a transient network failure, which must NOT also force a
          // logout on top of whatever refreshTokens() already decided.
          // Falling through to `authenticated` with the existing
          // (possibly still momentarily invalid) token lets the very
          // next real request retry refreshing once the network is
          // actually back, instead of ending a perfectly good session
          // over one bad moment.
          final ok = await refreshTokens();
          if (!ok) {
            // refreshTokens() already awaited its own forceLogout() above
            // if this was a genuine rejection — only fall back to
            // `authenticated` here for the OTHER case (a transient
            // failure that left the session alone), never clobber a
            // logout that already happened a moment ago.
            if (state.phase != SessionPhase.unauthenticated) {
              state = state.copyWith(
                  phase: SessionPhase.authenticated, config: config);
            }
            return;
          }
          final user = await ref
              .read(coreGatewayProvider)
              .me()
              .timeout(const Duration(seconds: 26));
          state = state.copyWith(
            phase: SessionPhase.authenticated,
            user: user,
            config: config,
          );
          await _cacheUser(user);
          await _prefetchEssentials();
          return;
        }
        if (error.kind == AppErrorKind.accessDenied) {
          ref.read(forcedLogoutReasonProvider.notifier).state =
              AppErrorKind.accessDenied;
          await forceLogout();
          return;
        }
        // Some other, non-definitive AppException from `me()` — leave the
        // cached snapshot the user is already looking at alone.
        state = state.copyWith(
          phase: SessionPhase.authenticated,
          config: config,
        );
      }
    } catch (e) {
      // clientConfig()/me()/ensureRegistered() unreachable, timed out, or
      // failed some other way — the user is already in on cached data, so
      // there's nothing to correct. Logged for visibility only.
      AppLogger.warn('Background session validation failed: $e');
    }
  }

  UserProfile? _readCachedUser() {
    final raw = PrefsStore.getString(PrefsStore.cachedUser);
    if (raw == null || raw.isEmpty) return null;
    try {
      return UserProfile.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<void> _cacheUser(UserProfile user) =>
      PrefsStore.setString(PrefsStore.cachedUser, jsonEncode(user.toJson()));

  Future<void> onAuthenticated(TokenPair tokens) async {
    try {
      await (() async {
        await SecureStore.write(SecureStore.accessToken, tokens.accessToken);
        await SecureStore.write(SecureStore.refreshToken, tokens.refreshToken);
      })()
          .timeout(const Duration(seconds: 6));
    } catch (e) {
      AppLogger.warn('Token persistence was slow after login: $e');
    }
    state = state.copyWith(phase: SessionPhase.authenticated);
    unawaited(_completePostAuth());
  }

  Future<void> _completePostAuth() async {
    // The tokens are already valid and stored at this point — login or
    // register itself succeeded. A hiccup in any of the *follow-up* calls
    // below must never surface as if signing in had failed (it would
    // show as a confusing "invalid credentials"/"session expired" right
    // after a correct password, since the login screen has no way to
    // tell "auth failed" apart from "something after auth failed").
    // Same best-effort spirit as bootstrapSession's catch-all.
    try {
      final user = await ref
          .read(coreGatewayProvider)
          .me()
          .timeout(const Duration(seconds: 26));
      state = state.copyWith(user: user);
      await _cacheUser(user);
      await DeviceService(ref.read(coreGatewayProvider))
          .ensureRegistered()
          .timeout(const Duration(seconds: 26));
      await _prefetchEssentials();
    } catch (e) {
      AppLogger.warn(
          'Post-auth bootstrap failed, continuing signed in anyway: $e');
      // Authentication is already complete. Optional profile/bootstrap
      // failures are logged and retried by their destination screens.
    }
  }

  /// Warms the subscription + locations caches before Home ever renders, so
  /// the app only leaves the splash screen once it can show real data
  /// immediately — never a loading spinner on the very first frame. Best
  /// effort: a slow or failing prefetch never blocks sign-in.
  Future<void> _prefetchEssentials() async {
    try {
      await Future.wait([
        ref.read(subscriptionProvider.future),
        ref.read(locationsProvider.future),
      ]).timeout(const Duration(seconds: 6));
    } catch (_) {
      // Ignored — Home's own providers will retry and show their own
      // error/loading state if this didn't warm the cache in time.
    }
  }

  /// Real-device bug this exists to fix: "occasionally logs the user out
  /// unexpectedly" / "heavily dependent on WiFi." Root cause traced to
  /// AuthInterceptor.onError: any 401 (including an access token simply
  /// expiring naturally after its normal ~15-minute lifetime — nothing
  /// wrong, just routine) calls this to get a fresh one, and on `false`
  /// force-logs-out the whole session. This used to return `false` for
  /// EVERY failure alike — a refresh token Core genuinely rejected
  /// (revoked, actually expired) and a refresh call that simply couldn't
  /// complete because the WiFi hiccuped for a second, indistinguishable.
  /// The underlying `coreGatewayProvider.refresh()` call already throws a
  /// properly classified [AppException] (see error_mapper.dart) — this
  /// was just discarding that classification. Now: a genuine auth
  /// rejection still ends the session (and does so directly, rather than
  /// leaving that decision to a caller that has no way to tell the two
  /// cases apart); a network/transient failure just fails this one
  /// refresh attempt and leaves the existing session alone to retry
  /// later, the same way a single dropped request anywhere else in the
  /// app doesn't end the session.
  Future<bool> refreshTokens() async {
    if (_refreshing) return false;
    _refreshing = true;
    try {
      final refresh = await SecureStore.read(SecureStore.refreshToken);
      if (refresh == null) return false;
      final pair = await ref.read(coreGatewayProvider).refresh(refresh);
      await SecureStore.write(SecureStore.accessToken, pair.accessToken);
      await SecureStore.write(SecureStore.refreshToken, pair.refreshToken);
      AppLogger.debug('Session refreshed');
      return true;
    } catch (e) {
      final kind = e is AppException ? e.kind : AppErrorKind.unknown;
      final isDefinitiveRejection = kind == AppErrorKind.invalidCredentials ||
          kind == AppErrorKind.sessionExpired ||
          kind == AppErrorKind.accessDenied;
      if (isDefinitiveRejection) {
        AppLogger.warn(
            'Refresh token rejected by Core ($kind) — ending session');
        ref.read(forcedLogoutReasonProvider.notifier).state =
            AppErrorKind.sessionExpired;
        // Awaited, not fire-and-forget: a caller checking `state.phase`
        // right after this returns (see bootstrapSession's own fallback)
        // must see the logout that already happened, not race it.
        await forceLogout();
      } else {
        AppLogger.warn(
            'Token refresh failed transiently ($kind), leaving session intact');
      }
      return false;
    } finally {
      _refreshing = false;
    }
  }

  /// Skips WAVEBREAK entirely — no registration, no login, no Core calls
  /// ever. For someone who only wants to paste their own subscription
  /// link and connect through it.
  Future<void> continueAsGuest() async {
    await PrefsStore.setBool(PrefsStore.guestMode, true);
    state = state.copyWith(phase: SessionPhase.guest, clearUser: true);
  }

  /// Leaves guest mode to sign in or create a real WAVEBREAK account.
  Future<void> exitGuestMode() async {
    await PrefsStore.setBool(PrefsStore.guestMode, false);
    state =
        state.copyWith(phase: SessionPhase.unauthenticated, clearUser: true);
  }

  Future<void> logout() async {
    // The button that calls this has no tap-debounce of its own (it's a
    // plain ConsumerWidget, not stateful) — confirmed on-device that a few
    // quick taps sent four concurrent `/auth/logout` requests. Harmless to
    // Core itself, but this was firing alongside other overlapping native
    // VPN calls during the same burst of taps and just added to the
    // pile-up, so it's guarded at the source rather than only where it
    // happened to be noticed.
    if (_loggingOut) return;
    _loggingOut = true;
    try {
      final refresh = await SecureStore.read(SecureStore.refreshToken);
      if (refresh != null) {
        await ref.read(coreGatewayProvider).logout(refresh);
      }
    } catch (_) {}
    await forceLogout();
    _loggingOut = false;
  }

  Future<void> forceLogout() async {
    await SecureStore.clearSession();
    await PrefsStore.setBool(PrefsStore.biometricEnabled, false);
    await PrefsStore.setBool(PrefsStore.guestMode, false);
    // Otherwise a different account signing in on the same device would
    // flash the previous account's cached name/email for a moment on its
    // very next cold start, before _validateSessionInBackground replaces
    // it — see bootstrapSession's fast path.
    await PrefsStore.setString(PrefsStore.cachedUser, null);
    state = state.copyWith(
      phase: SessionPhase.unauthenticated,
      clearUser: true,
    );
  }

  Future<bool> _isBelowMinimum(String? minimum) async {
    if (minimum == null || minimum.isEmpty) return false;
    try {
      final info = await PackageInfo.fromPlatform();
      return _compareVersions(info.version, minimum) < 0;
    } catch (_) {
      return false;
    }
  }

  int _compareVersions(String a, String b) {
    List<int> parts(String v) =>
        v.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pa = parts(a);
    final pb = parts(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }
}
