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
    this.usedBytes,
    this.totalBytes,
    this.expiresAt,
    this.updateIntervalHours,
    this.updatedAt,
  });

  final String id;

  /// The provider's `profile-title` when it sends one, else the host.
  final String name;

  /// The original URL or raw link the user provided. Kept only so the user
  /// can re-share or refresh it — never sent to WAVEBREAK Core.
  final String sourceLink;
  final List<LocationItem> servers;

  /// Someone's WAVEBREAK subscription redeemed from their share QR. It
  /// holds one of the owner's device slots, so it is never re-shared from
  /// here: passing its link on would skip the owner's device limit.
  final bool sharedWithMe;

  /// From the provider's `subscription-userinfo` header: traffic used
  /// (upload + download), the limit (null or 0 = unlimited) and the end
  /// date. All null when the provider doesn't send it.
  final int? usedBytes;
  final int? totalBytes;
  final DateTime? expiresAt;

  /// `profile-update-interval` (hours) — how often to re-read the URL.
  final int? updateIntervalHours;

  /// When the URL was last read successfully.
  final DateTime? updatedAt;

  bool get isSubscriptionUrl =>
      sourceLink.startsWith('http://') || sourceLink.startsWith('https://');

  /// Re-read the URL when this much time has passed (12 h by default).
  Duration get refreshEvery => Duration(hours: updateIntervalHours ?? 12);

  bool isStale(DateTime now) =>
      isSubscriptionUrl &&
      !sharedWithMe &&
      (updatedAt == null || now.difference(updatedAt!) >= refreshEvery);
}
