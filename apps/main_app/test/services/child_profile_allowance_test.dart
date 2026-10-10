import 'package:aumazing/services/child_profile_allowance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AUM-343 — one child profile is free; more need Premium and a bought slot;
/// nothing already on the account is ever taken away.
void main() {
  AddChildGate gate({
    required int existing,
    int baseline = 1,
    bool premium = false,
    int slots = 0,
    bool unlimited = false,
  }) => ChildProfileAllowance.gate(
    existing: existing,
    baseline: baseline,
    isPremium: premium,
    extraSlots: slots,
    unlimited: unlimited,
  );

  group('gate', () {
    test('the first child is always free', () {
      expect(gate(existing: 0), AddChildGate.allowed);
    });

    test('a second child on the free plan needs Premium', () {
      expect(gate(existing: 1), AddChildGate.needsPremium);
    });

    test('Premium without a spare slot needs one bought', () {
      expect(gate(existing: 1, premium: true), AddChildGate.needsSlot);
    });

    test('each bought slot allows one more child', () {
      expect(gate(existing: 1, premium: true, slots: 1), AddChildGate.allowed);
      expect(gate(existing: 2, premium: true, slots: 1), AddChildGate.needsSlot);
      expect(gate(existing: 2, premium: true, slots: 2), AddChildGate.allowed);
    });

    test('slots are Premium-only: a lapsed plan cannot use them', () {
      expect(gate(existing: 1, slots: 3), AddChildGate.needsPremium);
    });

    test('a grandfathered family needs one slot for one more child', () {
      // Already had three children when the limit arrived.
      expect(gate(existing: 3, baseline: 3, premium: true),
          AddChildGate.needsSlot);
      expect(gate(existing: 3, baseline: 3, premium: true, slots: 1),
          AddChildGate.allowed);
    });

    test('a grandfathered family that removed a child can add it back', () {
      expect(gate(existing: 2, baseline: 3), AddChildGate.allowed);
    });

    test('an unlimited build is never gated', () {
      expect(gate(existing: 9, unlimited: true), AddChildGate.allowed);
    });
  });

  group('baseline', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('is the free profile for a new account', () async {
      expect(
        await ChildProfileAllowance.instance.baselineFor('u1', existing: 1),
        1,
      );
    });

    test('grandfathers the children an account already has', () async {
      expect(
        await ChildProfileAllowance.instance.baselineFor('u2', existing: 3),
        3,
      );
    });

    test('is recorded once and does not grow with later children', () async {
      await ChildProfileAllowance.instance.baselineFor('u3', existing: 1);
      expect(
        await ChildProfileAllowance.instance.baselineFor('u3', existing: 4),
        1,
        reason: 'children added later came from bought slots',
      );
    });
  });

  test('allowance counts slots only on Premium', () {
    expect(
      ChildProfileAllowance.allowance(
        baseline: 1,
        isPremium: true,
        extraSlots: 2,
      ),
      3,
    );
    expect(
      ChildProfileAllowance.allowance(
        baseline: 1,
        isPremium: false,
        extraSlots: 2,
      ),
      1,
    );
  });
}
