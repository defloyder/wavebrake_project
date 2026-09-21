import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/session_controller.dart';
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
bool _canQueryCore(Ref ref) => ref.watch(
    sessionControllerProvider.select((s) => s.phase == SessionPhase.authenticated));

const _noSubscription = SubscriptionInfo(status: 'none');

final subscriptionProvider = FutureProvider<SubscriptionInfo>((ref) async {
  if (!_canQueryCore(ref)) return _noSubscription;
  return ref.watch(coreGatewayProvider).subscription();
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
  final rawCoreLocations = await ref.watch(coreGatewayProvider).locations();
  // Core's pilot node currently only publishes a VLESS+REALITY transport,
  // which was never confirmed working end-to-end from the unified
  // Xray-core engine this session (unlike Direct-TLS/WS and Hysteria2,
  // both fully tested) — showing it as a normal-looking "WAVEBREAK Plus"
  // entry that just silently fails to connect is worse than not listing
  // it at all. Drop it until REALITY is verified; everything else Core
  // reports is unaffected.
  final coreLocations = rawCoreLocations
      .where((l) => l.connectionTest?.security?.toLowerCase() != 'reality')
      .toList();
  // WAVEBREAK's own bundled pilot nodes (Direct-TLS + Hysteria2) are part
  // of the paid plan, not a fallback for accounts without one — a real
  // account that never subscribed must see the same "sign in to open
  // servers" / upgrade prompt a guest does, not extra free servers.
  final sub = await ref.watch(subscriptionProvider.future);
  if (!sub.isActive || sub.isExpired) return coreLocations;
  final bundled = await ref.watch(bundledLocationsProvider.future);
  return [...coreLocations, ...bundled];
});

final devicesProvider = FutureProvider<List<DeviceItem>>((ref) async {
  if (!_canQueryCore(ref)) return const [];
  return ref.watch(coreGatewayProvider).devices();
});

final plansProvider = FutureProvider<List<Plan>>((ref) async {
  if (!_canQueryCore(ref)) return const [];
  return ref.watch(coreGatewayProvider).plans();
});

/// Traffic used this billing period. `/v1/me/usage` is keyed on the
/// subscription, not any particular access grant — unlike a grant-config's
/// own `bytes_up`/`bytes_down` (only ever present for a Core-managed grant,
/// never true for WAVEBREAK's own bundled pilot nodes, which connect via a
/// raw share link — see bundled_locations.dart), this works regardless of
/// which node, or whether any, the user is currently connected through.
final trafficUsageProvider = FutureProvider<UsageSummary?>((ref) async {
  if (!_canQueryCore(ref)) return null;
  return ref.watch(coreGatewayProvider).usage();
});
