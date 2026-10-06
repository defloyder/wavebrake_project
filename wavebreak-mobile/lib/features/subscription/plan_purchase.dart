import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../core/theme/wb_theme.dart';
import '../../services/core_api/models.dart';

/// How a chosen plan gets paid for (P9). Choosing a plan never grants it
/// by itself: a payment step does. There is no payment system yet, so
/// the one implementation sends the user to the administration
/// ([ContactAdministrationPurchase]); a payment provider later implements
/// this same interface and the plan screen stays as it is.
abstract class PlanPurchase {
  const PlanPurchase();

  /// Starts buying [plan], with [promo] when the user applied a code.
  Future<void> purchase(BuildContext context, Plan plan, {PromoCheck? promo});
}

final planPurchaseProvider =
    Provider<PlanPurchase>((ref) => ContactAdministrationPurchase(ref));

/// No payment yet: "To get access, contact the administration", with a
/// way to Support.
class ContactAdministrationPurchase extends PlanPurchase {
  const ContactAdministrationPurchase(this._ref);

  final Ref _ref;

  @override
  Future<void> purchase(BuildContext context, Plan plan,
      {PromoCheck? promo}) async {
    final s = _ref.read(stringsProvider);
    final toSupport = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(plan.name,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        content: Text(
          s.planContactAdmin,
          style: const TextStyle(height: 1.45, color: WbColors.ice),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.close),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: dialogContext.accent,
              foregroundColor: WbColors.midnight,
            ),
            child: Text(s.planContactSupport),
          ),
        ],
      ),
    );
    if (toSupport == true && context.mounted) {
      await context.push('/settings/support');
    }
  }
}
