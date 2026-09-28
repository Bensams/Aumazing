import 'package:intl/intl.dart';

import '../../core/config/premium_access_config.dart';
import '../../services/entitlement_service.dart';

/// Which plan the account is on, as a parent should read it (AUM-169).
enum PremiumPlanKind {
  /// Never bought Premium, or bought it with no end recorded and lost it.
  free,

  /// Paid Premium with time left.
  active,

  /// Paid Premium in its last [PremiumPlan.reminderWindow].
  endingSoon,

  /// A paid period that has run out (or was refunded).
  ended,

  /// A build that unlocks every feature for everyone.
  unlocked,

  /// Premium from the simulated checkout, gone when the app closes.
  simulated,

  /// Premium forced on by the developer override.
  developer,
}

/// The account's plan at one moment: its kind, when paid Premium ends or
/// ended, and how many extra child profiles were bought.
///
/// Premium is a one-time payment for 30 days. Nothing renews by itself, so
/// there is no subscription to cancel: paying again adds 30 days on top of
/// whatever is left.
class PremiumPlan {
  const PremiumPlan({
    required this.kind,
    this.until,
    this.extraProfiles = 0,
    this.unlimitedProfiles = false,
    this.now,
  });

  /// Reads the plan from [entitlement] as of [now].
  factory PremiumPlan.of(EntitlementService entitlement, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final until = entitlement.premiumUntil;
    final PremiumPlanKind kind;
    if (PremiumAccessConfig.unlockedForEveryone) {
      kind = PremiumPlanKind.unlocked;
    } else if (entitlement.isRealPremium) {
      kind = until != null && until.difference(at) <= reminderWindow
          ? PremiumPlanKind.endingSoon
          : PremiumPlanKind.active;
    } else if (entitlement.isDeveloperPremiumOverrideActive) {
      kind = PremiumPlanKind.developer;
    } else if (entitlement.isSimulatedPurchaseActive) {
      kind = PremiumPlanKind.simulated;
    } else if (until != null && !until.isAfter(at)) {
      kind = PremiumPlanKind.ended;
    } else {
      kind = PremiumPlanKind.free;
    }
    return PremiumPlan(
      kind: kind,
      until: until,
      extraProfiles: entitlement.extraProfileSlots,
      unlimitedProfiles: entitlement.unlimitedProfiles,
      now: at,
    );
  }

  /// How close to the end the dashboard starts reminding the parent.
  static const reminderWindow = Duration(days: 3);

  final PremiumPlanKind kind;

  /// When paid Premium ends ([PremiumPlanKind.active],
  /// [PremiumPlanKind.endingSoon]) or ended ([PremiumPlanKind.ended]).
  final DateTime? until;

  /// Extra child profiles on top of the free one.
  final int extraProfiles;

  /// Whether this build or session sets no profile limit.
  final bool unlimitedProfiles;

  final DateTime? now;

  /// Paid Premium that is still running: paying now extends it rather than
  /// starting a new period.
  bool get isPaidActive =>
      kind == PremiumPlanKind.active || kind == PremiumPlanKind.endingSoon;

  /// "28 Oct 2026, 3:15 PM" in the device's time zone.
  static String formatDate(DateTime at) =>
      DateFormat('d MMM yyyy, h:mm a').format(at.toLocal());

  /// Time left, whole days rounded down: "12 days left", "1 day left",
  /// "Less than a day left". Null when there is no end date.
  String? get timeLeft {
    final end = until;
    if (end == null || !isPaidActive) return null;
    final left = end.difference(now ?? DateTime.now());
    final days = left.inHours ~/ 24;
    if (days < 1) return 'Less than a day left';
    return days == 1 ? '1 day left' : '$days days left';
  }

  /// One line for the Settings tile.
  String get summary => switch (kind) {
    PremiumPlanKind.active ||
    PremiumPlanKind.endingSoon => until == null
        ? 'Premium'
        : 'Premium until ${formatDate(until!)}',
    PremiumPlanKind.ended => 'Free plan · Premium ended ${formatDate(until!)}',
    PremiumPlanKind.free => 'Free plan',
    PremiumPlanKind.unlocked => 'Every feature unlocked in this edition',
    PremiumPlanKind.simulated => 'Premium (simulated, ends when the app closes)',
    PremiumPlanKind.developer => 'Premium (developer override)',
  };
}
