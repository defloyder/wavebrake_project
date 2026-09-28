import '../core_api/models.dart';

/// One imported subscription — either a single pasted server link, or a
/// subscription URL that expanded into many servers, exactly like Happ
/// treats "Duck VPN" or "VAULTS.PRO" as one card containing many locations.
class CustomSubscriptionGroup {
  const CustomSubscriptionGroup({
    required this.id,
    required this.name,
    required this.sourceLink,
    required this.servers,
    this.sharedWithMe = false,
  });

  final String id;
  final String name;

  /// The original URL or raw link the user provided. Kept only so the user
  /// can re-share or refresh it — never sent to WAVEBREAK Core.
  final String sourceLink;
  final List<LocationItem> servers;

  /// Someone's WAVEBREAK subscription redeemed from their share QR. It
  /// holds one of the owner's device slots, so it is never re-shared from
  /// here: passing its link on would skip the owner's device limit.
  final bool sharedWithMe;

  bool get isSubscriptionUrl =>
      sourceLink.startsWith('http://') || sourceLink.startsWith('https://');
}
