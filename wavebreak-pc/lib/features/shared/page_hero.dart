import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session_controller.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_theme.dart';
import '../../services/vpn/connection_manager.dart';
import '../../services/vpn/live_metrics.dart';
import '../home/location_bar.dart';
import '../immersive/immersive_colors.dart';
import '../immersive/tinted_glass.dart';
import 'data_providers.dart';
import 'flag_icon.dart';
import 'traffic_format.dart';

/// Servers: the server in use, big — flag, place, protocol, state, ping —
/// and connect / disconnect right there.
class SelectedServerHero extends ConsumerWidget {
  const SelectedServerHero({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final connection = ref.watch(connectionManagerProvider);
    final m = ref.watch(liveMetricsProvider);
    final canConnect = ref.watch(canConnectProvider);
    final loc = connection.location;
    final connected = connection.status == ConnectionStatus.connected;
    final busy = connection.status == ConnectionStatus.connecting ||
        connection.status == ConnectionStatus.requestingProfile ||
        connection.status == ConnectionStatus.configPending ||
        connection.status == ConnectionStatus.disconnecting;
    final (place, _) = splitPlaceAndProtocol(loc.city);
    final title = loc.isAuto
        ? s.fastestLocation
        : (place.isNotEmpty ? place : loc.country);
    final proto = protocolLabel(loc);
    final subtitle = [
      if (!loc.isAuto && place.isNotEmpty && place != loc.country) loc.country,
      if (proto != null) proto,
    ].join(' · ');
    final ping = connected && m.active ? m.pingMs : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 84,
          height: 84,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Ic.text.withValues(alpha: 0.06),
            border: Border.all(
                color: connected ? Ic.arctic : Ic.glassBorder, width: 1.5),
          ),
          child: loc.isAuto || loc.countryCode.isEmpty
              ? const Icon(Icons.public, color: Ic.arctic, size: 40)
              : FlagIcon(countryCode: loc.countryCode, width: 48),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: Ic.text, fontSize: 26, fontWeight: FontWeight.w600),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(color: Ic.textMuted, fontSize: 14)),
        ],
        const SizedBox(height: 10),
        Text(
          connected
              ? (ping == null ? s.connected : '${s.connected} · $ping ${s.unitMs}')
              : s.notConnected,
          style: TextStyle(
            color: connected ? Ic.arctic : Ic.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        // A button-sized pill, not a full-width bar.
        SizedBox(
          width: 220,
          child: TintedGlass(
            onTap: busy
                ? null
                : () => ref
                    .read(connectionManagerProvider.notifier)
                    .toggle(subscriptionActive: canConnect),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              connected || busy ? s.coreDisconnect : s.coreConnect,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: connected ? Ic.text : context.accent,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Settings: who is signed in and what the subscription is — e-mail, plan
/// and days left, devices, traffic. Taps through to Account.
class AccountHero extends ConsumerWidget {
  const AccountHero({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final session = ref.watch(sessionControllerProvider);
    final isGuest = session.phase == SessionPhase.guest;
    final email = session.user?.email ?? '';
    final sub = ref.watch(subscriptionProvider).valueOrNull;
    final own = ref.watch(sharingProvider).valueOrNull?.own;
    final usage = ref.watch(trafficUsageProvider).valueOrNull;
    final initial = isGuest || email.isEmpty ? '?' : email[0].toUpperCase();
    final active = sub != null && sub.isActive && !sub.isExpired;
    final days = sub?.daysRemaining;

    final facts = [
      if (active)
        days == null ? sub.planName : '${sub.planName} · $days ${s.daysRemaining}',
      if (active && own?.deviceLimit != null)
        '${s.devices}: ${own!.devicesUsed} / ${own.deviceLimit}',
      if (active && usage != null)
        formatTraffic(usage.bytesTotal, usage.limitBytes ?? sub.trafficLimitBytes, s),
    ];

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/settings/account'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.accent.withValues(alpha: 0.18),
              border: Border.all(color: context.accent.withValues(alpha: 0.6)),
            ),
            child: Text(
              initial,
              style: const TextStyle(
                  color: Ic.text, fontSize: 34, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            isGuest ? s.signIn : (email.isEmpty ? s.account : email),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Ic.text, fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (isGuest)
            Text(s.signInToUnlock,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Ic.textMuted, fontSize: 14))
          else
            for (final line in facts)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(line,
                    style: const TextStyle(
                        color: Ic.textMuted,
                        fontSize: 14,
                        fontFeatures: [FontFeature.tabularFigures()])),
              ),
        ],
      ),
    );
  }
}
