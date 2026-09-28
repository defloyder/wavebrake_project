import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session_controller.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../shared/data_providers.dart';
import '../shared/detail_scaffold.dart';
import '../shared/nav_utils.dart';
import '../shared/wb_card.dart';
import 'email_verify_sheet.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final subscription = ref.watch(subscriptionProvider);
    final profile = ref.watch(userProfileProvider);
    final s = ref.watch(stringsProvider);
    final isGuest = session.phase == SessionPhase.guest;

    if (isGuest) {
      return DetailScaffold(
        title: s.account,
        onBack: () => safePop(context, fallback: '/settings'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WbCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.signInToUnlock,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: () async {
                  await ref
                      .read(sessionControllerProvider.notifier)
                      .exitGuestMode();
                  if (context.mounted) context.go('/login');
                },
                style: FilledButton.styleFrom(
                  backgroundColor: WbColors.waveCyan,
                  foregroundColor: WbColors.midnight,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(s.signIn),
              ),
            ),
          ],
        ),
      );
    }

    return DetailScaffold(
      title: s.account,
      onBack: () => safePop(context, fallback: '/settings'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Builder(builder: (context) {
            final me = profile.asData?.value;
            final email = me?.email ?? session.user?.email ?? '—';
            // Confirming is offered only when Core reports the
            // address unconfirmed and can send the code now.
            final canVerify = me != null &&
                me.emailVerified == false &&
                me.emailVerificationAvailable;
            return WbCard(
              onTap: canVerify
                  ? () async {
                      final ok =
                          await showEmailVerifySheet(context, email: me.email);
                      if (ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(s.emailVerifiedRow)));
                      }
                    }
                  : null,
              child: Row(
                children: [
                  const Icon(Icons.email_outlined, color: WbColors.waveCyan),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(email, style: const TextStyle(fontSize: 16)),
                        if (me?.emailVerified != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            me!.emailVerified!
                                ? s.emailVerifiedRow
                                : s.emailNotVerifiedRow,
                            style: TextStyle(
                              fontSize: 12,
                              color: me.emailVerified!
                                  ? WbColors.oceanTeal
                                  : WbColors.warning,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (canVerify)
                    Text(
                      s.verifyEmailConfirm,
                      style: const TextStyle(
                        color: WbColors.waveCyan,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            );
          }),
          const SizedBox(height: 12),
          WbCard(
            onTap: () => context.push('/subscription'),
            child: Row(
              children: [
                const Icon(Icons.workspace_premium_outlined,
                    color: WbColors.waveCyan),
                const SizedBox(width: 12),
                Expanded(
                  child: subscription.when(
                    loading: () => Text(s.subscription),
                    error: (_, __) => Text(s.subscription),
                    data: (sub) => Text(
                      sub.isActive
                          ? '${s.subscription} · ${s.active}'
                          : s.subscription,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: WbColors.ice60),
              ],
            ),
          ),
          const SizedBox(height: 12),
          WbCard(
            onTap: () => context.push('/settings/devices'),
            child: Row(
              children: [
                const Icon(Icons.devices_outlined, color: WbColors.waveCyan),
                const SizedBox(width: 12),
                Expanded(child: Text(s.devices)),
                const Icon(Icons.chevron_right, color: WbColors.ice60),
              ],
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: () async {
                await ref.read(sessionControllerProvider.notifier).logout();
                if (context.mounted) context.go('/login');
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: WbColors.error,
                side: const BorderSide(color: WbColors.error),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(s.logOut),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
