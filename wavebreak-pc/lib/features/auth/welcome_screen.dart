import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session_controller.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/storage/prefs_store.dart';
import '../../core/theme/wb_colors.dart';
import '../shared/ocean_background.dart';
import '../shared/wavebreak_mark.dart';

/// The very first decision point, shown immediately on a fresh install —
/// before anything ever touches the network, since the "use my own link"
/// path specifically must not depend on WAVEBREAK's backend being
/// reachable. Recorded once via [PrefsStore.onboardingChoiceMade] so a
/// returning user (who picked login/register before) skips straight to
/// [LoginScreen] on later launches instead of re-choosing every time.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  Future<void> _choose(BuildContext context, WidgetRef ref, String destination) async {
    await PrefsStore.setBool(PrefsStore.onboardingChoiceMade, true);
    if (!context.mounted) return;
    context.go(destination);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return Scaffold(
      body: OceanBackground(
        illuminate: true,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 56),
                const WavebreakMark(size: 72, glow: true),
                const SizedBox(height: 20),
                const WavebreakWordmark(),
                const Spacer(),
                Text(
                  s.welcomeChooseTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: () => _choose(context, ref, '/register'),
                    style: FilledButton.styleFrom(
                      backgroundColor: WbColors.waveCyan,
                      foregroundColor: WbColors.midnight,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      s.createAccount,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton(
                    onPressed: () => _choose(context, ref, '/login'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: WbColors.ice,
                      side: const BorderSide(color: WbColors.ice08),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(s.iHaveAccount, style: const TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 20),
                // Never gated on WAVEBREAK's own backend — this is the
                // one path that must always work, network or no network.
                TextButton(
                  onPressed: () async {
                    await PrefsStore.setBool(PrefsStore.onboardingChoiceMade, true);
                    await ref.read(sessionControllerProvider.notifier).continueAsGuest();
                  },
                  child: Text(
                    s.continueWithOwnLink,
                    style: const TextStyle(color: WbColors.ice60, fontSize: 14),
                  ),
                ),
                const Spacer(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
