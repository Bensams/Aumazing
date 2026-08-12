import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/child_mode/child_mode_lobby_screen.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/providers/child_provider.dart';
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

  // Step 2 — the row of games behind "All", "Play Skills", "Communication"
  // and "Social Interaction". Same tight-height trap as the category cards:
  // its SizedBox(height: 200) could not shrink out of the Expanded above it.
  for (final category in _categoryLabels) {
    testWidgets('$category opens a row of bounded game cards', (tester) async {
      await tester.binding.setSurfaceSize(_tabletLandscape);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpLobby(tester);
      await tester.tap(_card(category));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      // The row is showing: the header now names the category (or All Games).
      final cards = find.byType(GameLogo);
      expect(cards, findsWidgets);

      final row = tester.getSize(
        find.ancestor(of: cards.first, matching: find.byType(ListView)).first,
      );
      expect(
        row.height,
        lessThan(_tabletLandscape.height / 2),
        reason: '$category game cards fill the screen height',
      );
      expect(row.height, inInclusiveRange(200, 320));

      await _disposeLobby(tester);
    });
  }
}

/// The card behind a category label — the box the layout actually sizes.
Finder _card(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;

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
  User? get currentUser => null;

  @override
  Session? get currentSession => null;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
