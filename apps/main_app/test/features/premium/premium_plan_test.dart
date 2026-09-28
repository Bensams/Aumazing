import 'package:aumazing/core/config/payment_simulation_config.dart';
import 'package:aumazing/features/premium/premium_plan.dart';
import 'package:aumazing/services/entitlement_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// AUM-169 — the plan a parent sees: active with an end date, ending soon,
/// ended, or free. Premium is a one-time 30-day payment, so there is no
/// subscription state to cancel.
void main() {
  final entitlement = EntitlementService.instance;
  final now = DateTime(2026, 9, 28, 12);

  tearDown(() {
    entitlement.debugSetRealPremium(false);
    entitlement.debugSetExtraProfileSlots(0);
    entitlement.clearSimulatedPurchase();
    PaymentSimulationConfig.debugAvailableOverride = null;
  });

  PremiumPlan planWith({bool premium = true, DateTime? until}) {
    entitlement.debugSetRealPremium(premium, until: until);
    return PremiumPlan.of(entitlement, now: now);
  }

  test('a running period is active, with whole days left', () {
    final plan = planWith(until: now.add(const Duration(days: 12, hours: 5)));
    expect(plan.kind, PremiumPlanKind.active);
    expect(plan.isPaidActive, isTrue);
    expect(plan.timeLeft, '12 days left');
    expect(plan.summary, startsWith('Premium until '));
  });

  test('the last three days are ending soon', () {
    final plan = planWith(until: now.add(const Duration(days: 2, hours: 3)));
    expect(plan.kind, PremiumPlanKind.endingSoon);
    expect(plan.isPaidActive, isTrue);
    expect(plan.timeLeft, '2 days left');
  });

  test('under a day left says so rather than "0 days"', () {
    final plan = planWith(until: now.add(const Duration(hours: 5)));
    expect(plan.kind, PremiumPlanKind.endingSoon);
    expect(plan.timeLeft, 'Less than a day left');
  });

  test('a period that ran out is ended, with its end date', () {
    final end = now.subtract(const Duration(days: 1));
    final plan = planWith(until: end);
    expect(plan.kind, PremiumPlanKind.ended);
    expect(plan.isPaidActive, isFalse);
    expect(plan.until, end);
    expect(plan.timeLeft, isNull);
    expect(plan.summary, startsWith('Free plan · Premium ended '));
  });

  test('a refund ends Premium on the refund date', () {
    // The payment webhook clears is_premium and sets expires_at to the
    // refund time.
    final plan = planWith(
      premium: false,
      until: now.subtract(const Duration(hours: 1)),
    );
    expect(plan.kind, PremiumPlanKind.ended);
  });

  test('no Premium ever is the free plan', () {
    final plan = planWith(premium: false);
    expect(plan.kind, PremiumPlanKind.free);
    expect(plan.summary, 'Free plan');
  });

  test('Premium with no end date stays active', () {
    final plan = planWith();
    expect(plan.kind, PremiumPlanKind.active);
    expect(plan.timeLeft, isNull);
    expect(plan.summary, 'Premium');
  });

  test('a simulated purchase is never shown as paid Premium', () {
    PaymentSimulationConfig.debugAvailableOverride = true;
    entitlement.grantSimulatedPurchase();
    final plan = PremiumPlan.of(entitlement, now: now);
    expect(plan.kind, PremiumPlanKind.simulated);
    expect(plan.isPaidActive, isFalse);
  });

  test('carries the extra child profiles bought', () {
    entitlement.debugSetExtraProfileSlots(2);
    expect(PremiumPlan.of(entitlement, now: now).extraProfiles, 2);
  });
}
