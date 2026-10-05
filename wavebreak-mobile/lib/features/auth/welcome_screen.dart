import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session_controller.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/storage/prefs_store.dart';
import '../../core/theme/wb_colors.dart';
import '../immersive/star_field.dart';
import '../immersive/tinted_glass.dart';
import '../shared/ocean_background.dart';
import '../shared/wavebreak_mark.dart';

/// The very first decision point, shown immediately on a fresh install —
/// before anything ever touches the network, since the "use my own link"
/// path specifically must not depend on WAVEBREAK's backend being
/// reachable. Recorded once via [PrefsStore.onboardingChoiceMade] so a
/// returning user (who picked login/register before) skips straight to
/// [LoginScreen] on later launches instead of re-choosing every time.
///
/// V5 look: wave field and vector stars, the serif headline, and one glass
/// panel with the choices. Google / Telegram sign-in are shown but
/// inactive until Core supports them; "Email" leads to the email sign-in.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  Future<void> _choose(
      BuildContext context, WidgetRef ref, String destination) async {
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
        child: Stack(
          children: [
            const Positioned.fill(child: StarField()),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: WavebreakWordmark()),
                    const SizedBox(height: 40),
                    Text(
                      s.welcomeKicker,
                      style: const TextStyle(
                        color: WbColors.muted,
                        fontSize: 12,
                        letterSpacing: 2.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Freedom\nMoves Forward.',
                      style: TextStyle(
                        fontFamily: 'serif',
                        fontSize: 44,
                        height: 1.08,
                        color: WbColors.ice,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      s.welcomeSub,
                      style: const TextStyle(
                          color: WbColors.ice60, fontSize: 15, height: 1.45),
                    ),
                    const SizedBox(height: 36),
                    TintedGlass(
                      radius: 24,
                      padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            s.welcomeChooseTitle,
                            style: const TextStyle(
                                fontFamily: 'serif', fontSize: 22),
                          ),
                          const SizedBox(height: 18),
                          FilledButton(
                            onPressed: () => _choose(context, ref, '/register'),
                            style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(52)),
                            child: Text(s.createAccount),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton(
                            onPressed: () => _choose(context, ref, '/login'),
                            style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(52)),
                            child: Text(s.iHaveAccount),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              const Expanded(
                                  child: Divider(color: WbColors.hairline)),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 10),
                                child: Text(s.orContinueWith,
                                    style: const TextStyle(
                                        color: WbColors.muted, fontSize: 12)),
                              ),
                              const Expanded(
                                  child: Divider(color: WbColors.hairline)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _SocialButton(
                                  icon: Icons.g_mobiledata_rounded,
                                  label: 'Google',
                                  note: s.comingSoon,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _SocialButton(
                                  icon: Icons.send_rounded,
                                  label: 'Telegram',
                                  note: s.comingSoon,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _SocialButton(
                                  icon: Icons.alternate_email_rounded,
                                  label: s.authEmail,
                                  onTap: () => _choose(context, ref, '/login'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Never gated on WAVEBREAK's own backend — this is the
                    // one path that must always work, network or no network.
                    Center(
                      child: TextButton(
                        onPressed: () async {
                          await PrefsStore.setBool(
                              PrefsStore.onboardingChoiceMade, true);
                          await ref
                              .read(sessionControllerProvider.notifier)
                              .continueAsGuest();
                        },
                        child: Text(
                          s.continueWithOwnLink,
                          style: const TextStyle(
                              color: WbColors.ice60, fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A sign-in method button; without [onTap] it's shown disabled with a
/// small "soon" note.
class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.icon,
    required this.label,
    this.note,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? note;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = enabled ? WbColors.ice : WbColors.muted;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          disabledForegroundColor: WbColors.muted,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(color: color, fontSize: 13)),
                ),
              ],
            ),
            if (note != null)
              Text(note!,
                  style: const TextStyle(color: WbColors.muted, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
