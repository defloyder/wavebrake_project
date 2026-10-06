import '../../core/theme/wb_theme.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/providers.dart';
import '../shared/data_providers.dart';

/// An existing (signed-in) account confirms its email: a code is sent as
/// the sheet opens, the user types it, done. True when confirmed.
Future<bool> showEmailVerifySheet(BuildContext context,
    {required String email}) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: WbColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _EmailVerifySheet(email: email),
  );
  return confirmed ?? false;
}

class _EmailVerifySheet extends ConsumerStatefulWidget {
  const _EmailVerifySheet({required this.email});

  final String email;

  @override
  ConsumerState<_EmailVerifySheet> createState() => _EmailVerifySheetState();
}

class _EmailVerifySheetState extends ConsumerState<_EmailVerifySheet> {
  final _code = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _error;
  int _resendIn = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_send());
  }

  void _countdown() {
    _timer?.cancel();
    setState(() => _resendIn = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn = _resendIn > 0 ? _resendIn - 1 : 0);
      if (_resendIn == 0) t.cancel();
    });
  }

  Future<void> _send() async {
    final s = ref.read(stringsProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(coreGatewayProvider)
          .sendMyEmailCode(language: ref.read(languageProvider).name);
      if (!mounted) return;
      setState(() => _sent = true);
      _countdown();
    } on AppException catch (e) {
      if (!mounted) return;
      // A code went out less than a minute ago: it's still valid.
      if (e.kind == AppErrorKind.resendTooSoon) {
        setState(() => _sent = true);
        _countdown();
      } else {
        setState(() => _error = e.localized(s));
      }
    } catch (_) {
      if (mounted) setState(() => _error = s.errUnavailable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final code = _code.text.trim();
    if (code.length != 6 || _busy) return;
    final s = ref.read(stringsProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(coreGatewayProvider).verifyMyEmail(code);
      ref.invalidate(userProfileProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.localized(s));
      if (e.kind == AppErrorKind.codeInvalid) _code.clear();
    } catch (_) {
      if (mounted) setState(() => _error = s.errUnavailable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.verifyEmailTitle,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            _sent
                ? s.verifyEmailBody.replaceAll('{email}', widget.email)
                : widget.email,
            style: const TextStyle(color: WbColors.muted, height: 1.4),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _code,
            enabled: _sent,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: TextStyle(
              fontSize: 26,
              letterSpacing: 10,
              fontWeight: FontWeight.w600,
              color: context.accent,
            ),
            decoration: InputDecoration(
              hintText: s.verifyEmailCodeHint,
              hintStyle: const TextStyle(fontSize: 15, letterSpacing: 0),
              counterText: '',
            ),
            onChanged: (v) {
              if (v.length == 6) _confirm();
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: WbColors.error)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: (_busy || !_sent) ? null : _confirm,
              style: FilledButton.styleFrom(
                backgroundColor: context.accent,
                foregroundColor: WbColors.midnight,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : Text(s.verifyEmailConfirm),
            ),
          ),
          TextButton(
            onPressed: (_busy || _resendIn > 0) ? null : _send,
            child: Text(
              _resendIn > 0
                  ? s.verifyEmailResendIn.replaceAll('{s}', '$_resendIn')
                  : s.verifyEmailResend,
              style: TextStyle(
                color: _resendIn > 0 ? WbColors.muted : context.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            s.verifyEmailCheckSpam,
            textAlign: TextAlign.center,
            style: const TextStyle(color: WbColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
