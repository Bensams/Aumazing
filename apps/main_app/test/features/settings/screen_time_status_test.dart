import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/settings/settings_screen.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/services/screen_time_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Parent-facing screen-time status (AUM-162).
///
/// A parent has to be able to read, without inference, how much has been
/// played, what the limit is, and how much is left — for *both* the daily and
/// the session budget. The no-limit cases are stated outright rather than the
/// row being dropped, which is what an earlier revision did for sessions.
void main() {
  final profile = ChildProfile(
    id: 'child-1',
    userId: 'user-1',
    displayName: 'Test',
    birthDate: DateTime(2022, 4, 20),
    avatar: 'bear',
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );

  final service = ScreenTimeService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ScreenTimeService.clock = DateTime.now;
  });

  tearDown(() async {
    await service.endSession();
    ScreenTimeService.clock = DateTime.now;
  });

  Future<void> openScreenTime(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ChildProvider>.value(
            value: _TestChildProvider(profile),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: SettingsScreen(
            authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Screen Time'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('screenTime.dailyUsed')), findsOneWidget);
  }

  /// Applies the budget state *after* the screen is mounted, so the values
  /// under assertion are the ones the screen's listener rendered — the
  /// mount-time reload would otherwise race the pre-seeded state.
  Future<void> applyState(
    WidgetTester tester, {
    int? dailyMinutes,
    int? sessionMinutes,
    int usageSeconds = 0,
  }) async {
    await service.setLimitMinutes(dailyMinutes);
    await service.setSessionLimitMinutes(sessionMinutes);
    if (usageSeconds > 0) {
      await service.startSession();
      await service.addUsage(usageSeconds);
    }
    await tester.pumpAndSettle();
  }

  String valueAt(WidgetTester tester, String key) {
    return tester.widget<Text>(find.byKey(Key(key))).data!;
  }

  testWidgets('both budgets show used, configured and remaining', (
    tester,
  ) async {
    await openScreenTime(tester);
    await applyState(
      tester,
      dailyMinutes: 30, // 1800s
      sessionMinutes: 10, // 600s
      usageSeconds: 150, // 2m 30s
    );

    expect(valueAt(tester, 'screenTime.dailyUsed'), '2m 30s');
    expect(valueAt(tester, 'screenTime.dailyLimit'), '30m');
    expect(valueAt(tester, 'screenTime.dailyRemaining'), '27m 30s');

    expect(valueAt(tester, 'screenTime.sessionUsed'), '2m 30s');
    expect(valueAt(tester, 'screenTime.sessionLimit'), '10m');
    expect(valueAt(tester, 'screenTime.sessionRemaining'), '7m 30s');
  });

  testWidgets('no session limit is stated, not hidden', (tester) async {
    await openScreenTime(tester);
    await applyState(tester, dailyMinutes: 30, sessionMinutes: null);

    // The session rows are still present and say so explicitly.
    expect(valueAt(tester, 'screenTime.sessionLimit'), 'No session limit');
    expect(valueAt(tester, 'screenTime.sessionRemaining'), 'No session limit');
    // The daily budget is unaffected.
    expect(valueAt(tester, 'screenTime.dailyLimit'), '30m');
  });

  testWidgets('no daily limit is stated, not hidden', (tester) async {
    await openScreenTime(tester);
    await applyState(tester, dailyMinutes: null, sessionMinutes: 10);

    expect(valueAt(tester, 'screenTime.dailyLimit'), 'No daily limit');
    expect(valueAt(tester, 'screenTime.dailyRemaining'), 'No daily limit');
    expect(valueAt(tester, 'screenTime.sessionLimit'), '10m');
  });

  testWidgets('neither limit set shows both no-limit labels', (tester) async {
    await openScreenTime(tester);
    await applyState(tester, dailyMinutes: null, sessionMinutes: null);

    expect(valueAt(tester, 'screenTime.dailyLimit'), 'No daily limit');
    expect(valueAt(tester, 'screenTime.sessionLimit'), 'No session limit');
    expect(valueAt(tester, 'screenTime.dailyUsed'), '0s');
    expect(valueAt(tester, 'screenTime.sessionUsed'), '0s');
  });

  testWidgets('an exhausted budget clamps remaining at zero, never negative', (
    tester,
  ) async {
    await openScreenTime(tester);
    await applyState(
      tester,
      dailyMinutes: 1, // 60s
      sessionMinutes: 1,
      usageSeconds: 200, // well past both budgets
    );

    expect(valueAt(tester, 'screenTime.dailyRemaining'), '0s');
    expect(valueAt(tester, 'screenTime.sessionRemaining'), '0s');
    expect(valueAt(tester, 'screenTime.dailyUsed'), '3m 20s');
  });

  testWidgets('the status block survives a large text scale', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ChildProvider>.value(
            value: _TestChildProvider(profile),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          builder:
              (context, child) => MediaQuery.withClampedTextScaling(
                minScaleFactor: 2.0,
                maxScaleFactor: 2.0,
                child: child!,
              ),
          home: SettingsScreen(
            authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Screen Time'));
    await tester.pumpAndSettle();
    await applyState(tester, dailyMinutes: 30, sessionMinutes: 10);

    // No overflow exception, and the values are still readable.
    expect(tester.takeException(), isNull);
    expect(valueAt(tester, 'screenTime.dailyLimit'), '30m');
    expect(valueAt(tester, 'screenTime.sessionLimit'), '10m');
  });
}

class _TestChildProvider extends ChildProvider {
  _TestChildProvider(this._profile)
    : super(authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()));

  final ChildProfile _profile;

  @override
  ChildProfile? get profile => _profile;

  @override
  bool get hasProfile => true;
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
