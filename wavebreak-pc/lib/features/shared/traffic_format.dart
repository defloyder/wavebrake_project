import '../../core/i18n/app_strings.dart';

/// Bytes per ГБ. Binary, the same base Core uses for plan limits, so
/// "100 ГБ" in the app is exactly the plan's 100 × 1024³ bytes.
const int bytesPerGb = 1024 * 1024 * 1024;

/// "12,4 ГБ / 100 ГБ" (unit from [AppStrings.unitGb]), or
/// "12.4 GB / Unlimited" when the plan has no [limitBytes] at all
/// (Core's `traffic_limit_bytes` is nullable — unmetered plans just never
/// set it). Shared between the subscription screen's own detail card and
/// Home's subscription strip so both read the same number the same way.
String formatTraffic(int usedBytes, int? limitBytes, AppStrings s) {
  final used = '${formatGb(usedBytes)} ${s.unitGb}';
  if (limitBytes == null) return '$used / ${s.trafficUnlimited}';
  return '$used / ${formatGb(limitBytes)} ${s.unitGb}';
}

/// One decimal, trailing ".0" dropped: 100 × 1024³ -> "100", 1.5 × 1024³ -> "1.5".
String formatGb(int bytes) {
  final value = (bytes / bytesPerGb).toStringAsFixed(1);
  return value.endsWith('.0') ? value.substring(0, value.length - 2) : value;
}
