import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/premium/premium_upgrade_screen.dart';
import 'package:aumazing/features/settings/your_plan_screen.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/services/entitlement_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// AUM-169 — Settings › Your Plan: where a parent sees when Premium ends,
/// learns there is nothing to cancel, and renews.
void main() {
  final entitlement = EntitlementService.instance;
  final auth = AuthService(supabaseAuth: _FakeSupabaseAuthClient());

  tearDown(() {
    entitlement.debugSetRealPremium(false);
    entitlement.debugSetExtraProfileSlots(0);
  });

  Future<int> pumpPlan(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var refreshes = 0;
    final children = _TestChildProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider<ChildProvider>.value(
        value: children,
        child: MaterialApp(
          theme: AppTheme.light,
          home: YourPlanScreen(
            palette: children.activePalette,
            authService: auth,
            refresh: () async => refreshes++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return refreshes;
  }

  String cardText(WidgetTester tester, String key) => tester
      .widgetList<Text>(
        find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(Text),
        ),
      )
      .map((t) => t.data)
      .join(' ');

  testWidgets('active Premium shows its end date and time left', (
    tester,
  ) async {
    entitlement.debugSetRealPremium(
      true,
      until: DateTime.now().add(const Duration(days: 20, hours: 2)),
    );
    final refreshes = await pumpPlan(tester);

    // The page re-reads the plan when it opens.
    expect(refreshes, 1);
    final status = cardText(tester, 'plan-status-card');
    expect(status, contains('Premium'));
    expect(status, contains('Active until'));
    expect(status, contains('20 days left'));
    expect(find.text('Renew now (+30 days)'), findsOneWidget);
  });

  testWidgets('says plainly that nothing renews and nothing needs cancelling', (
    tester,
  ) async {
    entitlement.debugSetRealPremium(
      true,
      until: DateTime.now().add(const Duration(days: 10)),
    );
    await pumpPlan(tester);
    expect(find.textContaining('never renews by itself'), findsOneWidget);
    expect(find.textContaining('no subscription to cancel'), findsOneWidget);
  });

  testWidgets('the last days warn and offer to renew without a gap', (
    tester,
  ) async {
    entitlement.debugSetRealPremium(
      true,
      until: DateTime.now().add(const Duration(days: 1, hours: 4)),
    );
    await pumpPlan(tester);
    final status = cardText(tester, 'plan-status-card');
    expect(status, contains('ending soon'));
    expect(status, contains('1 day left'));
  });

  testWidgets('ended Premium says when, and that progress is kept', (
    tester,
  ) async {
    entitlement.debugSetRealPremium(
      true,
      until: DateTime.now().subtract(const Duration(days: 3)),
    );
    await pumpPlan(tester);
    final status = cardText(tester, 'plan-status-card');
    expect(status, contains('Free plan'));
    expect(status, contains('Premium ended on'));
    expect(status, contains('progress are kept'));
    expect(find.text('Renew Premium'), findsOneWidget);
  });

  testWidgets('lists the extra child profiles bought', (tester) async {
    entitlement.debugSetRealPremium(
      true,
      until: DateTime.now().add(const Duration(days: 10)),
    );
    entitlement.debugSetExtraProfileSlots(2);
    await pumpPlan(tester);
    expect(
      cardText(tester, 'plan-profiles-card'),
      contains('1 free profile + 2 extra profiles bought'),
    );
  });

  testWidgets('the free plan offers Premium, which opens checkout', (
    tester,
  ) async {
    await pumpPlan(tester);
    expect(cardText(tester, 'plan-status-card'), contains('Free plan'));
    await tester.tap(find.text('Get Premium'));
    await tester.pumpAndSettle();
    expect(find.byType(PremiumUpgradeScreen), findsOneWidget);
    expect(find.text('₱149 for 30 days'), findsOneWidget);
  });

  testWidgets('renewing from an active plan shows the running period', (
    tester,
  ) async {
    entitlement.debugSetRealPremium(
      true,
      until: DateTime.now().add(const Duration(days: 10)),
    );
    await pumpPlan(tester);
    await tester.tap(find.text('Renew now (+30 days)'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('premium-active-card')), findsOneWidget);
    expect(find.textContaining('Paying again adds 30 days'), findsOneWidget);
  });
}

class _TestChildProvider extends ChildProvider {
  _TestChildProvider()
    : super(authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()));

  @override
  ChildProfile? get profile => null;
}

class _FakeSupabaseAuthClient implements SupabaseAuthClient {
  @override
  Session? get currentSession => null;

  @override
  User? get currentUser => null;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
