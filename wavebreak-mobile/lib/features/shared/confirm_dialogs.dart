import 'package:flutter/material.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/wb_colors.dart';

/// A custom/BYO server's link lives only on this device — unlike a
/// WAVEBREAK-hosted location, deleting it is not recoverable from the
/// account, so a stray tap on the "..." menu's remove item (right next to
/// refresh/share in the same small popup) used to delete it immediately,
/// with no way back except re-pasting the link from wherever it first came
/// from — often nowhere, if it isn't saved elsewhere.
Future<bool> confirmRemoveCustomGroup(BuildContext context, AppStrings s) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: WbColors.card,
      title: Text(s.removeCustomServerTitle),
      content: Text(s.removeCustomServerBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(s.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(s.remove, style: const TextStyle(color: WbColors.error)),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
