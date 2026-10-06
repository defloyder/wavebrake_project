import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/providers.dart';
import '../shared/qr_scan_screen.dart';
import '../shared/toast.dart';

final _codeInUrl = RegExp(r'/v1/device-login/([A-Za-z0-9]{8})(?:$|[/?#])');
final _bareCode = RegExp(r'^[A-Z0-9]{8}$');

/// The format of a TV code, as a hint in the field (not a translation).
const _codeFormat = 'ABCD-EFGH';

/// The code from what the TV shows: its QR (Core's /v1/device-login/CODE
/// address) or the code typed by hand ("ABCD-EFGH", any case). Null for
/// anything else.
String? deviceLoginCode(String raw, {bool allowBare = true}) {
  final text = raw.trim();
  final m = _codeInUrl.firstMatch(text);
  if (m != null) return m.group(1)!.toUpperCase();
  if (!allowBare) return null;
  final bare = text.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  return _bareCode.hasMatch(bare) ? bare : null;
}

/// Settings → Account → "Sign in on another device": scan the TV's QR
/// (phones), or type its code (PC), then confirm.
Future<void> startDeviceLoginApproval(BuildContext context, WidgetRef ref) async {
  final s = ref.read(stringsProvider);
  String? code;
  if (Platform.isAndroid || Platform.isIOS) {
    final raw = await Navigator.of(context, rootNavigator: true).push<String>(
        MaterialPageRoute(builder: (_) => QrScanScreen(s: s)));
    if (raw == null || !context.mounted) return;
    code = deviceLoginCode(raw);
  } else {
    code = await _askCode(context, s);
    if (code == null || !context.mounted) return;
    code = deviceLoginCode(code);
  }
  if (!context.mounted) return;
  if (code == null) {
    showToast(ScaffoldMessenger.of(context), s.deviceLoginExpired);
    return;
  }
  await approveDeviceLoginCode(context, ref, code);
}

/// Shows which device asks, and signs it in on "Sign in". The device gets
/// a session of its own; this one stays signed in.
Future<void> approveDeviceLoginCode(
    BuildContext context, WidgetRef ref, String code) async {
  final s = ref.read(stringsProvider);
  final gateway = ref.read(coreGatewayProvider);
  final messenger = ScaffoldMessenger.of(context);
  String device;
  try {
    device = await gateway.inspectDeviceLogin(code);
  } on AppException catch (e) {
    showToast(messenger,
        e.statusCode == 404 ? s.deviceLoginExpired : e.localized(s));
    return;
  } catch (_) {
    showToast(messenger, s.errUnavailable);
    return;
  }
  if (device.isEmpty) device = 'TV';
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: WbColors.card,
      title: Text(s.deviceLoginConfirm.replaceAll('{device}', device)),
      content: Text(s.deviceLoginConfirmNote,
          style: const TextStyle(color: WbColors.ice60)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
        FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.signIn)),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await gateway.approveDeviceLogin(code);
    showToast(messenger, s.deviceLoginDone.replaceAll('{device}', device),
        duration: const Duration(seconds: 3));
  } on AppException catch (e) {
    showToast(messenger,
        e.statusCode == 404 ? s.deviceLoginExpired : e.localized(s));
  } catch (_) {
    showToast(messenger, s.errUnavailable);
  }
}

Future<String?> _askCode(BuildContext context, AppStrings s) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: WbColors.card,
      title: Text(s.signInOtherDevice),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(
          labelText: s.deviceLoginCodeLabel,
          hintText: _codeFormat,
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(s.signIn)),
      ],
    ),
  );
}
