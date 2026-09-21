import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors/app_exception.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/analytics/analytics.dart';
import '../../services/core_api/models.dart';
import '../../services/providers.dart';
import '../shared/data_providers.dart';
import '../shared/detail_scaffold.dart';
import '../shared/nav_utils.dart';
import '../shared/traffic_wave_bar.dart';
import '../shared/wb_card.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  String? _activatingPlanId;
  bool _changingPlan = false;

  Future<void> _activate(Plan plan) async {
    setState(() => _activatingPlanId = plan.id);
    try {
      await ref.read(coreGatewayProvider).createSubscription(plan.id);
      ref.invalidate(subscriptionProvider);
      if (mounted) setState(() => _changingPlan = false);
    } on AppException catch (error) {
      if (mounted) {
        final s = ref.read(stringsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.localized(s))),
        );
      }
    } finally {
      if (mounted) setState(() => _activatingPlanId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Analytics().event('subscription_screen_open');
    final asyncSub = ref.watch(subscriptionProvider);
    final asyncDevices = ref.watch(devicesProvider);
    final usage = ref.watch(trafficUsageProvider).asData?.value;
    final s = ref.watch(stringsProvider);

    return DetailScaffold(
      title: s.subscription,
      onBack: () => safePop(context, fallback: '/home'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
                asyncSub.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, _) {
                    // Core returns 404 when the user simply has no active
                    // subscription yet — that's not a failure, it's the
                    // entry point into "pick a plan" (POST /v1/subscriptions).
                    final noActiveSubscription =
                        error is AppException && error.statusCode == 404;
                    if (noActiveSubscription) {
                      return _PlanPicker(
                        s: s,
                        activatingPlanId: _activatingPlanId,
                        onSelect: _activate,
                      );
                    }
                    return Text(
                      error is AppException ? error.localized(s) : s.errUnavailable,
                    );
                  },
                  data: (sub) {
                    final until = sub.expiresAt == null
                        ? '—'
                        : DateFormat('d MMMM y').format(sub.expiresAt!);
                    final devicesUsed = asyncDevices.asData?.value.length;
                    final devices = (devicesUsed != null && sub.deviceLimit != null)
                        ? '$devicesUsed / ${sub.deviceLimit}'
                        : '—';
                    if (_changingPlan) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextButton.icon(
                            onPressed: () => setState(() => _changingPlan = false),
                            icon: const Icon(Icons.arrow_back_rounded, size: 18),
                            label: Text(sub.planName),
                          ),
                          const SizedBox(height: 8),
                          _PlanPicker(
                            s: s,
                            activatingPlanId: _activatingPlanId,
                            onSelect: _activate,
                          ),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        WbCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sub.planName,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                sub.isActive ? s.active : sub.status,
                                style: TextStyle(
                                  color: sub.isActive
                                      ? WbColors.oceanTeal
                                      : WbColors.warning,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                s.until,
                                style: const TextStyle(color: WbColors.ice60),
                              ),
                              Text(until),
                              const SizedBox(height: 12),
                              Text(
                                s.devices,
                                style: const TextStyle(color: WbColors.ice60),
                              ),
                              Text(devices),
                              if (usage != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  s.traffic,
                                  style: const TextStyle(color: WbColors.ice60),
                                ),
                                const SizedBox(height: 8),
                                TrafficWaveBar(
                                  usedBytes: usage.bytesTotal,
                                  limitBytes: usage.limitBytes ?? sub.trafficLimitBytes,
                                  s: s,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            // A real billing portal URL is used when Core
                            // provides one; otherwise "manage" means
                            // switching plans in-app, which is always
                            // possible — never a dead disabled button.
                            onPressed: sub.manageUrl != null
                                ? () => launchUrl(Uri.parse(sub.manageUrl!))
                                : () => setState(() => _changingPlan = true),
                            style: FilledButton.styleFrom(
                              backgroundColor: WbColors.waveCyan,
                              foregroundColor: WbColors.midnight,
                            ),
                            child: Text(s.manageSubscription),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ],
      ),
    );
  }
}

class _PlanPicker extends ConsumerWidget {
  const _PlanPicker({
    required this.s,
    required this.activatingPlanId,
    required this.onSelect,
  });

  final AppStrings s;
  final String? activatingPlanId;
  final ValueChanged<Plan> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncPlans = ref.watch(plansProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.selectPlanHint,
          style: const TextStyle(color: WbColors.ice60),
        ),
        const SizedBox(height: 16),
        asyncPlans.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text(
            error is AppException ? error.localized(s) : s.errUnavailable,
          ),
          data: (plans) {
            final visible = plans.where((p) => p.isPublic && p.isActive).toList()
              ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
            if (visible.isEmpty) {
              return Text(s.errUnavailable);
            }
            return Column(
              children: [
                for (final plan in visible) ...[
                  _PlanCard(
                    plan: plan,
                    activating: activatingPlanId == plan.id,
                    onTap: activatingPlanId == null ? () => onSelect(plan) : null,
                    s: s,
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.activating,
    required this.onTap,
    required this.s,
  });

  final Plan plan;
  final bool activating;
  final VoidCallback? onTap;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    return WbCard(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  '${plan.priceMajor.toStringAsFixed(2)} ${plan.currency} / ${plan.interval}',
                  style: const TextStyle(color: WbColors.ice60, fontSize: 13),
                ),
              ],
            ),
          ),
          if (activating)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Text(
              s.choosePlan,
              style: const TextStyle(color: WbColors.waveCyan, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}
