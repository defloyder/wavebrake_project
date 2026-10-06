import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session_controller.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../core/theme/wb_theme.dart';
import '../shared/data_providers.dart';
import 'email_verify_sheet.dart';
import 'settings_ui.dart';

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
      return SettingsPage(
        title: s.account,
        children: [
          SettingsGroup(children: [
            SettingsRow(
              icon: Icons.person_outline_rounded,
              title: s.signInToUnlock,
            ),
          ]),
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
                backgroundColor: context.accent,
                foregroundColor: WbColors.midnight,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(s.signIn),
            ),
          ),
        ],
      );
    }

    final me = profile.asData?.value;
    final email = me?.email ?? session.user?.email ?? '—';
    // Confirming is offered only when Core reports the address
    // unconfirmed and can send the code now.
    final canVerify = me != null &&
        me.emailVerified == false &&
        me.emailVerificationAvailable;
    final verified = me?.emailVerified;

    return SettingsPage(
      title: s.account,
      children: [
        SettingsGroup(children: [
          SettingsRow(
            icon: Icons.email_outlined,
            title: email,
            subtitle: verified == null
                ? null
                : verified
                    ? s.emailVerifiedRow
                    : canVerify
                        ? '${s.emailNotVerifiedRow} · ${s.verifyEmailConfirm}'
                        : s.emailNotVerifiedRow,
            trailing: verified == null
                ? null
                : Icon(
                    verified
                        ? Icons.verified_outlined
                        : Icons.error_outline_rounded,
                    size: 20,
                    color: verified ? WbColors.oceanTeal : WbColors.warning,
                  ),
            chevron: canVerify,
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
          ),
          SettingsRow(
            icon: Icons.workspace_premium_outlined,
            title: s.subscription,
            value: subscription.asData?.value.isActive == true
                ? s.active
                : null,
            onTap: () => context.push('/subscription'),
          ),
          SettingsRow(
            icon: Icons.devices_outlined,
            title: s.devices,
            onTap: () => context.push('/settings/devices'),
          ),
        ]),
        SettingsGroup(children: [
          SettingsRow(
            icon: Icons.logout_rounded,
            title: s.logOut,
            destructive: true,
            chevron: false,
            onTap: () async {
              await ref.read(sessionControllerProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ]),
      ],
    );
  }
}
