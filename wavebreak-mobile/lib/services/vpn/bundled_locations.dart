import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core_api/models.dart';
import '../custom_servers/share_link_parsing.dart';

/// WAVEBREAK's own pilot nodes (Direct-TLS VLESS + Hysteria2, see
/// native_vpn_adapter.dart's history for how those two got built) —
/// bundled with every paid plan rather than something a subscriber has to
/// paste in themselves via "Add your own link". Someone using the app
/// purely as a shell for their own servers (guest mode, or an account with
/// no active plan) never sees this — see data_providers.dart's
/// [locationsProvider].
///
/// Hardcoded rather than fetched from sub.wavebreak.com.tr (the previous
/// approach): that subscription generator turned out to be its own,
/// separately-maintained piece of infrastructure that silently drifted out
/// of sync with the actual pilot deployment — confirmed on-device twice
/// now. First the whole subscription ID it was keyed on stopped existing
/// after a database reset (plain 404). Then, even pointed at one of the
/// pilot's current shared credentials, it kept publishing Direct-TLS on
/// port 443 — the port Xray-core's `vless-direct-tls` inbound was
/// listening on when that generator was last updated — while the actual
/// deployment had since moved it to 18444 (confirmed directly against the
/// node: a raw TLS handshake to port 18444 works, 443 there now belongs to
/// an unrelated service on the same host, and the firewall itself still
/// only allowed the *old* 9443 until this session opened 18444 too). A
/// generator that quietly goes stale is worse than no generator: nothing
/// in that failure mode is visible to a subscriber, it just doesn't work.
/// These two links were re-verified directly against the node's own
/// listening ports/certs as of 2026-09-17.
const _directTlsLink =
    'vless://57afe491-b30b-498f-a8f9-4422d6de1231@direct.wavebreak.com.tr:18444'
    '?encryption=none&host=direct.wavebreak.com.tr&path=%2Fwvb-dt&security=tls'
    '&sni=direct.wavebreak.com.tr&type=ws'
    '#%F0%9F%87%B3%F0%9F%87%B1%20Netherlands%2C%20Amsterdam%20%28Direct-TLS%29';

const _hysteria2Link =
    'hysteria2://57afe491-b30b-498f-a8f9-4422d6de1231:57afe491-b30b-498f-a8f9-4422d6de1231'
    '@91.149.241.52:443/?alpn=h3&sni=hy2.wavebreak.com.tr'
    '#%F0%9F%87%B3%F0%9F%87%B1%20Netherlands%2C%20Amsterdam%20%28Hysteria2%29';

final bundledLocationsProvider = FutureProvider<List<LocationItem>>((ref) async {
  return parseSubscriptionBody('$_directTlsLink\n$_hysteria2Link');
});
