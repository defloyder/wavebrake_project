import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../core/theme/wb_theme.dart';
import '../../services/providers.dart';
import '../shared/nav_utils.dart';
import '../shared/ocean_background.dart';
import '../shared/wave_params.dart';
import '../shared/wavebreak_mark.dart';

/// Sign-in without the password, step 1: the account's email. Core mails
/// a one-time code (silently nothing for an unknown address, so this can't
/// probe for accounts); step 2 is [VerifyEmailScreen] in login-code mode.
class EmailCodeScreen extends ConsumerStatefulWidget {
  const EmailCodeScreen({super.key});

  @override
  ConsumerState<EmailCodeScreen> createState() => _EmailCodeScreenState();
}

class _EmailCodeScreenState extends ConsumerState<EmailCodeScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;

  static final _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  Future<void> _send() async {
    final email = _email.text.trim();
    final s = ref.read(stringsProvider);
    if (!_emailShape.hasMatch(email)) return;
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    var sent = true;
    try {
      await ref.read(coreGatewayProvider).requestLoginCode(
            email: email,
            language: ref.read(languageProvider).name,
          );
    } on AppException catch (error) {
      // A server without sign-in codes yet (404) or without email (503):
      // the password sign-in is the way in, not a dead end.
      if (error.statusCode == 404 ||
          error.statusCode == 405 ||
          error.statusCode == 503) {
        if (mounted) setState(() => _busy = false);
        if (mounted) context.go('/login');
        return;
      }
      // A code went out less than a minute ago: it's still valid, go on
      // to entering it.
      if (error.kind != AppErrorKind.resendTooSoon) {
        if (mounted) setState(() => _error = error.localized(s));
        sent = false;
      }
    } catch (_) {
      if (mounted) setState(() => _error = s.errUnavailable);
      sent = false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!sent || !mounted) return;
    context.push('/verify-email',
        extra: {'email': email, 'sent': true, 'login': true});
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final waves = ref.watch(appWaveParamsProvider);
    return Scaffold(
      body: OceanBackground(
        stars: true,
        illuminate: true,
        tint: waves.tint,
        waveSpeed: waves.speed,
        waveAmplitude: waves.amplitude,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => safePop(context, fallback: '/login'),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  ),
                ),
                const WavebreakMark(size: 64),
                const SizedBox(height: 16),
                Text(
                  s.emailCodeTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'serif', fontSize: 26),
                ),
                const SizedBox(height: 10),
                Text(
                  s.emailCodeHint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: WbColors.muted, height: 1.4),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _email,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(hintText: s.email),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _send(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: WbColors.error)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    // Enabled once the text looks like an address.
                    onPressed: _busy || !_emailShape.hasMatch(_email.text.trim())
                        ? null
                        : _send,
                    style: FilledButton.styleFrom(
                      backgroundColor: context.accent,
                      foregroundColor: WbColors.midnight,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : Text(s.emailCodeSend),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
