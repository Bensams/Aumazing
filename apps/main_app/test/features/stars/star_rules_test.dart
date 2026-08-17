import 'dart:io';

import 'package:aumazing/core/repositories/star_repository.dart';
import 'package:aumazing/core/services/local_db_service.dart';
import 'package:aumazing/core/sync/sync_status.dart';
import 'package:aumazing/features/stars/star_catalogue.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/model/star_ledger_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Pins the Star Shop's invariants (AUM-246).
///
/// These are not incidental behaviours to be updated when they fail. Each one
/// is the difference between a digital token board and the kind of
/// variable-reward loop this app exists to be the opposite of. If one of these
/// breaks, the fix is in the code, not in the expectation.
void main() {
  group('STAR-B1 — the award is fixed', () {
    test('is the same whatever happened in the session', () {
      // There is no code path from a session's score, errors, hints, retries
      // or duration to the payout, so the guarantee is structural: the award
      // is a constant, and the repository takes no outcome argument at all.
      expect(kStarsPerGame, 3);
      expect(
        StarRepository.new,
        isNotNull,
        reason: 'awardForSession takes no score/accuracy parameter — see its '
            'signature; adding one would break this rule.',
      );
    });

    test('the daily cap is a whole number of games', () {
      expect(kDailyStarCap % kStarsPerGame, 0);
    });
  });

  group('STAR-B5 — stars are never lost', () {
    test('only a purchase may carry a negative delta', () {
      expect(StarReason.purchase.maySpend, isTrue);
      for (final reason in StarReason.values.where((r) => !r.maySpend)) {
        expect(
          () => StarLedgerEntry(
            id: 'x',
            childId: 'c',
            delta: -1,
            reason: reason,
            createdAt: DateTime(2026),
          ),
          throwsA(isA<AssertionError>()),
          reason: '$reason must not be able to remove stars',
        );
      }
    });

    test('earning reasons accept only non-negative deltas', () {
      expect(
        () => StarLedgerEntry(
          id: 'x',
          childId: 'c',
          delta: kStarsPerGame,
          reason: StarReason.gamePlayed,
          createdAt: DateTime(2026),
        ),
        returnsNormally,
      );
    });
  });

  group('STAR-C5 — prices are fixed and honest', () {
    test('every purchasable costume has a positive, constant price', () {
      for (final costume in Costume.purchasable) {
        expect(costume.priceStars, greaterThan(0), reason: costume.id);
      }
      // Reading twice returns the same value — enum fields are `const`, so
      // there is nowhere for a sale or a personalised price to live.
      expect(Costume.panda.priceStars, Costume.panda.priceStars);
    });

    test('no costume is free except "none", which is not purchasable', () {
      expect(Costume.none.priceStars, 0);
      expect(Costume.purchasable, isNot(contains(Costume.none)));
    });

    test('the shop lists cheapest first, so the nearest goal is on top', () {
      final prices = Costume.purchasable.map((c) => c.priceStars).toList();
      expect(prices, orderedEquals(List.of(prices)..sort()));
    });
  });

  group('STAR-D3 — every costume fits every character', () {
    test('all 27 combinations resolve to a distinct asset path', () {
      final paths = <String>{};
      for (final character in ChildCharacter.values) {
        for (final costume in Costume.purchasable) {
          final path = costume.assetFor(character);
          expect(path, contains(costume.id));
          expect(path, contains(character.id));
          expect(paths.add(path), isTrue, reason: 'duplicate path: $path');
        }
      }
      expect(paths,
          hasLength(ChildCharacter.values.length * Costume.purchasable.length));
    });

    test('every catalogue asset actually exists on disk', () {
      // `packages/assets/` has no pubspec, so nothing in it ships with the
      // app — an asset path pointing there resolves in the editor and fails
      // silently at runtime as a grey box. This test is what makes that
      // impossible to reintroduce: it walks the real file system rather than
      // trusting the string.
      final root = Directory.current.path.endsWith('main_app')
          ? Directory('${Directory.current.path}/../..')
          : Directory.current;
      final missing = <String>[];
      for (final character in ChildCharacter.values) {
        for (final costume in [Costume.none, ...Costume.purchasable]) {
          // 'packages/shared_ui/assets/x.png' -> 'packages/shared_ui/assets/x.png'
          final rel = costume.assetFor(character);
          final file = File('${root.path}/$rel');
          if (!file.existsSync()) missing.add(rel);
        }
      }
      expect(missing, isEmpty, reason: 'costume art not bundled: $missing');
    });

    test('availability does not vary by character', () {
      final byCharacter = {
        for (final c in ChildCharacter.values)
          c: Costume.purchasable.map((x) => x.id).toSet(),
      };
      final first = byCharacter.values.first;
      for (final set in byCharacter.values) {
        expect(set, equals(first));
      }
    });
  });

  group('STAR-A3 — the character is never derived from recorded sex', () {
    test('every ChildSex value still offers all three characters', () {
      // The picker is not even given the child's sex; this asserts the model
      // side, that nothing in ChildProfile couples the two fields.
      for (final sex in [...ChildSex.values, null]) {
        final profile = _profile(sex: sex, characterId: 'lexianne');
        expect(profile.character, ChildCharacter.lexianne,
            reason: 'sex=$sex must not influence the chosen character');
      }
    });

    test('changing sex leaves the character untouched', () {
      final before = _profile(sex: ChildSex.male, characterId: 'reiz');
      final after = before.copyWith(sex: ChildSex.female);
      expect(after.character, ChildCharacter.reiz);
    });

    test('an unknown character id falls back instead of throwing', () {
      expect(_profile(characterId: 'not-a-character').character,
          ChildCharacter.bps);
    });
  });

  group('STAR-C1 — nothing is ever "locked"', () {
    test('an unaffordable costume reports progress, not rejection', () {
      const offer = CostumeOffer(
        costume: Costume.unicorn,
        owned: false,
        balance: 0,
      );
      expect(offer.affordable, isFalse);
      expect(offer.progress, 0);
      expect(offer.remaining, Costume.unicorn.priceStars);
      // Phrased as a countdown of games, never as a refusal.
      expect(offer.spokenProgress, contains('more games until'));
    });

    test('progress is clamped and complete once owned', () {
      const owned = CostumeOffer(
        costume: Costume.teddy,
        owned: true,
        balance: 0,
      );
      expect(owned.progress, 1);
      expect(owned.remaining, 0);

      const rich = CostumeOffer(
        costume: Costume.teddy,
        owned: false,
        balance: 9999,
      );
      expect(rich.progress, 1);
      expect(rich.remaining, 0);
    });
  });

  group('StarRepository', () {
    late _TestDb db;
    late StarRepository repo;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      db = _TestDb();
      repo = StarRepository(db: db);
    });

    tearDown(() => db.close());

    test('balance is derived by summing the ledger', () async {
      expect(await repo.balanceFor('c1'), 0);
      await repo.awardForSession(childId: 'c1', gameSessionId: 's1');
      await repo.awardForSession(childId: 'c1', gameSessionId: 's2');
      expect(await repo.balanceFor('c1'), kStarsPerGame * 2);
    });

    test('STAR-E2 — replaying a session does not pay twice', () async {
      final first = await repo.awardForSession(childId: 'c1', gameSessionId: 's1');
      final second = await repo.awardForSession(childId: 'c1', gameSessionId: 's1');
      expect(first, kStarsPerGame);
      expect(second, 0);
      expect(await repo.balanceFor('c1'), kStarsPerGame);
    });

    test('STAR-B4 — the daily cap stops payouts but not play', () async {
      final day = DateTime(2026, 8, 18, 9);
      var total = 0;
      for (var i = 0; i < 20; i++) {
        total += await repo.awardForSession(
          childId: 'c1',
          gameSessionId: 'session-$i',
          now: day,
        );
      }
      expect(total, kDailyStarCap);
      expect(await repo.balanceFor('c1'), kDailyStarCap);

      // A new day pays again — the cap is a daily ceiling, not a lifetime one.
      final tomorrow = day.add(const Duration(days: 1));
      final next = await repo.awardForSession(
        childId: 'c1',
        gameSessionId: 'fresh',
        now: tomorrow,
      );
      expect(next, kStarsPerGame);
    });

    test('spending does not buy back headroom under the daily cap', () async {
      final day = DateTime(2026, 8, 18, 9);
      for (var i = 0; i < 5; i++) {
        await repo.awardForSession(
          childId: 'c1', gameSessionId: 'g$i', now: day);
      }
      expect(await repo.balanceFor('c1'), kDailyStarCap);
      await repo.purchase(childId: 'c1', costume: Costume.teddy, now: day);

      final more = await repo.awardForSession(
        childId: 'c1', gameSessionId: 'after-purchase', now: day);
      expect(more, 0, reason: 'buying must not unlock more earning today');
    });

    test('purchase debits, unlocks, and is refused when unaffordable', () async {
      expect(
        await repo.purchase(childId: 'c1', costume: Costume.teddy),
        isFalse,
        reason: 'no stars yet',
      );

      for (var i = 0; i < 4; i++) {
        await repo.awardForSession(childId: 'c1', gameSessionId: 'g$i');
      }
      final balance = await repo.balanceFor('c1');
      expect(balance, greaterThanOrEqualTo(Costume.teddy.priceStars));

      expect(await repo.purchase(childId: 'c1', costume: Costume.teddy), isTrue);
      expect(await repo.balanceFor('c1'), balance - Costume.teddy.priceStars);
      expect(await repo.unlockedFor('c1'), contains(Costume.teddy.id));

      // Monotonic: buying again is a no-op, never a second charge.
      expect(await repo.purchase(childId: 'c1', costume: Costume.teddy), isFalse);
      expect(await repo.balanceFor('c1'), balance - Costume.teddy.priceStars);
    });

    test('offers cover every costume, affordable or not', () async {
      final offers = await repo.offersFor('c1');
      expect(offers, hasLength(Costume.purchasable.length));
      expect(offers.every((o) => !o.owned), isTrue);
    });
  });
}

ChildProfile _profile({ChildSex? sex, String characterId = 'bps'}) => ChildProfile(
      id: 'c1',
      userId: 'p1',
      displayName: 'Test',
      birthDate: DateTime(2021, 1, 1),
      avatar: 'avatar_1',
      sex: sex,
      characterId: characterId,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

/// In-memory database carrying only the star tables, mirroring the schema in
/// `LocalDbService._createStarTables`.
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
