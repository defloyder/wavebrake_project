import 'package:intl/intl.dart';

import '../../core/i18n/app_strings.dart';
import '../../services/core_api/models.dart';

/// "Renew before 04.10.2026" for a past_due subscription, or the plain
/// reset note when Core didn't say until when. Shared by Home's
/// subscription strip and the subscription screen.
String renewBeforeLine(SubscriptionInfo sub, AppStrings s) {
  final until = sub.graceEndsAt;
  if (until == null) return s.renewResetNote;
  return '${s.renewBefore} ${DateFormat('dd.MM.yyyy').format(until.toLocal())}';
}

/// Status label: "Active", "Awaiting renewal", else Core's raw status.
String subscriptionStatusLabel(SubscriptionInfo sub, AppStrings s) {
  if (sub.isActive) return s.active;
  if (sub.isPastDue) return s.statusPastDue;
  return sub.status;
}
