import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/session_controller.dart';
import '../../core/errors/app_exception.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/providers.dart';
import '../shared/nav_utils.dart';
import '../shared/ocean_background.dart';
import '../shared/wave_params.dart';
import '../shared/wavebreak_mark.dart';

/// Step after sign-up (or a sign-in of an account that isn't confirmed
/// yet): enter the 6-digit code Core emailed. A confirmed code signs the
/// user in (Core returns tokens), exactly like a login.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen(
      {super.key, required this.email, this.codeSent = true});

  final String email;

  /// False when Core created the account but the email didn't go out —
  /// the screen then offers "send again" straight away.
  final bool codeSent;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  static const _resendAfter = 60;

  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _info;
  int _resendIn = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.codeSent) _startCountdown();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _resendIn = _resendAfter);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn = _resendIn > 0 ? _resendIn - 1 : 0);
      if (_resendIn == 0) t.cancel();
    });
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    if (code.length != 6 || _busy) return;
    final s = ref.read(stringsProvider);
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final tokens = await ref
          .read(coreGatewayProvider)
          .verifyEmail(email: widget.email, code: code)
          .timeout(const Duration(seconds: 30),
              onTimeout: () => throw AppException(AppErrorKind.unavailable));
      await ref
          .read(sessionControllerProvider.notifier)
          .onAuthenticated(tokens);
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.localized(s));
      if (error.kind == AppErrorKind.codeInvalid) _code.clear();
    } catch (_) {
      if (mounted) setState(() => _error = s.errUnavailable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_resendIn > 0 || _busy) return;
    final s = ref.read(stringsProvider);
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await ref.read(coreGatewayProvider).resendEmailCode(
            email: widget.email,
            language: ref.read(languageProvider).name,
          );
      if (!mounted) return;
      setState(
          () => _info = s.verifyEmailSent.replaceAll('{email}', widget.email));
      _code.clear();
      _startCountdown();
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.localized(s));
      if (error.kind == AppErrorKind.resendTooSoon) _startCountdown();
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
    final waves = ref.watch(appWaveParamsProvider);
    final notSent = !widget.codeSent && _info == null;
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
                  s.verifyEmailTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: 'serif', fontSize: 26),
                ),
                const SizedBox(height: 10),
                Text(
                  notSent
                      ? s.errEmailSendFailed
                      : s.verifyEmailBody.replaceAll('{email}', widget.email),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: notSent ? WbColors.warning : WbColors.muted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _code,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                    fontSize: 28,
                    letterSpacing: 10,
                    fontWeight: FontWeight.w600,
                    color: WbColors.waveCyan,
                  ),
                  decoration: InputDecoration(
                    hintText: s.verifyEmailCodeHint,
                    hintStyle: const TextStyle(fontSize: 16, letterSpacing: 0),
                    counterText: '',
                  ),
                  onChanged: (v) {
                    if (v.length == 6) _submit();
                  },
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: WbColors.error)),
                ],
                if (_info != null) ...[
                  const SizedBox(height: 12),
                  Text(_info!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: WbColors.waveCyan)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: WbColors.waveCyan,
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
                        : Text(s.verifyEmailConfirm),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: (_busy || _resendIn > 0) ? null : _resend,
                  child: Text(
                    _resendIn > 0
                        ? s.verifyEmailResendIn.replaceAll('{s}', '$_resendIn')
                        : s.verifyEmailResend,
                    style: TextStyle(
                      color: _resendIn > 0 ? WbColors.muted : WbColors.waveCyan,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  s.verifyEmailCheckSpam,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: WbColors.muted, fontSize: 12),
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
