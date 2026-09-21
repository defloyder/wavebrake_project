import '../../core/i18n/app_strings.dart';

/// "12.4 GB / 100 GB", or "12.4 GB / Unlimited" when the plan has no
/// [limitBytes] at all (Core's `traffic_limit_bytes` is nullable —
/// unmetered plans just never set it). Shared between the subscription
/// screen's own detail card and Home's subscription strip so both read the
/// same number the same way.
String formatTraffic(int usedBytes, int? limitBytes, AppStrings s) {
  String gb(int bytes) => (bytes / (1000 * 1000 * 1000)).toStringAsFixed(1);
  final used = '${gb(usedBytes)} GB';
  if (limitBytes == null) return '$used / ${s.trafficUnlimited}';
  return '$used / ${gb(limitBytes)} GB';
}
