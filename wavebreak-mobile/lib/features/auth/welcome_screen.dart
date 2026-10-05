import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/wavebreak_mark.dart';
import '../../core/auth/session_controller.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/storage/prefs_store.dart';
import '../../core/theme/wb_colors.dart';
import '../immersive/earth_scene.dart';
import '../immersive/immersive_colors.dart';
import '../immersive/tinted_glass.dart';
import '../shared/ocean_background.dart';

/// The very first decision point, shown immediately on a fresh install —
/// before anything ever touches the network, since the "use my own link"
/// path specifically must not depend on WAVEBREAK's backend being
/// reachable. Recorded once via [PrefsStore.onboardingChoiceMade] so a
/// returning user (who picked login/register before) skips straight to
/// [LoginScreen] on later launches instead of re-choosing every time.
///
/// V5 look: the Earth scene ([EarthScene]: stars, the rotating night Earth,
/// orbit band) with the serif headline over it — above the choices on a
/// phone, beside them on a wide window — and one glass panel with the
/// choices. Google / Telegram sign-in are shown but
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
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 900;
    return Scaffold(
      body: OceanBackground(
        illuminate: true,
        maxContentWidth: double.infinity,
        child: wide
            ? _wideLayout(context, ref, s, size)
            : _phoneLayout(context, ref, s, size),
      ),
    );
  }

  /// Phone: the Earth scene on top (full width, under the status bar), the
  /// choices panel overlapping its lower edge; everything scrolls.
  Widget _phoneLayout(
      BuildContext context, WidgetRef ref, AppStrings s, Size size) {
    final sceneHeight = (size.height * 0.64).clamp(520.0, 600.0);
    final padding = MediaQuery.paddingOf(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: 24 + padding.bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: sceneHeight,
                child: EarthScene(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(26, padding.top + 22, 26, 44),
                    child: _SceneCopy(s: s, headlineSize: 44, centered: true),
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -24),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _choicesPanel(context, ref, s),
                      const SizedBox(height: 14),
                      _ownLink(ref, s),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Wide window: the scene as a large card on the left, the choices on
  /// the right.
  Widget _wideLayout(
      BuildContext context, WidgetRef ref, AppStrings s, Size size) {
    final headline = (size.width * 0.045).clamp(44.0, 68.0);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: EarthScene(
                borderRadius: 26,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(40, 36, 40, 30),
                  child: _SceneCopy(s: s, headlineSize: headline),
                ),
              ),
            ),
            const SizedBox(width: 32),
            SizedBox(
              width: 420,
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _choicesPanel(context, ref, s),
                      const SizedBox(height: 14),
                      _ownLink(ref, s),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choicesPanel(BuildContext context, WidgetRef ref, AppStrings s) {
    return TintedGlass(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.welcomeChooseTitle,
            style: const TextStyle(fontFamily: 'serif', fontSize: 22),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () => _choose(context, ref, '/register'),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
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
              const Expanded(child: Divider(color: WbColors.hairline)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(s.orContinueWith,
                    style:
                        const TextStyle(color: WbColors.muted, fontSize: 12)),
              ),
              const Expanded(child: Divider(color: WbColors.hairline)),
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
    );
  }

  // Never gated on WAVEBREAK's own backend — this is the one path that
  // must always work, network or no network.
  Widget _ownLink(WidgetRef ref, AppStrings s) {
    return Center(
      child: TextButton(
        onPressed: () async {
          await PrefsStore.setBool(PrefsStore.onboardingChoiceMade, true);
          await ref.read(sessionControllerProvider.notifier).continueAsGuest();
        },
        child: Text(
          s.continueWithOwnLink,
          style: const TextStyle(color: WbColors.ice60, fontSize: 14),
        ),
      ),
    );
  }
}

/// Text over the Earth scene: wordmark, kicker, the serif headline, the
/// subline, and a small caption at the bottom.
class _SceneCopy extends StatelessWidget {
  const _SceneCopy(
      {required this.s, required this.headlineSize, this.centered = false});

  final AppStrings s;
  final double headlineSize;

  /// Phone: the wordmark is centered; the copy itself stays left-aligned.
  final bool centered;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: centered ? Alignment.center : Alignment.centerLeft,
          // The real brand wordmark image, same as on Home.
          child: const WavebreakWordmark(size: 16),
        ),
        SizedBox(height: centered ? 44 : 40),
        Text(
          s.welcomeKicker,
          style: const TextStyle(
            color: Ic.textSecondary,
            fontSize: 12,
            letterSpacing: 2.4,
          ),
        ),
        const SizedBox(height: 14),
        // Two fixed lines; a longer translation shrinks instead of wrapping
        // into a third line over the planet.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            s.welcomeHeadline,
            softWrap: false,
            style: TextStyle(
              fontFamily: Ic.fontSerif,
              fontSize: headlineSize,
              height: 1.08,
              color: Ic.text,
            ),
          ),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text(
            s.welcomeSub,
            style: const TextStyle(
                color: Ic.textSecondary, fontSize: 15, height: 1.6),
          ),
        ),
        const Spacer(),
        const Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Ic.arctic,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Ic.arctic, blurRadius: 6)],
              ),
              child: SizedBox(width: 5, height: 5),
            ),
            SizedBox(width: 8),
            Text(
              'BEYOND THE HORIZON',
              style: TextStyle(
                  color: Ic.textSecondary, fontSize: 10, letterSpacing: 2),
            ),
          ],
        ),
      ],
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
