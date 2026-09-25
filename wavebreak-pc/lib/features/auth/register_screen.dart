import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
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

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  CancelToken? _cancelToken;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final s = ref.read(stringsProvider);
    // Same CancelToken treatment as login_screen.dart's own fix — a
    // register call that outlives this screen (timed out, or the user
    // backed out mid-request) must not linger in ApiClient's
    // QueuedInterceptor queue and block a subsequent attempt from even
    // starting. See login_screen.dart's _submit() doc comment for the
    // full mechanism.
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    try {
      final tokens = await ref
          .read(coreGatewayProvider)
          .register(
            email: _email.text.trim(),
            password: _password.text,
            cancelToken: cancelToken,
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              cancelToken.cancel('register UI timeout');
              throw AppException(AppErrorKind.noInternet);
            },
          );
      await ref.read(sessionControllerProvider.notifier).onAuthenticated(tokens);
    } on AppException catch (error) {
      if (mounted) setState(() => _error = error.localized(s));
    } catch (_) {
      if (mounted) setState(() => _error = s.errUnavailable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    return Scaffold(
      body: OceanBackground(
        illuminate: true,
        tint: waves.tint,
        waveSpeed: waves.speed,
        waveAmplitude: waves.amplitude,
        child: SafeArea(
          // No scroll container here previously — once the keyboard
          // shrinks the viewport enough, content would overflow instead
          // of scrolling (same class of bug as the login screen's fields
          // riding up over the logo).
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
                  s.createAccount,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(hintText: s.email),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(hintText: s.password),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: WbColors.error)),
                  // Same reasoning as login_screen.dart's own fix — a
                  // failed sign-up gets an immediate, contextual way
                  // around it (guest mode / own subscription link)
                  // instead of leaving someone stuck with no path forward
                  // other than retrying the same failing request.
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
                    child: Text(s.createAccount),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
