import 'dart:async';

import 'package:aumazing/features/premium/web_checkout_return.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The web app's return from a PayMongo checkout: only a checkout this
/// browser started is reported, once, and a successful one waits for the
/// backend to confirm Premium before saying so.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WebCheckoutReturn.debugOutcome = null;
  });

  group('takeOutcome', () {
    test('reports a return to a checkout this browser started', () async {
      await WebCheckoutReturn.markStarted();
      WebCheckoutReturn.debugOutcome = 'success';
      final result = (await WebCheckoutReturn.takeOutcome())!;
      expect(result.paid, isTrue);
      expect(result.profileSlot, isFalse);
      // Once only.
      expect(await WebCheckoutReturn.takeOutcome(), isNull);
    });

    test('ignores ?payment= without a checkout started here', () async {
      WebCheckoutReturn.debugOutcome = 'success';
      expect(await WebCheckoutReturn.takeOutcome(), isNull);
    });

    test('ignores a checkout started long ago', () async {
      await WebCheckoutReturn.markStarted();
      WebCheckoutReturn.debugOutcome = 'success';
      expect(
        await WebCheckoutReturn.takeOutcome(
          now: DateTime.now().add(const Duration(hours: 3)),
        ),
        isNull,
      );
    });

    test('remembers an extra-profile checkout and its slot count', () async {
      await WebCheckoutReturn.markStarted(product: 'profile_slot', slotsBefore: 2);
      WebCheckoutReturn.debugOutcome = 'cancelled';
      final result = (await WebCheckoutReturn.takeOutcome())!;
      expect(result.paid, isFalse);
      expect(result.profileSlot, isTrue);
      expect(result.slotsBefore, 2);
    });

    test('ignores unknown outcomes', () async {
      await WebCheckoutReturn.markStarted();
      WebCheckoutReturn.debugOutcome = 'maybe';
      expect(await WebCheckoutReturn.takeOutcome(), isNull);
    });
  });

  group('WebCheckoutReturnBanner', () {
    Widget app(
      Future<bool> Function() wait, {
      Future<bool> Function(int above)? waitForSlot,
    }) => MaterialApp(
      home: WebCheckoutReturnBanner(
        waitForActivation: wait,
        waitForProfileSlot: waitForSlot,
        child: const Scaffold(body: Text('home')),
      ),
    );

    testWidgets('shows nothing without a checkout return', (tester) async {
      await tester.pumpWidget(app(() async => true));
      await tester.pump();
      expect(find.byKey(const Key('web-checkout-return-banner')), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('confirms Premium once the backend activates it', (
      tester,
    ) async {
      await tester.runAsync(WebCheckoutReturn.markStarted);
      WebCheckoutReturn.debugOutcome = 'success';
      final activation = Completer<bool>();
      await tester.pumpWidget(app(() => activation.future));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(find.text('Finishing your upgrade…'), findsOneWidget);

      activation.complete(true);
      await tester.pump();
      await tester.pump();
      expect(find.text('Welcome to Premium! 🎉'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pump();
      expect(find.byKey(const Key('web-checkout-return-banner')), findsNothing);
    });

    testWidgets('says activation is on its way when it is slow', (
      tester,
    ) async {
      await tester.runAsync(WebCheckoutReturn.markStarted);
      WebCheckoutReturn.debugOutcome = 'success';
      await tester.pumpWidget(app(() async => false));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      await tester.pump();
      expect(find.text('Payment received'), findsOneWidget);
    });

    testWidgets('an extra profile waits for the slot, not for Premium', (
      tester,
    ) async {
      await tester.runAsync(
        () => WebCheckoutReturn.markStarted(product: 'profile_slot', slotsBefore: 1),
      );
      WebCheckoutReturn.debugOutcome = 'success';
      int? above;
      await tester.pumpWidget(
        app(
          () async => fail('must not wait for Premium'),
          waitForSlot: (value) async {
            above = value;
            return true;
          },
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      await tester.pump();
      expect(above, 1);
      expect(find.text('Extra child profile added 🎉'), findsOneWidget);
    });

    testWidgets('reports a cancelled payment, then hides by itself', (
      tester,
    ) async {
      await tester.runAsync(WebCheckoutReturn.markStarted);
      WebCheckoutReturn.debugOutcome = 'cancelled';
      await tester.pumpWidget(app(() async => true));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(find.text('Payment cancelled'), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      expect(find.text('Payment cancelled'), findsNothing);
    });
  });
}
