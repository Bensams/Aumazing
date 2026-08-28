import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/core/services/local_db_service.dart';
import 'package:aumazing/features/settings/delete_account_screen.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Deleting an account is the one action in the app that cannot be undone
/// (AUM-147). These pin the guards: it takes a deliberate confirmation *and*
/// parent verification, it never fires by accident, and a failure leaves the
/// account alone rather than half-deleting it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ParentVerificationDialog.pinDelegate = null;
  });

  tearDown(() => ParentVerificationDialog.pinDelegate = null);

  const words = [
    'zero',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
  ];

  String shownCode(WidgetTester tester) {
    final shown =
        tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .where((s) => s != null && words.contains(s))
            .map((s) => words.indexOf(s!).toString())
            .toList();
    expect(shown, hasLength(4));
    return shown.join();
  }

  Future<void> verifyAsParent(WidgetTester tester) async {
    final code = shownCode(tester);
    for (final digit in code.split('')) {
      await tester.tap(find.byKey(ValueKey('numpad_$digit')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('numpad_submit')));
    await tester.pumpAndSettle();
  }

  Future<_FakeAuth> pumpScreen(
    WidgetTester tester, {
    _FakeAuth? auth,
    _FakeDb? db,
  }) async {
    final authService = auth ?? _FakeAuth();
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider<ChildProvider>(
        create: (_) => _TestChildProvider(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: DeleteAccountScreen(
            palette: GamePalettes.neutral,
            authService: authService,
            localDb: db ?? _FakeDb(),
            // Stands in for the login screen, which needs a live Supabase
            // instance this test has no reason to stand up.
            signedOutBuilder:
                (_) => const Scaffold(body: Center(child: Text('signed out'))),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return authService;
  }

  testWidgets('the delete button is disabled until DELETE is typed', (
    tester,
  ) async {
    await pumpScreen(tester);

    final button = tester.widget<ElevatedButton>(
      find.byKey(const Key('deleteAccount.submit')),
    );
    expect(button.onPressed, isNull, reason: 'never one stray tap away');
  });

  testWidgets('a near-miss does not enable deletion', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(
      find.byKey(const Key('deleteAccount.confirmField')),
      'DELET',
    );
    await tester.pump();

    final button = tester.widget<ElevatedButton>(
      find.byKey(const Key('deleteAccount.submit')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('typing DELETE enables it, in any case', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(
      find.byKey(const Key('deleteAccount.confirmField')),
      'delete',
    );
    await tester.pump();

    final button = tester.widget<ElevatedButton>(
      find.byKey(const Key('deleteAccount.submit')),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('deletion still requires parent verification', (tester) async {
    final auth = await pumpScreen(tester);

    await tester.enterText(
      find.byKey(const Key('deleteAccount.confirmField')),
      'DELETE',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('deleteAccount.submit')));
    await tester.pumpAndSettle();

    // The verification challenge is up and nothing has been deleted yet.
    expect(find.byKey(const ValueKey('numpad_submit')), findsOneWidget);
    expect(auth.deleteCalls, 0);
  });

  testWidgets('a failed verification deletes nothing', (tester) async {
    final auth = await pumpScreen(tester);

    await tester.enterText(
      find.byKey(const Key('deleteAccount.confirmField')),
      'DELETE',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('deleteAccount.submit')));
    await tester.pumpAndSettle();

    final code = shownCode(tester);
    final wrong =
        code.split('').map((d) => ((int.parse(d) + 1) % 10).toString()).join();
    for (final digit in wrong.split('')) {
      await tester.tap(find.byKey(ValueKey('numpad_$digit')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('numpad_submit')));
    await tester.pumpAndSettle();

    expect(auth.deleteCalls, 0);
  });

  testWidgets('a verified confirmation deletes the account and wipes local '
      'data', (tester) async {
    final db = _FakeDb();
    final auth = await pumpScreen(tester, db: db);

    await tester.enterText(
      find.byKey(const Key('deleteAccount.confirmField')),
      'DELETE',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('deleteAccount.submit')));
    await tester.pumpAndSettle();
    await verifyAsParent(tester);

    expect(auth.deleteCalls, 1);
    expect(db.cleared, 1, reason: 'the next account must not inherit this one');
    // And the parent is put back at the signed-out screen, with no route
    // left behind to navigate back into the deleted account.
    expect(find.text('signed out'), findsOneWidget);
    expect(find.byKey(const Key('deleteAccount.submit')), findsNothing);
  });

  testWidgets('a server failure leaves the account alone and says so', (
    tester,
  ) async {
    final auth = _FakeAuth(failWith: AuthException('Account deletion failed.'));
    final db = _FakeDb();
    await pumpScreen(tester, auth: auth, db: db);

    await tester.enterText(
      find.byKey(const Key('deleteAccount.confirmField')),
      'DELETE',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('deleteAccount.submit')));
    await tester.pumpAndSettle();
    await verifyAsParent(tester);

    // Local data is untouched — a half-deleted state would be worse than
    // no deletion at all.
    expect(db.cleared, 0);
    expect(find.byKey(const Key('deleteAccount.error')), findsOneWidget);
    // The raw exception never reaches the parent.
    expect(find.textContaining('AuthException'), findsNothing);
  });

  testWidgets('the screen offers a way out that changes nothing', (
    tester,
  ) async {
    final auth = await pumpScreen(tester);

    expect(find.text('Keep my account'), findsOneWidget);
    expect(auth.deleteCalls, 0);
  });
}

class _FakeAuth extends AuthService {
  _FakeAuth({this.failWith}) : super(supabaseAuth: _FakeSupabaseAuthClient());

  final Object? failWith;
  int deleteCalls = 0;

  @override
  Future<void> deleteAccount() async {
    if (failWith != null) throw failWith!;
    deleteCalls++;
  }
}

class _FakeDb extends LocalDbService {
  int cleared = 0;

  @override
  Future<void> clearAll() async => cleared++;
}

class _TestChildProvider extends ChildProvider {
  _TestChildProvider()
    : super(authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()));

  @override
  ChildProfile? get profile => null;

  @override
  void clear() {}
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
