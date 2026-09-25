import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session_controller.dart';
import '../../core/errors/app_exception.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/storage/prefs_store.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/analytics/analytics.dart';
import '../../services/biometric/biometric_service.dart';
import '../../services/pin/pin_service.dart';
import '../../services/providers.dart';
import '../settings/pin_setup_screen.dart';
import '../shared/ocean_background.dart';
import '../shared/wave_params.dart';
import '../shared/wavebreak_mark.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _bio = BiometricService();
  final _pin = const PinService();
  bool _busy = false;
  String? _error;
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowForcedLogoutNotice();
    });
  }

  void _maybeShowForcedLogoutNotice() {
    final reason = ref.read(forcedLogoutReasonProvider);
    if (reason == null) return;
    ref.read(forcedLogoutReasonProvider.notifier).state = null;
    final s = ref.read(stringsProvider);
    final message = reason == AppErrorKind.accessDenied
        ? s.errAccessDenied
        : s.sessionExpiredNotice;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final s = ref.read(stringsProvider);
    // Real-device bug this fixes: "loads for a long time and doesn't log
    // in — pressing sign in a second time works." Root cause was that
    // ApiClient's Dio instance runs auth through a QueuedInterceptor
    // (auth_interceptor.dart), which processes every request's
    // interceptor lifecycle strictly in order across the WHOLE client —
    // and the previous code's `.timeout(15s)` only abandoned the AWAIT on
    // the client side; it never cancelled the underlying Dio request,
    // which kept running (and kept its place in that queue) in the
    // background. A first attempt slow past 15s (cold TLS handshake, a
    // congested network) left an orphaned request still occupying the
    // queue; the user's second tap then queued BEHIND it and couldn't
    // even start until the first one finally finished — at which point
    // the connection was warm and the second attempt resolved almost
    // instantly, LOOKING like the second click was what worked, while
    // the first attempt's own (possibly successful) result had already
    // been discarded by the timeout that gave up on it. A real
    // [CancelToken], cancelled the moment this attempt gives up, frees
    // the queue immediately instead of leaving a zombie request behind
    // it — so a retry is actually independent, not queued behind a ghost
    // of the last one. login() now also retries internally on a real
    // connection-level failure (ApiClient's own `retryOnConnectionError`
    // — see core_api.dart), up to ~23s worst case on its own (3 attempts
    // × its 7s per-attempt budget + backoff); 30s here sits comfortably
    // above that instead of cutting an internal retry off early.
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    try {
      final tokens = await ref
          .read(coreGatewayProvider)
          .login(
            email: _email.text.trim(),
            password: _password.text,
            cancelToken: cancelToken,
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              cancelToken.cancel('login UI timeout');
              throw AppException(AppErrorKind.noInternet);
            },
          );
      await ref
          .read(sessionControllerProvider.notifier)
          .onAuthenticated(tokens);
      const Analytics().event('login_success');
      if (!mounted) return;
      await _offerBiometric();
    } on AppException catch (error) {
      if (mounted) setState(() => _error = error.localized(s));
    } catch (_) {
      if (mounted) setState(() => _error = s.errUnavailable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _offerBiometric() async {
    if (PrefsStore.getBool(PrefsStore.biometricPromptShown)) return;
    final available = await _bio.isAvailable();
    if (!mounted || !available) return;
    await PrefsStore.setBool(PrefsStore.biometricPromptShown, true);
    if (!mounted) return;
    final s = ref.read(stringsProvider);
    final enable = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: WbColors.card,
          title: Text(s.biometricPromptTitle),
          content: Text(s.biometricPromptBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.notNow),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.enable),
            ),
          ],
        );
      },
    );
    if (enable != true) return;
    // Same requirement as turning this on from Security settings (see
    // security_screen.dart's own comment): a PIN is the only fallback a
    // failed/misbehaving biometric scan has, and this first-login prompt
    // was a second, separate path to ending up with biometric-only lock
    // and no PIN ever set — the exact state that left a product owner
    // permanently locked out. Not optional here either.
    if (!_pin.isSet) {
      if (!mounted) return;
      final saved = await showPinSetupScreen(
        context,
        subtitle: s.pinRequiredForBiometric,
      );
      if (saved != true) return;
    }
    await _bio.setEnabled(true);
    await PrefsStore.setBool(PrefsStore.appLockEnabled, true);
  }

  @override
  void dispose() {
    _cancelToken?.cancel('screen disposed');
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final waves = ref.watch(appWaveParamsProvider);
    // The Spacer-based centered layout below only has real slack to give
    // up when the keyboard is closed — once it opens on a shorter phone,
    // both Spacers collapse to zero and the fields end up jammed directly
    // under the logo with no gap at all (confirmed on-device: reads as
    // "the keyboard pushed the fields onto the logo" even though nothing
    // actually overlaps). Shrinking the logo away while the keyboard is
    // open removes the fight for space entirely instead of trying to
    // out-scroll it.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      body: OceanBackground(
        illuminate: true,
        tint: waves.tint,
        waveSpeed: waves.speed,
        waveAmplitude: waves.amplitude,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: AutofillGroup(
                      child: Column(
                        children: [
                          AnimatedSize(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            child: keyboardOpen
                                ? const SizedBox(height: 16)
                                : Column(
                                    children: [
                                      const SizedBox(height: 48),
                                      const WavebreakMark(size: 72, glow: true),
                                      const SizedBox(height: 20),
                                      const WavebreakWordmark(),
                                    ],
                                  ),
                          ),
                          const Spacer(),
                          TextField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: InputDecoration(hintText: s.email),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _password,
                            obscureText: true,
                            autofillHints: const [AutofillHints.password],
                            decoration: InputDecoration(hintText: s.password),
                            onSubmitted: (_) => _submit(),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: const TextStyle(color: WbColors.error),
                              textAlign: TextAlign.center,
                            ),
                            // A failed sign-in already has an escape hatch
                            // at the bottom of this screen (guest mode /
                            // "continue with your own link"), but it's a
                            // small, muted, always-there link with no
                            // connection to whatever just went wrong —
                            // someone stuck on a real login/connectivity
                            // problem has no reason to notice it's exactly
                            // the way around this. Surfacing it right next
                            // to the error itself, only when there IS an
                            // error, makes it an actual answer to "I can't
                            // sign in" instead of an unrelated nav item.
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () async {
                                await ref
                                    .read(sessionControllerProvider.notifier)
                                    .continueAsGuest();
                              },
                              child: Text(
                                s.continueWithOwnLink,
                                style: const TextStyle(
                                  color: WbColors.waveCyan,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
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
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : Text(
                                      s.signIn,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600),
                                    ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => context.push('/forgot'),
                            child: Text(s.forgotPassword),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => context.push('/register'),
                            child: Text.rich(
                              TextSpan(
                                text: s.noAccount,
                                style: const TextStyle(color: WbColors.ice60),
                                children: [
                                  TextSpan(
                                    text: s.createAccount,
                                    style: const TextStyle(
                                        color: WbColors.waveCyan),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // The Welcome screen only ever shows once, on a fresh
                          // install — after that, landing here (e.g. from tapping
                          // "Sign in" while in guest mode, then backing out) must
                          // never be a one-way door with no way back to guest use.
                          TextButton(
                            onPressed: () async {
                              await ref
                                  .read(sessionControllerProvider.notifier)
                                  .continueAsGuest();
                            },
                            child: Text(
                              s.continueWithOwnLink,
                              style: const TextStyle(
                                  color: WbColors.ice60, fontSize: 13),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
