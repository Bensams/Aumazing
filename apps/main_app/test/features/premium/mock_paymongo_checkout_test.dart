import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aumazing/core/config/payment_simulation_config.dart';
import 'package:aumazing/features/premium/mock_paymongo_checkout_screen.dart';
import 'package:aumazing/services/entitlement_service.dart';

/// The simulated checkout (AUM-331) lets a demo walk the whole Premium
/// purchase without contacting PayMongo. Two properties matter more than the
/// feature itself:
///
///  * it can never reach a real family — the grant is gated at the same place
///    the screen is, so a build that cannot show the mock cannot honour its
///    result either;
///  * it never writes entitlement data — no Supabase row, no cache, nothing
///    that could outlive the process and be mistaken for a real purchase.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final entitlement = EntitlementService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PaymentSimulationConfig.debugAvailableOverride = true;
    entitlement.clearSimulatedPurchase();
    entitlement.debugSetRealPremium(false);
  });

  tearDown(() {
    PaymentSimulationConfig.debugAvailableOverride = true;
    entitlement.clearSimulatedPurchase();
    entitlement.debugSetRealPremium(false);
    PaymentSimulationConfig.debugAvailableOverride = null;
  });

  group('simulated entitlement', () {
    test('a simulated purchase unlocks every Premium gate', () {
      var notifications = 0;
      void listener() => notifications++;
      entitlement.addListener(listener);
      addTearDown(() => entitlement.removeListener(listener));

      expect(entitlement.isPremium, isFalse);

      entitlement.grantSimulatedPurchase();

      expect(entitlement.isPremium, isTrue);
      expect(entitlement.isSimulatedPurchaseActive, isTrue);
      expect(notifications, 1);
    });

    test('it cannot be granted when the simulation is not compiled in', () {
      // The release-safety property: a fake checkout must not be able to hand
      // out Premium even if something calls the grant directly.
      PaymentSimulationConfig.debugAvailableOverride = false;

      entitlement.grantSimulatedPurchase();

      expect(entitlement.isSimulatedPurchaseActive, isFalse);
      expect(entitlement.isPremium, isFalse);
    });

    test('it writes nothing that could survive a restart', () async {
      entitlement.grantSimulatedPurchase();

      expect(entitlement.isRealPremium, isFalse,
          reason: 'the genuine entitlement is untouched');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty,
          reason: 'nothing cached, so a restart drops the pretend purchase');
    });

    test('a backend refresh neither cancels nor is cancelled by it', () {
      entitlement.grantSimulatedPurchase();

      // What refresh() does when the backend says "not premium".
      entitlement.debugSetRealPremium(false);
      expect(entitlement.isPremium, isTrue);
      expect(entitlement.isSimulatedPurchaseActive, isTrue);

      // Clearing the simulation leaves a genuine entitlement standing.
      entitlement.debugSetRealPremium(true);
      entitlement.clearSimulatedPurchase();
      expect(entitlement.isPremium, isTrue);
      expect(entitlement.isRealPremium, isTrue);
    });
  });

  group('the checkout screen', () {
    /// Pushes the checkout from a navigator the test owns, so the outcome is
    /// read straight off the route's future rather than out of a callback
    /// whose completion the test would have to guess at.
    Future<MockCheckoutOutcome?> runCheckout(
      WidgetTester tester,
      String buttonText,
    ) async {
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navKey, home: const SizedBox.shrink()),
      );

      final route = navKey.currentState!.push<MockCheckoutOutcome>(
        MaterialPageRoute(builder: (_) => const MockPaymongoCheckoutScreen()),
      );
      await tester.pumpAndSettle();

      // The action buttons sit below the fold in the test viewport, and a tap
      // that lands on nothing looks exactly like a screen that never answers.
      final button = find.text(buttonText);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();

      await tester.tap(button);
      // Fixed pumps, not pumpAndSettle: paying puts a spinner on the button
      // for the deliberate "processing" beat, and a spinner never settles —
      // pumpAndSettle would sit there until its own timeout fired.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      return route;
    }

    testWidgets('says it is a simulation before anything can be tapped',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: MockPaymongoCheckoutScreen()),
      );

      expect(
        find.textContaining('SIMULATION'),
        findsOneWidget,
        reason: 'a convincing payment screen that does something else is the '
            'shape of a scam; this one must never stop saying what it is',
      );
      expect(find.textContaining('nothing is charged'), findsOneWidget);
    });

    testWidgets('collects no payment details at all', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: MockPaymongoCheckoutScreen()),
      );

      expect(find.byType(TextField), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
    });

    testWidgets('a successful simulation reports paid', (tester) async {
      expect(await runCheckout(tester, 'Simulate successful payment'),
          MockCheckoutOutcome.paid);
    });

    testWidgets('a declined simulation reports declined', (tester) async {
      expect(await runCheckout(tester, 'Simulate declined payment'),
          MockCheckoutOutcome.declined);
    });

    testWidgets('cancelling reports cancelled and grants nothing',
        (tester) async {
      expect(await runCheckout(tester, 'Cancel'), MockCheckoutOutcome.cancelled);
      expect(entitlement.isPremium, isFalse);
    });
  });
}
