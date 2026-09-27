import 'package:aumazing/core/services/local_db_service.dart';
import 'package:aumazing/core/config/payment_simulation_config.dart';
import 'package:aumazing/features/premium/mock_paymongo_checkout_screen.dart';
import 'package:aumazing/features/premium/profile_slot_checkout.dart';
import 'package:aumazing/features/settings/manage_children_screen.dart';
import 'package:aumazing/features/splash/auth/child_profile_setup_screen.dart';
import 'package:aumazing/services/entitlement_service.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/providers/progress_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_haptic/shared_haptic.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_auth.dart';

/// AUM-150 — the parent-facing profile list: who is on the account, who is
/// active, and switching between them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ChildProfile child(
    String id,
    String name, {
    required DateTime createdAt,
    DateTime? birthDate,
  }) =>
      ChildProfile(
        id: id,
        userId: 'user-1',
        displayName: name,
        birthDate: birthDate ?? DateTime(2020, 3, 4),
        avatar: '🐻',
        createdAt: createdAt,
        updatedAt: createdAt,
      );

  Future<ChildProvider> pumpScreen(
    WidgetTester tester,
    List<ChildProfile> children, {
    ProfileSlotCheckout? checkout,
  }) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final childProvider = ChildProvider(
      localDb: _FakeLocalDb(children),
      authService: FakeAuthService.boundAccount(),
    );
    await childProvider.loadProfile();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ChildProvider>.value(value: childProvider),
          ChangeNotifierProvider<AssessmentProvider>(
            create: (_) => AssessmentProvider(localDb: _FakeLocalDb(children)),
          ),
          ChangeNotifierProvider<ProgressProvider>(
            create: (_) => ProgressProvider(),
          ),
          Provider<AudioService>(create: (_) => _FakeAudioService()),
          Provider<HapticService>.value(value: HapticService()),
        ],
        child: MaterialApp(
          home: ManageChildrenScreen(profileSlotCheckout: checkout),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return childProvider;
  }

  testWidgets('lists every child with their age and marks the active one',
      (tester) async {
    final today = DateTime.now();
    await pumpScreen(tester, [
      child('a', 'Ana', createdAt: DateTime(2026, 1, 1),
          birthDate: DateTime(today.year - 5, 1, 2)),
      // Deliberately older than the former 2–6 limit.
      child('b', 'Bea', createdAt: DateTime(2026, 2, 1),
          birthDate: DateTime(today.year - 12, 1, 2)),
    ]);

    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Bea'), findsOneWidget);
    expect(find.textContaining('Age 5'), findsOneWidget);
    expect(find.textContaining('Age 12'), findsOneWidget);
    // Exactly one profile is presented as active.
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Tap to make active'), findsOneWidget);
    expect(find.byKey(const Key('add-child-button')), findsOneWidget);
  });

  testWidgets('tapping another child makes it the active profile',
      (tester) async {
    final provider = await pumpScreen(tester, [
      child('a', 'Ana', createdAt: DateTime(2026, 1, 1)),
      child('b', 'Bea', createdAt: DateTime(2026, 2, 1)),
    ]);
    expect(provider.activeChildId, 'a');

    await tester.tap(find.text('Bea'));
    await tester.pumpAndSettle();

    expect(provider.activeChildId, 'b');
    expect(find.text('Bea is now the active profile.'), findsOneWidget);
    // The badge moved with the selection rather than being duplicated.
    expect(find.text('Active'), findsOneWidget);
    // Past AudioService's 4s native-operation backstop from the child
    // switch's updateConfig, so no pending timer is left behind.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('deleting asks for parent verification before anything happens',
      (tester) async {
    final provider = await pumpScreen(tester, [
      child('a', 'Ana', createdAt: DateTime(2026, 1, 1)),
      child('b', 'Bea', createdAt: DateTime(2026, 2, 1)),
    ]);

    await tester.tap(find.byTooltip('Delete Bea'));
    await tester.pumpAndSettle();

    // The parent gate is up and nothing has been deleted yet.
    expect(find.byType(Dialog), findsWidgets);
    expect(find.byKey(const Key('confirm-delete-child')), findsNothing);
    expect(provider.children, hasLength(2));
  });

  group('profile allowance (AUM-343)', () {
    final entitlement = EntitlementService.instance;

    setUp(() {
      entitlement.debugSetRealPremium(false);
      entitlement.debugSetExtraProfileSlots(0);
      entitlement.clearSimulatedPurchase();
    });
    tearDown(() {
      entitlement.debugSetRealPremium(false);
      entitlement.debugSetExtraProfileSlots(0);
      PaymentSimulationConfig.debugAvailableOverride = null;
    });

    Future<void> tapAdd(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const Key('add-child-button')));
      await tester.tap(find.byKey(const Key('add-child-button')));
      await tester.pumpAndSettle();
    }

    testWidgets('says how many profiles are in use', (tester) async {
      await pumpScreen(tester, [
        child('a', 'Ana', createdAt: DateTime(2026, 1, 1)),
      ]);
      expect(find.textContaining('Profiles: 1 of 1.'), findsOneWidget);
    });

    testWidgets('a second child on the free plan asks for Premium', (
      tester,
    ) async {
      await pumpScreen(tester, [
        child('a', 'Ana', createdAt: DateTime(2026, 1, 1)),
      ]);
      await tapAdd(tester);

      expect(find.byKey(const Key('needs-premium-dialog')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('needs-premium-dialog')),
          matching: find.textContaining('₱30.00 each'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('needs-premium-dialog')), findsNothing);
    });

    testWidgets('Premium with every slot used offers one for ₱30', (
      tester,
    ) async {
      PaymentSimulationConfig.debugAvailableOverride = true;
      entitlement.debugSetRealPremium(true);
      await pumpScreen(tester, [
        child('a', 'Ana', createdAt: DateTime(2026, 1, 1)),
      ]);
      await tapAdd(tester);

      expect(find.byKey(const Key('buy-profile-dialog')), findsOneWidget);
      await tester.tap(find.text('Continue to payment'));
      await tester.pumpAndSettle();

      // The clearly-labelled simulated checkout, for the one-time price.
      final checkout = tester.widget<MockPaymongoCheckoutScreen>(
        find.byType(MockPaymongoCheckoutScreen),
      );
      expect(checkout.amountLabel, '₱30.00');
      expect(checkout.planLabel, contains('Extra child profile'));
    });

    testWidgets('a real build sells the slot through PayMongo (AUM-349)', (
      tester,
    ) async {
      PaymentSimulationConfig.debugAvailableOverride = false;
      entitlement.debugSetRealPremium(true);
      int? askedWith;
      await pumpScreen(
        tester,
        [child('a', 'Ana', createdAt: DateTime(2026, 1, 1))],
        checkout: (context, {required slotsBefore}) async {
          askedWith = slotsBefore;
          return ProfileSlotPurchase.added;
        },
      );
      await tapAdd(tester);
      await tester.tap(find.text('Continue to payment'));
      await tester.pumpAndSettle();

      expect(find.byType(MockPaymongoCheckoutScreen), findsNothing);
      // The purchase is judged against the real slots held before it.
      expect(askedWith, 0);
      // A confirmed slot goes straight on to setting up the child.
      expect(find.byType(ChildProfileSetupScreen), findsOneWidget);
      // Dispose the setup screen so its audio restore runs, then let the
      // audio backstop timers finish.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
    });

    for (final (result, message) in [
      (ProfileSlotPurchase.pending, 'Payment received'),
      (ProfileSlotPurchase.premiumRequired, 'need an active Premium'),
      (ProfileSlotPurchase.failed, 'Could not start the payment'),
    ]) {
      testWidgets('a ${result.name} purchase adds no child', (tester) async {
        PaymentSimulationConfig.debugAvailableOverride = false;
        entitlement.debugSetRealPremium(true);
        await pumpScreen(
          tester,
          [child('a', 'Ana', createdAt: DateTime(2026, 1, 1))],
          checkout: (context, {required slotsBefore}) async => result,
        );
        await tapAdd(tester);
        await tester.tap(find.text('Continue to payment'));
        await tester.pumpAndSettle();

        expect(find.byType(ChildProfileSetupScreen), findsNothing);
        expect(find.textContaining(message), findsOneWidget);
      });
    }

    testWidgets('children already on the account are never taken away', (
      tester,
    ) async {
      // Three children, free plan: all three are listed and usable; only
      // adding a fourth is gated.
      await pumpScreen(tester, [
        child('a', 'Ana', createdAt: DateTime(2026, 1, 1)),
        child('b', 'Bea', createdAt: DateTime(2026, 2, 1)),
        child('c', 'Cai', createdAt: DateTime(2026, 3, 1)),
      ]);
      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('Bea'), findsOneWidget);
      expect(find.text('Cai'), findsOneWidget);
      expect(find.textContaining('Profiles: 3 of 3.'), findsOneWidget);
    });
  });
}

class _FakeLocalDb extends LocalDbService {
  _FakeLocalDb(this._children);

  final List<ChildProfile> _children;

  @override
  Future<List<ChildProfile>> getChildren({
    String? userId,
    bool includeDeleted = false,
  }) async =>
      _children;
}

class _FakeAudioService extends AudioService {
  _FakeAudioService() : super(config: const AudioConfig());
}
