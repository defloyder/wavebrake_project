import 'package:flutter/material.dart';

/// One short message at a time. A new one replaces whatever is on screen
/// instead of queueing behind it, and the same text again while it is
/// still showing does nothing — tapping "refresh" ten times used to line
/// up ten toasts that kept coming for half a minute (owner, 06.10).
void showToast(
  ScaffoldMessengerState messenger,
  String text, {
  Duration duration = const Duration(seconds: 2),
}) {
  final now = DateTime.now();
  if (text == _lastText &&
      _lastUntil != null &&
      now.isBefore(_lastUntil!)) {
    return;
  }
  _lastText = text;
  _lastUntil = now.add(duration);
  messenger
    ..removeCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), duration: duration));
}

String? _lastText;
DateTime? _lastUntil;
