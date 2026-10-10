/// What an administrator can do about one account's Premium (AUM-357), read
/// from a `get_admin_users` row.
///
/// Premium can be granted only to bound accounts: a guest has no
/// recoverable identity, so Premium given to one is lost with the device.
/// Only given Premium (an administrator grant or the free month) can be
/// ended here; paid Premium is ended by refunding it through PayMongo. The
/// server enforces both rules too.
library;

import 'package:intl/intl.dart';

/// How long a grant runs, in days, as offered in the grant dialog.
const kPremiumGrantDays = [30, 60, 90];

class PremiumAdminStatus {
  const PremiumAdminStatus({
    required this.isGuest,
    required this.isActive,
    this.until,
    this.source,
  });

  factory PremiumAdminStatus.fromRow(Map<String, dynamic> row) =>
      PremiumAdminStatus(
        isGuest: row['is_anonymous'] == true,
        isActive: row['is_premium'] == true,
        until: DateTime.tryParse(row['premium_until'] as String? ?? ''),
        source: row['premium_source'] as String?,
      );

  final bool isGuest;
  final bool isActive;
  final DateTime? until;
  final String? source;

  bool get canGrant => !isGuest;

  /// Why Grant Premium is unavailable, or null when it is available.
  String? get grantBlockedReason =>
      isGuest
          ? 'Ask the parent to link this guest account first, then grant '
              'Premium.'
          : null;

  bool get canEnd =>
      isActive && (source == 'admin_grant' || source == 'free_month');

  /// "free month", "granted" or "paid", for the subtitle.
  String get sourceLabel => switch (source) {
    'free_month' => 'free month',
    'admin_grant' => 'granted',
    'admin_revoke' => 'ended by an administrator',
    null => 'unknown',
    _ => 'paid',
  };

  /// "Premium until Nov 10, 2026 · free month", "Premium ended Oct 1,
  /// 2026 · paid", or null when the account never had Premium.
  String? describe() {
    final end = until;
    if (end == null) return isActive ? 'Premium · $sourceLabel' : null;
    final date = DateFormat('MMM d, y').format(end.toLocal());
    if (isActive) return 'Premium until $date · $sourceLabel';
    if (source == 'admin_revoke') {
      return 'Premium ended $date by an administrator';
    }
    return 'Premium ended $date · $sourceLabel';
  }
}
