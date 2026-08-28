import 'package:aumazing/core/repositories/star_repository.dart';
import 'package:aumazing/core/services/local_db_service.dart';
import 'package:aumazing/core/sync/sync_status.dart';
import 'package:aumazing/features/stars/star_catalogue.dart';
import 'package:aumazing/features/stars/widgets/star_earned_overlay.dart';
import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/providers/stars_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// AUM-286 — the two ways an award can grant nothing are different things,
/// and the child is told which.
///
/// Before this they were both a bare `0`, so the game-end flow could only
/// respond by showing nothing at all: a child finished a game and the app said
/// not one word. These tests pin the distinction at its source, because a
/// wrong reason is worse than the silence it replaced.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  late _TestDb db;
  late StarsProvider stars;

  setUp(() async {
    db = _TestDb();
    stars = StarsProvider(repository: StarRepository(db: db));
    await stars.bind('c1');
  });

  tearDown(() => db.close());

  String keyFor(String gameId) =>
      starPlayKey(childId: 'c1', gameId: gameId);

  test('a first finish earns', () async {
    final award = await stars.awardForPlay(playKey: keyFor('match_it'));

    expect(award.outcome, StarAwardOutcome.earned);
    expect(award.granted, kStarsPerGame);
    expect(award.didEarn, isTrue);
  });

  test('the same game again today reports why, not just zero', () async {
    await stars.awardForPlay(playKey: keyFor('match_it'));
    final again = await stars.awardForPlay(playKey: keyFor('match_it'));

    expect(again.outcome, StarAwardOutcome.alreadyEarnedToday);
    expect(again.granted, 0);
    expect(again.didEarn, isFalse);
  });

  test('at the cap, a game never played today reports the cap', () async {
    // Five different games fills kDailyStarCap.
    for (final gameId in ['a', 'b', 'c', 'd', 'e']) {
      await stars.awardForPlay(playKey: keyFor(gameId));
    }
    expect(stars.atDailyCap, isTrue);

    final sixth = await stars.awardForPlay(playKey: keyFor('f'));
    expect(sixth.outcome, StarAwardOutcome.dailyCapReached);
    expect(sixth.granted, 0);
  });

  test('at the cap, a game already played today still reports the replay',
      () async {
    // Both conditions hold at once, and the more specific one is the useful
    // one: "this game already paid" tells a child something they can act on,
    // where "the day is done" would be true but unhelpfully broad.
    for (final gameId in ['a', 'b', 'c', 'd', 'e']) {
      await stars.awardForPlay(playKey: keyFor(gameId));
    }

    final again = await stars.awardForPlay(playKey: keyFor('a'));
    expect(again.outcome, StarAwardOutcome.alreadyEarnedToday);
  });

  test('an unbound provider attempts nothing and says nothing', () async {
    final unbound = StarsProvider(repository: StarRepository(db: db));
    final award = await unbound.awardForPlay(playKey: keyFor('match_it'));

    expect(award.outcome, StarAwardOutcome.noChild);
    expect(award.granted, 0);
  });

  group('the moment shown when nothing was earned', () {
    testWidgets('says the headline and the note, with no stars claimed', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const StarEarnedOverlay(
            granted: 0,
            headline: "You already got today's star for Match It!",
            note: 'Try another game to earn more!',
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text("You already got today's star for Match It!"),
        findsOneWidget,
      );
      expect(find.text('Try another game to earn more!'), findsOneWidget);
      // Never the earning wording — nothing was earned.
      expect(find.textContaining('You earned'), findsNothing);
      expect(tester.takeException(), isNull);
      await _letItLeave(tester);
    });

    testWidgets('the earning moment is unchanged', (tester) async {
      await tester.pumpWidget(_wrap(const StarEarnedOverlay(granted: 3)));
      await tester.pump();

      expect(find.text('You earned 3 stars!'), findsOneWidget);
      expect(find.text('⭐'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
      await _letItLeave(tester);
    });
  });
}

/// The moment dismisses itself after 1.8s. Pumping past that drains the timer,
/// which the test binding otherwise reports as still pending at teardown.
Future<void> _letItLeave(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 2));

/// The overlay reads the child's animation intensity and SFX volume. A null
/// profile is the quiet default: no chime is attempted at all, which keeps the
/// audio plugin out of a widget test.
Widget _wrap(Widget child) => ChangeNotifierProvider<ChildProvider>(
      create: (_) => _NoProfileChild(),
      child: MaterialApp(home: child),
    );

class _NoProfileChild extends ChildProvider {
  _NoProfileChild()
      : super(authService: AuthService(supabaseAuth: _FakeSupabaseAuth()));

  @override
  ChildProfile? get profile => null;

  @override
  Future<void> loadProfile() async {}
}

class _FakeSupabaseAuth implements SupabaseAuthClient {
  @override
  User? get currentUser => null;

  @override
  Session? get currentSession => null;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// An in-memory ledger, so an outcome is decided by real rows rather than by
/// a stubbed provider agreeing with itself.
class _TestDb extends LocalDbService {
  Database? _db;

  @override
  Future<Database> get database async {
    _db ??= await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE ${LocalTables.starLedger} (
            id TEXT PRIMARY KEY,
            child_id TEXT NOT NULL,
            delta INTEGER NOT NULL,
            reason TEXT NOT NULL,
            game_session_id TEXT,
            item_id TEXT,
            created_at TEXT NOT NULL,
            synced INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE UNIQUE INDEX idx_star_ledger_session
            ON ${LocalTables.starLedger}(child_id, game_session_id, reason)
            WHERE game_session_id IS NOT NULL
        ''');
        await db.execute('''
          CREATE TABLE ${LocalTables.childUnlocks} (
            child_id TEXT NOT NULL,
            item_id TEXT NOT NULL,
            unlocked_at TEXT NOT NULL,
            synced INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (child_id, item_id)
          )
        ''');
      },
    );
    return _db!;
  }

  @override
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
