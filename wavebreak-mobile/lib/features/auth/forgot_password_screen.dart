import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/providers.dart';
import '../shared/nav_utils.dart';
import '../shared/ocean_background.dart';
import '../shared/wave_params.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final s = ref.read(stringsProvider);
    try {
      await ref.read(coreGatewayProvider).forgotPassword(_email.text.trim());
      setState(() => _sent = true);
    } on AppException catch (error) {
      setState(() => _error = error.localized(s));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    s.forgotPassword,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    s.enterEmailReset,
                    style: const TextStyle(color: WbColors.ice60),
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(hintText: s.email),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: WbColors.error)),
                ],
                if (_sent) ...[
                  const SizedBox(height: 12),
                  Text(s.checkEmailToContinue),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _busy || _sent ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: WbColors.waveCyan,
                      foregroundColor: WbColors.midnight,
                    ),
                    child: Text(s.send),
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
