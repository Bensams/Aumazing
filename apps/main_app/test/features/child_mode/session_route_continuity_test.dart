import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/child_mode/child_mode_lobby_screen.dart';
import 'package:aumazing/features/child_mode/time_up_dialog.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/services/screen_time_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Route-level evidence for the AUM-162 session boundary.
///
/// The service tests prove the arithmetic; these prove the *lifecycle* that
/// arithmetic runs under. The session is owned by the lobby, and games are
/// pushed above it, so the thing that actually has to hold is: walking
/// lobby → Game 1 → lobby → Game 2 keeps one session running and never
/// restarts or resets the counter. That is a property of the route stack, so
/// it is asserted against the real lobby widget rather than a service script.
const _tickSeconds = 15;

final _profile = ChildProfile(
  id: 'child-1',
  userId: 'user-1',
  displayName: 'Test',
  birthDate: DateTime(2022, 4, 20),
  avatar: 'bear',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

void main() {
  final service = ScreenTimeService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ScreenTimeService.clock = DateTime.now;
    TimeUpDialog.debugReset();
  });

  tearDown(() async {
    await service.endSession();
    ScreenTimeService.clock = DateTime.now;
    TimeUpDialog.debugReset();
  });

  testWidgets(
    'one session survives lobby → game → lobby → game without resetting',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1152, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpLobby(tester);

      // Entering child mode started exactly one session, owned by this child.
      expect(service.sessionActive, isTrue);
      expect(service.sessionChildId, 'child-1');
      expect(service.sessionUsedSeconds, 0);

      // Play in the lobby.
      await tester.pump(const Duration(seconds: _tickSeconds));
      expect(service.sessionUsedSeconds, _tickSeconds);

      // Game 1 opens above the lobby; the lobby stays mounted and owns the
      // clock, so time keeps accruing to the same session.
      await _pushGame(tester, 'Game 1');
      await tester.pump(const Duration(seconds: _tickSeconds));
      expect(service.sessionActive, isTrue);
      expect(service.sessionUsedSeconds, _tickSeconds * 2);

      // Back to the lobby / reward screen.
      await _popGame(tester);
      await tester.pump(const Duration(seconds: _tickSeconds));
      expect(service.sessionUsedSeconds, _tickSeconds * 3);

      // Game 2 — the moment a naive implementation would start over.
      await _pushGame(tester, 'Game 2');
      await tester.pump(const Duration(seconds: _tickSeconds));
      expect(service.sessionUsedSeconds, _tickSeconds * 4);

      await _popGame(tester);

      // Still one continuous session for the same child throughout.
      expect(service.sessionActive, isTrue);
      expect(service.sessionChildId, 'child-1');
      expect(service.usedTodaySeconds, _tickSeconds * 4);

      await _disposeLobby(tester);
    },
  );

  testWidgets('leaving child mode ends the session that the lobby owned', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1152, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpLobby(tester);
    await tester.pump(const Duration(seconds: _tickSeconds));
    expect(service.sessionActive, isTrue);
    expect(service.sessionUsedSeconds, _tickSeconds);

    // Popping the lobby is what every exit path does.
    await _disposeLobby(tester);

    expect(service.sessionActive, isFalse);
    // The day's total survives the session ending.
    expect(service.usedTodaySeconds, _tickSeconds);
  });

  testWidgets(
    'a session limit reached inside a game is not enforced mid-play',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1152, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpLobby(tester);
      await service.setSessionLimitMinutes(1); // 60s
      await tester.pump();

      // The child is inside a game when the budget runs out.
      await _pushGame(tester, 'Game 1');
      await tester.pump(const Duration(seconds: _tickSeconds * 4));

      expect(service.isExhausted, isTrue);
      // A mid-activity cutoff is distressing, so the rest screen waits for the
      // lobby to be current again rather than interrupting the game.
      expect(TimeUpDialog.isShowing, isFalse);
      expect(find.text('Game 1'), findsOneWidget);

      await _disposeLobby(tester);
    },
  );
}

/// Pushes a stand-in game route above the lobby, the way GameLauncher does.
Future<void> _pushGame(WidgetTester tester, String label) async {
  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(body: Center(child: Text(label))),
    ),
  );
  // Explicit pumps rather than pumpAndSettle: the lobby's idle animations
  // repeat forever, so the tree never reaches a settled state.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text(label), findsOneWidget);
}

Future<void> _popGame(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator)).pop();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _pumpLobby(WidgetTester tester) async {
  await tester.pumpWidget(_wrap(const ChildModeLobbyScreen()));
  await tester.pump();
  // Short of the 900ms entry-guidance delay, which speaks through the audio
  // plugin the test has no binding for.
  await tester.pump(const Duration(milliseconds: 300));
  expect(tester.takeException(), isNull);
}

/// Unmounts the lobby so its timers and controllers are disposed, then lets
/// the one uncancellable delayed callback (entry guidance) fire against the
/// dead state, where it returns early.
Future<void> _disposeLobby(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

Widget _wrap(Widget screen) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ChildProvider>(
        create: (_) => _TestChildProvider(),
      ),
      ChangeNotifierProvider<AssessmentProvider>(
        create: (_) => _TestAssessmentProvider(),
      ),
    ],
    child: MaterialApp(theme: AppTheme.light, home: screen),
  );
}

class _TestChildProvider extends ChildProvider {
  _TestChildProvider()
    : super(authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()));

  @override
  ChildProfile? get profile => _profile;

  @override
  Future<void> loadProfile() async {}
}

class _TestAssessmentProvider extends AssessmentProvider {
  @override
  bool get hasPreAssessment => false;

  @override
  Future<void> loadAssessments(String childId) async {}
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
