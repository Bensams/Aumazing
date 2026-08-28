import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/child_mode/child_mode_lobby_screen.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/providers/stars_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The Xiaomi tablet the lobby is used on: 2880x1800 at a 2.5 device pixel
/// ratio, i.e. 1152x720 logical pixels in landscape.
const _tabletLandscape = Size(1152, 720);

/// A small landscape phone — the case where four cards at their minimum width
/// no longer fit side by side.
const _smallLandscape = Size(640, 360);

/// A typical phone held sideways for child mode (a 392x850 phone rotated).
const _phoneLandscape = Size(850, 392);

const _categoryLabels = [
  'All',
  'Play Skills',
  'Communication',
  'Social Interaction',
];

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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ParentVerificationDialog.pinDelegate = null;
  });

  tearDown(() => ParentVerificationDialog.pinDelegate = null);


  testWidgets('system back keeps the lobby visible after failed PIN', (
    tester,
  ) async {
    ParentVerificationDialog.pinDelegate = const _TestPinDelegate(
      expectedPin: '1234',
      result: ParentPinAttempt.incorrect,
    );
    await _pumpLobbyRoute(tester);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Parent Verification'), findsOneWidget);

    await _tapPin(tester, '0000');
    expect(find.text('Incorrect PIN. Try again.'), findsOneWidget);
    expect(find.byType(ChildModeLobbyScreen), findsOneWidget);
    expect(find.text('Parent screen'), findsNothing);
  });

  testWidgets('system back pops the lobby after successful PIN', (tester) async {
    ParentVerificationDialog.pinDelegate = const _TestPinDelegate(
      expectedPin: '1234',
      result: ParentPinAttempt.correct,
    );
    await _pumpLobbyRoute(tester);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    await _tapPin(tester, '1234');
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Enter your parent PIN:'), findsNothing);

    expect(find.byType(ChildModeLobbyScreen), findsNothing);
    expect(find.text('Parent screen'), findsOneWidget);
  });

  // The form factor drives the step-2 layout; pin it per test rather than
  // inferring it from the test surface.
  tearDown(() => debugSetDeviceSmallestWidthDp(null));

  testWidgets('a game that paid today is badged, and only that game', (
    tester,
  ) async {
    // AUM-285. Without this the once-a-day rule is invisible until a child
    // plays a game and receives silence.
    await tester.binding.setSurfaceSize(_tabletLandscape);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    debugSetDeviceSmallestWidthDp(720);

    await _pumpLobby(tester, starsEarnedToday: {'match_it'});
    await _openCategory(tester, 'All');

    final badged = _cardsWithStarBadge(tester);
    expect(badged, ['Match It'],
        reason: 'exactly the game that paid should carry the badge');

    // Still a full-colour, tappable card — the game remains playable and must
    // still look it. A badge is not a padlock.
    expect(
      tester.widget<InkWell>(_card('Match It')).onTap,
      isNotNull,
    );
    await _disposeLobby(tester);
  });

  testWidgets('no game badged is the neutral state', (tester) async {
    await tester.binding.setSurfaceSize(_tabletLandscape);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    debugSetDeviceSmallestWidthDp(720);

    await _pumpLobby(tester);
    await _openCategory(tester, 'All');

    expect(_cardsWithStarBadge(tester), isEmpty);
    await _disposeLobby(tester);
  });

  testWidgets('category cards are bounded tiles on a landscape tablet', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(_tabletLandscape);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpLobby(tester);

    final sizes = _categoryLabels.map((l) => tester.getSize(_card(l))).toList();

    for (var i = 0; i < sizes.length; i++) {
      final size = sizes[i];
      // The bug: cards inherited the Expanded's tight height and ran from the
      // header to the bottom of the screen.
      expect(
        size.height,
        lessThan(_tabletLandscape.height / 2),
        reason: '${_categoryLabels[i]} card fills the screen height',
      );
      expect(size.height, inInclusiveRange(260, 360));
      expect(size.width, lessThanOrEqualTo(260));
      // Portrait-ish tiles, not wide bars or tall columns.
      expect(size.height / size.width, inInclusiveRange(1.0, 1.6));
      // Equal sizes across the group.
      expect(size, sizes.first);
    }

    await _disposeLobby(tester);
  });

  testWidgets('the card group is centred in the space below the header', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(_tabletLandscape);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpLobby(tester);

    final first = tester.getRect(_card(_categoryLabels.first));
    final last = tester.getRect(_card(_categoryLabels.last));

    // Horizontally centred as a group: equal slack on both sides.
    expect(
      first.left,
      closeTo(_tabletLandscape.width - last.right, 1.0),
      reason: 'the row is not centred horizontally',
    );

    // Vertically centred in the content area, and clear of the mascot in the
    // bottom-left corner (92 logical pixels tall plus its margin).
    expect(first.top, greaterThan(0));
    expect(
      first.bottom,
      lessThan(_tabletLandscape.height - 104),
      reason: 'cards reach into the mascot corner',
    );

    await _disposeLobby(tester);
  });

  testWidgets('a narrow landscape screen scrolls the row instead of '
      'squeezing the cards', (tester) async {
    await tester.binding.setSurfaceSize(_smallLandscape);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpLobby(tester);

    expect(
      find.byWidgetPredicate(
        (w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      ),
      findsOneWidget,
    );

    final size = tester.getSize(_card(_categoryLabels.first));
    // Still a comfortable target, and still bounded by the viewport.
    expect(size.width, greaterThanOrEqualTo(168));
    expect(size.height, lessThan(_smallLandscape.height));

    await _disposeLobby(tester);
  });

  // Step 2 — the games behind "All", "Play Skills", "Communication" and
  // "Social Interaction". Same tight-height trap as the category cards: the
  // SizedBox(height: 200) could not shrink out of the Expanded above it.
  for (final category in _categoryLabels) {
    testWidgets('$category wraps its games into a grid on a tablet', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(_tabletLandscape);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      debugSetDeviceSmallestWidthDp(720);

      await _pumpLobby(tester);
      await _openCategory(tester, category);

      expect(find.byType(GridView), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is ListView && w.scrollDirection == Axis.horizontal,
        ),
        findsNothing,
        reason: '$category still uses the phone row on a tablet',
      );

      final cards = _gameCards(tester);
      expect(cards, isNotEmpty);
      for (final card in cards) {
        // The bug: cards inherited the Expanded's tight height.
        expect(
          card.height,
          lessThan(_tabletLandscape.height / 2),
          reason: '$category game cards fill the screen height',
        );
        expect(card.height, closeTo(240, 2));
        expect(card.width, closeTo(186, 2));
        expect(card.size, cards.first.size);
      }

      // Cards laid out on more than one line — i.e. actually wrapped.
      final rows = cards.map((r) => r.top.roundToDouble()).toSet();
      expect(
        rows.length,
        category == 'Social Interaction' ? 1 : greaterThanOrEqualTo(2),
        reason: '$category did not wrap as expected',
      );
      expect(rows.length, lessThanOrEqualTo(3));

      await _disposeLobby(tester);
    });
  }

  testWidgets('a tall category scrolls vertically on a tablet', (tester) async {
    await tester.binding.setSurfaceSize(_tabletLandscape);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    debugSetDeviceSmallestWidthDp(720);

    await _pumpLobby(tester);
    await _openCategory(tester, 'All');

    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(grid.scrollDirection, Axis.vertical);

    // All 12 games do not fit in the visible rows, so the grid scrolls.
    await tester.drag(find.byType(GridView), const Offset(0, -120));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await _disposeLobby(tester);
  });

  testWidgets('a phone keeps the single horizontal row', (tester) async {
    await tester.binding.setSurfaceSize(_phoneLandscape);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    debugSetDeviceSmallestWidthDp(392);

    await _pumpLobby(tester);
    await _openCategory(tester, 'All');

    expect(find.byType(GridView), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is ListView && w.scrollDirection == Axis.horizontal,
      ),
      findsOneWidget,
    );

    final cards = _gameCards(tester);
    expect(cards.first.height, lessThanOrEqualTo(240));

    await _disposeLobby(tester);
  });
}

/// Rects of the game cards currently laid out, in order.
List<Rect> _gameCards(WidgetTester tester) =>
    tester
        .widgetList<GameLogo>(find.byType(GameLogo))
        .map(
          (logo) => tester.getRect(
            find
                .ancestor(
                  of: find.byWidget(logo),
                  matching: find.byType(InkWell),
                )
                .first,
          ),
        )
        .toList();

Future<void> _openCategory(WidgetTester tester, String label) async {
  await tester.tap(_card(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expect(tester.takeException(), isNull);
}

/// Names of the game cards currently showing the "got today's star" badge.
///
/// Read from the card's semantics label rather than by finding a private
/// widget type: the label is the contract the card publishes, and asserting
/// on it checks the screen-reader wording at the same time.
List<String> _cardsWithStarBadge(WidgetTester tester) => tester
    .widgetList<Semantics>(find.byType(Semantics))
    .map((w) => w.properties.label)
    .whereType<String>()
    .where((label) => label.contains("got today's star"))
    .map((label) => label.split(',').first)
    .toList();

/// The card behind a category label — the box the layout actually sizes.
Finder _card(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;

Future<void> _pumpLobby(
  WidgetTester tester, {
  Set<String> starsEarnedToday = const {},
}) async {
  await tester.pumpWidget(
    _wrap(const ChildModeLobbyScreen(), starsEarnedToday: starsEarnedToday),
  );
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
  // Past VoiceOverService's 4s native-operation backstop, so a category
  // open (which speaks the choice) leaves no pending timer behind.
  await tester.pump(const Duration(seconds: 5));
}

Widget _wrap(Widget screen, {Set<String> starsEarnedToday = const {}}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ChildProvider>(
        create: (_) => _TestChildProvider(),
      ),
      ChangeNotifierProvider<AssessmentProvider>(
        create: (_) => _TestAssessmentProvider(),
      ),
      // The lobby reads this for the "got today's star" badge (AUM-285).
      ChangeNotifierProvider<StarsProvider>(
        create: (_) => _TestStarsProvider(starsEarnedToday),
      ),
    ],
    child: MaterialApp(theme: AppTheme.light, home: screen),
  );
}

/// Reports a fixed set of game ids as already paid today, without a database.
class _TestStarsProvider extends StarsProvider {
  _TestStarsProvider(this._earned);

  final Set<String> _earned;

  @override
  bool hasEarnedStarToday(String gameId) => _earned.contains(gameId);

  @override
  Future<void> bind(String? childId) async {}

  @override
  Future<void> refresh() async {}
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
  User? get currentUser => null;

  @override
  Session? get currentSession => null;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> _pumpLobbyRoute(WidgetTester tester) async {
  await tester.pumpWidget(_wrap(const _BackStack()));
  await tester.tap(find.text('Enter child mode'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _tapPin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.byKey(ValueKey('numpad_$digit')));
    await tester.pump();
  }
  await tester.tap(find.byKey(const ValueKey('numpad_submit')));
  await tester.pump(const Duration(seconds: 1));
}

class _BackStack extends StatelessWidget {
  const _BackStack();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Parent screen'),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ChildModeLobbyScreen(),
                ),
              ),
              child: const Text('Enter child mode'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TestPinDelegate implements ParentPinDelegate {
  const _TestPinDelegate({required this.expectedPin, required this.result});

  final String expectedPin;
  final ParentPinAttempt result;

  @override
  bool get hasPin => true;

  @override
  Future<ParentPinAttempt> verify(String pin) async {
    if (pin != expectedPin) return ParentPinAttempt.incorrect;
    return result;
  }

  @override
  Duration? get lockoutRemaining => null;

  @override
  Future<bool> onForgotPin(BuildContext context) async => false;
}
