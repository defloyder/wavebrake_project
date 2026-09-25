import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/session_controller.dart';
import '../../core/network/connectivity_provider.dart';
import '../../core/storage/prefs_store.dart';
import '../../services/core_api/models.dart';
import '../../services/providers.dart';
import '../../services/vpn/bundled_locations.dart';

/// None of these providers have anything to fetch outside of
/// [SessionPhase.authenticated] — a guest (see that enum) never touches
/// Core at all by design, and every OTHER phase (`booting`,
/// `unauthenticated`, `maintenance`, `updateRequired`) means there either
/// isn't a session yet or isn't a valid one. Gating on "not guest" instead
/// of "is authenticated" used to let these fire during `booting` — e.g. on
/// a cold start with a stale/expired token still in SecureStore, before
/// bootstrapSession had even decided whether that token is still good.
/// That request would 401, and since these are plain (non-autoDispose)
/// FutureProviders, the failure got cached — permanently, since nothing
/// re-triggers them later. A subsequent successful login left the *new*
/// session staring at that same stale "invalid email or password" error
/// instead of a fresh fetch (confirmed on-device: login succeeded, Core's
/// own token worked fine via a direct API call, yet Home kept showing the
/// old cached error). Because this check uses `ref.watch`, every provider
/// below automatically re-runs from scratch whenever the phase actually
/// flips (booting/unauthenticated → authenticated, or a forced logout and
/// back) — no manual invalidation needed, just the gate actually matching
/// reality. [SessionController.onAuthenticated] and
/// `.bootstrapSession`'s success paths flip phase to `authenticated`
/// *before* warming these caches, for the same reason: their own prefetch
/// reads would otherwise be gated out by the state change they're waiting
/// on.
// `.select` on purpose — watching the whole SessionState would re-run
// every provider below on ANY session change (token refresh, user profile
// update, etc.), not just an actual phase transition.
//
// Also watches [isOfflineProvider] — without this, none of the providers
// below ever re-run once they've failed once: a plain FutureProvider only
// re-executes when something it `ref.watch`es changes, and the session
// phase alone doesn't change just because the device's connection came
// back. Confirmed bug this fixes: [usingCachedDataProvider] flips true on
// the first failure and then never flips back, even long after
// connectivity is restored, because nothing ever gave these providers a
// reason to retry. Watching connectivity here means every transition
// (online<->offline) is exactly that reason, for every provider below
// with no extra wiring per call site.
bool _canQueryCore(Ref ref) {
  ref.watch(isOfflineProvider);
  return ref.watch(sessionControllerProvider
      .select((s) => s.phase == SessionPhase.authenticated));
}

const _noSubscription = SubscriptionInfo(status: 'none');

/// True when at least one of the providers below is currently serving a
/// cached (possibly stale) snapshot because its live refresh just failed —
/// not the same thing as [isOfflineProvider] (core/network/connectivity_provider.dart),
/// which only reports the device's own radio state. This also catches
/// "device has signal but Core itself is unreachable/erroring." Read by
/// the same offline pill in app/app.dart so a subscriber sees one
/// consistent "you're looking at saved data" signal regardless of which
/// of the two conditions actually caused it.
final usingCachedDataProvider = StateProvider<bool>((ref) => false);

void _markCacheState(Ref ref, {required bool stale}) {
  final notifier = ref.read(usingCachedDataProvider.notifier);
  // Only ever loosen (false) if nothing else currently needs `true` — a
  // simple last-write-wins would let a later-resolving fresh fetch for
  // one provider mask another provider's genuine cache fallback.
  if (stale) {
    notifier.state = true;
  } else if (notifier.state) {
    notifier.state = false;
  }
}

T? _readCachedOne<T>(String key, T Function(Map<String, dynamic>) fromJson) {
  final raw = PrefsStore.getString(key);
  if (raw == null || raw.isEmpty) return null;
  try {
    return fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
  } catch (_) {
    return null;
  }
}

List<T> _readCachedList<T>(
    String key, T Function(Map<String, dynamic>) fromJson) {
  final raw = PrefsStore.getString(key);
  if (raw == null || raw.isEmpty) return const [];
  try {
    final list = jsonDecode(raw) as List;
    return list
        .whereType<Map>()
        .map((e) => fromJson(e.cast<String, dynamic>()))
        .toList();
  } catch (_) {
    return const [];
  }
}

Future<void> _writeCache(String key, Object? jsonValue) =>
    PrefsStore.setString(key, jsonEncode(jsonValue));

/// Real-device bug this fixes: the connect wall's skeleton (see
/// [subscriptionProvider]) stayed up for over 30 seconds straight with no
/// cache to fall back on — the live `subscription()` call was stuck
/// somewhere Dio's own connectTimeout/receiveTimeout never bounds, most
/// likely ApiClient's AuthInterceptor (a `QueuedInterceptor` — see its own
/// doc comment) waiting on a slow `readAccessToken()` SecureStore read, or
/// simply queued behind another still-in-flight request. Dio's per-call
/// timeouts only cover the HTTP transfer itself, not time spent earlier in
/// the interceptor pipeline. Wrapping the WHOLE call in a plain
/// [Future.timeout] bounds it regardless of where it's actually stuck,
/// same fix as login_screen.dart's own CancelToken treatment but for
/// providers that can't cancel a shared Dio client's queue mid-flight —
/// this just guarantees the wait is finite so a real error (or the cache
/// fallback) is reached instead of an indefinite spinner/skeleton.
// 26s, not 20s: ApiClient's own GET retry logic (api_client.dart) can now
// take up to ~23s worst case on its own (3 attempts × its 7s per-attempt
// budget + backoff) before this wrapper would even see a result — this
// just needs to sit comfortably above that so it isn't the thing that
// cuts a legitimately-still-retrying request off early.
Future<T> _withTimeout<T>(Future<T> future) =>
    future.timeout(const Duration(seconds: 26));

/// The account profile (email, id, ...) as its own reactively-retried
/// provider — NOT the one-shot `me()` call SessionController makes during
/// login/bootstrap (SessionState.user), which has no retry if that single
/// attempt times out or fails. Real-device bug this fixes: turning on a
/// third-party VPN made login/subscription/locations all succeed (Core's
/// other endpoints came back fine) but the email row kept showing "—"
/// forever — `me()` specifically had timed out during that one login
/// attempt, and nothing ever asked again. Same shape as every other
/// provider in this file: cached fallback, and `_canQueryCore`'s
/// [isOfflineProvider] watch means it automatically retries the moment
/// connectivity changes, instead of being stuck with whatever the one
/// login-time attempt happened to get. Shares SessionController's own
/// [PrefsStore.cachedUser] key deliberately — same snapshot, one source of
/// truth for "the last profile we actually saw."
final userProfileProvider = FutureProvider<UserProfile?>((ref) async {
  if (!_canQueryCore(ref)) return null;
  try {
    final result = await _withTimeout(ref.watch(coreGatewayProvider).me());
    await _writeCache(PrefsStore.cachedUser, result.toJson());
    _markCacheState(ref, stale: false);
    return result;
  } catch (_) {
    final cached = _readCachedOne(PrefsStore.cachedUser, UserProfile.fromJson);
    if (cached != null) {
      _markCacheState(ref, stale: true);
      return cached;
    }
    rethrow;
  }
});

/// StreamProvider, not FutureProvider — deliberately, so a returning
/// user with a cached subscription can be shown it on the very first
/// frame instead of an `AsyncLoading` with no data. Real-device bug this
/// fixes: every login/reopen briefly rendered the "Требуется подписка /
/// Выбрать тариф" wall (home_screen.dart's `_StatusCopy`, gated on
/// `canConnectProvider` reading `.asData?.value`, which is null while
/// AsyncLoading) even for an already-paying subscriber — not because
/// there was no cache (there was, see the old catch-block fallback
/// below), but because that cache was only ever consulted AFTER a live
/// call had already failed, never as an immediate starting value while
/// one was still in flight. Now: yield the cached snapshot first (if any)
/// so dependents see real data on frame one, then yield the live result
/// once it lands — `canConnectProvider`/`_StatusCopy` need no changes,
/// they just now observe real data sooner. A genuine first-ever login
/// (no cache yet) still has nothing to yield until the live call
/// resolves — that gap is what home_screen.dart's own skeleton state is
/// for, not this provider's job to paper over.
final subscriptionProvider = StreamProvider<SubscriptionInfo>((ref) async* {
  if (!_canQueryCore(ref)) {
    yield _noSubscription;
    return;
  }
  final cached =
      _readCachedOne(PrefsStore.cachedSubscription, SubscriptionInfo.fromJson);
  if (cached != null) yield cached;
  try {
    final result =
        await _withTimeout(ref.watch(coreGatewayProvider).subscription());
    await _writeCache(PrefsStore.cachedSubscription, result.toJson());
    _markCacheState(ref, stale: false);
    yield result;
  } catch (_) {
    if (cached == null) rethrow;
    _markCacheState(ref, stale: true);
  }
});

/// Whether the current subscription allows connecting to a WAVEBREAK
/// server right now. Shared so every call site that needs to know before
/// starting/switching a connection (the connect button, restart, picking a
/// new location while already connected) agrees on the same rule instead
/// of each re-deriving it slightly differently.
final canConnectProvider = Provider<bool>((ref) {
  final sub = ref.watch(subscriptionProvider).asData?.value;
  return sub != null && sub.isActive && !sub.isExpired;
});

final locationsProvider = FutureProvider<List<LocationItem>>((ref) async {
  if (!_canQueryCore(ref)) return const [];
  List<LocationItem> coreLocations;
  try {
    final rawCoreLocations =
        await _withTimeout(ref.watch(coreGatewayProvider).locations());
    // Core's pilot node currently only publishes a VLESS+REALITY transport,
    // which was never confirmed working end-to-end from the unified
    // Xray-core engine this session (unlike Direct-TLS/WS and Hysteria2,
    // both fully tested) — showing it as a normal-looking "WAVEBREAK Plus"
    // entry that just silently fails to connect is worse than not listing
    // it at all. Drop it until REALITY is verified; everything else Core
    // reports is unaffected.
    coreLocations = rawCoreLocations
        .where((l) => l.connectionTest?.security?.toLowerCase() != 'reality')
        .toList();
    await _writeCache(PrefsStore.cachedLocations,
        coreLocations.map((l) => l.toJson()).toList());
    _markCacheState(ref, stale: false);
  } catch (_) {
    coreLocations =
        _readCachedList(PrefsStore.cachedLocations, LocationItem.fromJson);
    if (coreLocations.isNotEmpty) _markCacheState(ref, stale: true);
  }
  // WAVEBREAK's own bundled pilot nodes (Direct-TLS + Hysteria2) are part
  // of the paid plan, not a fallback for accounts without one — a real
  // account that never subscribed must see the same "sign in to open
  // servers" / upgrade prompt a guest does, not extra free servers.
  final sub = await ref.watch(subscriptionProvider.future);
  if (!sub.isActive || sub.isExpired) return coreLocations;
  // Hardcoded, not fetched — see bundled_locations.dart. Always available
  // even with zero connectivity, so it's never gated behind the try/catch
  // above.
  final bundled = await ref.watch(bundledLocationsProvider.future);
  return [...coreLocations, ...bundled];
});

final devicesProvider = FutureProvider<List<DeviceItem>>((ref) async {
  if (!_canQueryCore(ref)) return const [];
  try {
    final result = await _withTimeout(ref.watch(coreGatewayProvider).devices());
    await _writeCache(
        PrefsStore.cachedDevices, result.map((d) => d.toJson()).toList());
    _markCacheState(ref, stale: false);
    return result;
  } catch (_) {
    final cached =
        _readCachedList(PrefsStore.cachedDevices, DeviceItem.fromJson);
    if (cached.isNotEmpty) {
      _markCacheState(ref, stale: true);
      return cached;
    }
    rethrow;
  }
});

final plansProvider = FutureProvider<List<Plan>>((ref) async {
  if (!_canQueryCore(ref)) return const [];
  try {
    final result = await _withTimeout(ref.watch(coreGatewayProvider).plans());
    await _writeCache(
        PrefsStore.cachedPlans, result.map((p) => p.toJson()).toList());
    _markCacheState(ref, stale: false);
    return result;
  } catch (_) {
    final cached = _readCachedList(PrefsStore.cachedPlans, Plan.fromJson);
    if (cached.isNotEmpty) {
      _markCacheState(ref, stale: true);
      return cached;
    }
    rethrow;
  }
});

/// Traffic used this billing period. `/v1/me/usage` is keyed on the
/// subscription, not any particular access grant — unlike a grant-config's
/// own `bytes_up`/`bytes_down` (only ever present for a Core-managed grant,
/// never true for WAVEBREAK's own bundled pilot nodes, which connect via a
/// raw share link — see bundled_locations.dart), this works regardless of
/// which node, or whether any, the user is currently connected through.
final trafficUsageProvider = FutureProvider<UsageSummary?>((ref) async {
  if (!_canQueryCore(ref)) return null;
  try {
    final result = await _withTimeout(ref.watch(coreGatewayProvider).usage());
    if (result != null) {
      await _writeCache(PrefsStore.cachedUsage, result.toJson());
    }
    _markCacheState(ref, stale: false);
    return result;
  } catch (_) {
    final cached =
        _readCachedOne(PrefsStore.cachedUsage, UsageSummary.fromJson);
    if (cached != null) {
      _markCacheState(ref, stale: true);
      return cached;
    }
    rethrow;
  }
});
