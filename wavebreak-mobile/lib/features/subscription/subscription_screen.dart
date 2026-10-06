import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors/app_exception.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../core/theme/wb_theme.dart';
import '../../services/analytics/analytics.dart';
import '../../services/core_api/models.dart';
import '../../services/providers.dart';
import '../settings/settings_ui.dart';
import '../shared/data_providers.dart';
import '../shared/subscription_texts.dart';
import '../shared/traffic_format.dart';
import '../shared/traffic_wave_bar.dart';
import 'plan_purchase.dart';

/// Subscription (P9): the current subscription, the plans from Core with
/// their offers, and a promo code field. Choosing a plan goes through
/// [PlanPurchase] — today that's "contact the administration", never an
/// activation by itself.
class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  final _promoField = TextEditingController();
  PromoCheck? _promo;
  String? _promoError;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    const Analytics().event('subscription_screen_open');
  }

  @override
  void dispose() {
    _promoField.dispose();
    super.dispose();
  }

  Future<void> _applyPromo() async {
    final code = _promoField.text.trim();
    if (code.isEmpty || _checking) return;
    final s = ref.read(stringsProvider);
    FocusScope.of(context).unfocus();
    setState(() {
      _checking = true;
      _promoError = null;
    });
    try {
      final promo = await ref.read(coreGatewayProvider).checkPromoCode(code);
      if (mounted) setState(() => _promo = promo);
    } on AppException catch (e) {
      if (mounted) setState(() => _promoError = e.localized(s));
    } catch (_) {
      if (mounted) setState(() => _promoError = s.errUnavailable);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _removePromo() => setState(() {
        _promo = null;
        _promoError = null;
        _promoField.clear();
      });

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final asyncSub = ref.watch(subscriptionProvider);
    return SettingsPage(
      title: s.subscription,
      fallback: '/home',
      children: [
        ...asyncSub.when(
          loading: () => const [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
          // 404 = simply no subscription yet: the plans below are the way in.
          error: (error, _) => error is AppException && error.statusCode == 404
              ? const <Widget>[]
              : [
                  SettingsFooter(error is AppException
                      ? error.localized(s)
                      : s.errUnavailable),
                  const SizedBox(height: 16),
                ],
          data: (sub) => [_CurrentSubscription(sub: sub, s: s)],
        ),
        _PlansGroup(s: s, promo: _promo),
        SettingsGroup(
          title: s.promoCodeHint,
          footer: _promoError,
          children: [
            SettingsBlock(
              child: _promo == null
                  ? _PromoInput(
                      controller: _promoField,
                      checking: _checking,
                      s: s,
                      onApply: _applyPromo,
                    )
                  : _PromoApplied(promo: _promo!, s: s, onRemove: _removePromo),
            ),
          ],
        ),
      ],
    );
  }
}

class _CurrentSubscription extends ConsumerWidget {
  const _CurrentSubscription({required this.sub, required this.s});

  final SubscriptionInfo sub;
  final AppStrings s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(trafficUsageProvider).valueOrNull;
    final devicesUsed = ref.watch(devicesProvider).valueOrNull?.length;
    final until = sub.expiresAt == null
        ? '—'
        : DateFormat('d MMMM y').format(sub.expiresAt!);
    final devices = (devicesUsed != null && sub.deviceLimit != null)
        ? '$devicesUsed / ${sub.deviceLimit}'
        : '—';
    return SettingsGroup(
      title: sub.planName,
      footer: sub.isPastDue
          ? '${renewBeforeLine(sub, s)}\n${s.renewResetNote}'
          : null,
      children: [
        SettingsRow(
          icon: Icons.workspace_premium_outlined,
          title: subscriptionStatusLabel(sub, s),
          trailing: Icon(
            sub.isActive ? Icons.check_circle_outline : Icons.error_outline,
            size: 20,
            color: sub.isActive ? WbColors.oceanTeal : WbColors.warning,
          ),
        ),
        SettingsRow(
            icon: Icons.event_outlined, title: s.until, value: until),
        SettingsRow(
            icon: Icons.devices_outlined, title: s.devices, value: devices),
        if (usage != null)
          SettingsBlock(
            title: s.traffic,
            child: TrafficWaveBar(
              usedBytes: usage.bytesTotal,
              limitBytes: usage.limitBytes ?? sub.trafficLimitBytes,
              s: s,
            ),
          ),
        // A billing portal when Core provides one.
        if (sub.manageUrl != null)
          SettingsRow(
            icon: Icons.open_in_new_rounded,
            title: s.manageSubscription,
            onTap: () => launchUrl(Uri.parse(sub.manageUrl!)),
          ),
      ],
    );
  }
}

class _PlansGroup extends ConsumerWidget {
  const _PlansGroup({required this.s, required this.promo});

  final AppStrings s;
  final PromoCheck? promo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncPlans = ref.watch(plansProvider);
    return asyncPlans.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => SettingsFooter(
          error is AppException ? error.localized(s) : s.errUnavailable),
      data: (plans) {
        final visible = plans.where((p) => p.isPublic && p.isActive).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        if (visible.isEmpty) return const SizedBox.shrink();
        return SettingsGroup(
          title: s.choosePlan,
          footer: s.selectPlanHint,
          children: [
            for (final plan in visible)
              _PlanTile(
                plan: plan,
                promoPrice: promo?.prices[plan.id],
                s: s,
                onTap: () => ref
                    .read(planPurchaseProvider)
                    .purchase(context, plan, promo: promo),
              ),
          ],
        );
      },
    );
  }
}

/// One plan: name with its offer label, what it includes, and the price —
/// the old price struck through when there's an offer or a promo code.
class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.plan,
    required this.promoPrice,
    required this.s,
    required this.onTap,
  });

  final Plan plan;
  final int? promoPrice;
  final AppStrings s;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final price = promoPrice ?? plan.priceMinor;
    final was = promoPrice != null && promoPrice! < plan.priceMinor
        ? plan.priceMinor
        : (plan.originalPriceMinor != null &&
                plan.originalPriceMinor! > plan.priceMinor
            ? plan.originalPriceMinor
            : null);
    final traffic = plan.trafficLimitBytes == null
        ? s.trafficUnlimited
        : formatBytes(plan.trafficLimitBytes!, s);
    final includes = [
      if (plan.deviceLimit != null)
        s.planDevicesLine.replaceAll('{n}', '${plan.deviceLimit}'),
      if (plan.durationDays != null)
        s.planDaysLine.replaceAll('{n}', '${plan.durationDays}'),
      traffic,
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(plan.name,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      if (plan.badge.isNotEmpty) _Badge(plan.badge),
                    ],
                  ),
                  if (plan.description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(plan.description,
                        style: const TextStyle(
                            fontSize: 13, color: WbColors.ice60, height: 1.3)),
                  ],
                  const SizedBox(height: 4),
                  Text(includes,
                      style: const TextStyle(
                          fontSize: 12.5, color: WbColors.muted, height: 1.3)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (was != null)
                  Text(
                    formatMoney(was, plan.currency),
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: WbColors.muted,
                      decoration: TextDecoration.lineThrough,
                      decorationColor: WbColors.muted,
                    ),
                  ),
                Text(
                  formatMoney(price, plan.currency),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700),
                ),
                Text(
                  plan.interval == 'year' ? s.planPerYear : s.planPerMonth,
                  style: const TextStyle(fontSize: 12, color: WbColors.muted),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.chevron_right_rounded,
                  color: WbColors.ice60, size: 22),
            ),
          ],
        ),
      ),
    );
  }
}

/// The offer label of a plan ("-17%") — accent, it is an active state.
class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: context.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.accent.withValues(alpha: 0.45)),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: context.accent)),
    );
  }
}

class _PromoInput extends StatelessWidget {
  const _PromoInput({
    required this.controller,
    required this.checking,
    required this.s,
    required this.onApply,
  });

  final TextEditingController controller;
  final bool checking;
  final AppStrings s;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onApply(),
            decoration: InputDecoration(
              hintText: s.promoCodeHint,
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 46,
          child: FilledButton(
            onPressed: checking ? null : onApply,
            style: FilledButton.styleFrom(
              backgroundColor: context.accent,
              foregroundColor: WbColors.midnight,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(s.promoApply),
          ),
        ),
      ],
    );
  }
}

class _PromoApplied extends StatelessWidget {
  const _PromoApplied({
    required this.promo,
    required this.s,
    required this.onRemove,
  });

  final PromoCheck promo;
  final AppStrings s;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final discount = promo.isPercent
        ? '−${promo.discountValue}%'
        : '−${formatMoney(promo.discountValue, promo.currency ?? '')}';
    return Row(
      children: [
        const Icon(Icons.local_offer_outlined,
            size: 20, color: WbColors.oceanTeal),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.promoAppliedLine
                    .replaceAll('{code}', promo.code)
                    .replaceAll('{discount}', discount),
                style: const TextStyle(fontSize: 15),
              ),
              if (promo.description.isNotEmpty)
                Text(promo.description,
                    style:
                        const TextStyle(fontSize: 12.5, color: WbColors.muted)),
            ],
          ),
        ),
        TextButton(onPressed: onRemove, child: Text(s.promoRemove)),
      ],
    );
  }
}

/// "499 ₽", "4.99 $": whole amounts without decimals.
String formatMoney(int minor, String currency) {
  const symbols = {'USD': '\$', 'EUR': '€', 'RUB': '₽', 'TRY': '₺'};
  final amount = minor % 100 == 0
      ? '${minor ~/ 100}'
      : (minor / 100).toStringAsFixed(2);
  final symbol = symbols[currency.toUpperCase()] ?? currency;
  return symbol.isEmpty ? amount : '$amount $symbol';
}
