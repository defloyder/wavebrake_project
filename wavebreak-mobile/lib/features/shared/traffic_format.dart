import '../../core/i18n/app_strings.dart';

/// Bytes per ГБ. Binary, the same base Core uses for plan limits, so
/// "100 ГБ" in the app is exactly the plan's 100 × 1024³ bytes.
const int bytesPerGb = 1024 * 1024 * 1024;

/// Bytes per МБ (binary as well).
const int bytesPerMb = 1024 * 1024;

/// "312 МБ / 300 ГБ", "12.4 ГБ / 300 ГБ", or "... / Unlimited" when the plan
/// has no [limitBytes] (Core's `traffic_limit_bytes` is nullable —
/// unmetered plans just never set it). Shared between the subscription
/// screen's own detail card and Home's subscription strip so both read the
/// same number the same way.
String formatTraffic(int usedBytes, int? limitBytes, AppStrings s) {
  final used = formatBytes(usedBytes, s);
  if (limitBytes == null) return '$used / ${s.trafficUnlimited}';
  return '$used / ${formatBytes(limitBytes, s)}';
}

/// Below 1 ГБ in МБ so small usage is visible (whole МБ, one decimal under
/// 10 МБ); from 1 ГБ in ГБ with one decimal.
String formatBytes(int bytes, AppStrings s) {
  final mb = bytes / bytesPerMb;
  if (mb.round() < 1024) {
    final value = mb < 10 ? _trim(mb.toStringAsFixed(1)) : mb.round().toString();
    return '$value ${s.unitMb}';
  }
  return '${formatGb(bytes)} ${s.unitGb}';
}

/// One decimal, trailing ".0" dropped: 100 × 1024³ -> "100", 1.5 × 1024³ -> "1.5".
String formatGb(int bytes) => _trim((bytes / bytesPerGb).toStringAsFixed(1));

String _trim(String value) =>
    value.endsWith('.0') ? value.substring(0, value.length - 2) : value;
