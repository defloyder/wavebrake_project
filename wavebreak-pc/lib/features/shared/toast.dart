import 'package:flutter/material.dart';

import 'notice.dart';

export 'notice.dart' show NoticeKind, showNotice;

/// A short message — now one of the app's notices (notice.dart): the card
/// at the top, one at a time, the same text again does nothing. [messenger]
/// stays for the callers written for the old bottom toast; it isn't used.
void showToast(
  ScaffoldMessengerState? messenger,
  String text, {
  Duration duration = const Duration(seconds: 2),
  NoticeKind kind = NoticeKind.info,
  IconData? icon,
}) {
  showNotice(text, kind: kind, icon: icon, duration: duration);
}
