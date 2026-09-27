import 'package:aumazing/services/entitlement_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// AUM-349 — each Premium payment buys 30 days; the app honours the end of
/// the period (entitlements.expires_at), including offline from the cache.
void main() {
  final entitlement = EntitlementService.instance;
  tearDown(() => entitlement.debugSetRealPremium(false));

  test('a running period counts as Premium', () {
    entitlement.debugSetRealPremium(
      true,
      until: DateTime.now().add(const Duration(days: 12)),
    );
    expect(entitlement.isRealPremium, isTrue);
    expect(entitlement.isPremium, isTrue);
  });

  test('an ended period no longer counts, though the flag is still set', () {
    entitlement.debugSetRealPremium(
      true,
      until: DateTime.now().subtract(const Duration(minutes: 1)),
    );
    expect(entitlement.isRealPremium, isFalse);
    expect(entitlement.isPremium, isFalse);
  });

  test('an entitlement with no end date stays active', () {
    entitlement.debugSetRealPremium(true);
    expect(entitlement.isRealPremium, isTrue);
  });
}
