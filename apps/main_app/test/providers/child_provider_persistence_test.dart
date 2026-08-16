import 'package:aumazing/core/repositories/child_repository.dart';
import 'package:aumazing/core/services/local_db_service.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';

import '../support/fake_auth.dart';

/// AUM-151 — persist the selected child profile.
///
/// The active child is saved per parent account (`active_child_<userId>`)
/// and restored whenever the provider is rebuilt — app restart, re-login,
/// account switch. A saved id that no longer resolves to one of this
/// parent's children falls back deterministically to the oldest child, and
/// the fallback is re-saved so every later launch agrees with this one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ChildProfile child(
    String id, {
    String name = 'Child',
    String userId = 'user-1',
    DateTime? createdAt,
  }) => ChildProfile(
    id: id,
    userId: userId,
    displayName: name,
    birthDate: DateTime(2020, 1, 1),
    avatar: '🐻',
    createdAt: createdAt ?? DateTime(2026, 1, 1),
    updatedAt: createdAt ?? DateTime(2026, 1, 1),
  );

  ({ChildProvider provider, _FakeLocalDb db}) build({
    List<ChildProfile> children = const [],
    String userId = 'user-1',
    bool guest = false,
    String? migratedFromGuestId,
    String? storedGuestId,
  }) {
    final db = _FakeLocalDb(children);
    final auth = FakeAuthService(
      userId: userId,
      loggedIn: !guest,
      migratedFromGuestId: migratedFromGuestId,
      storedGuestId: storedGuestId,
    );
    return (
      provider: ChildProvider(
        localDb: db,
        authService: auth,
        childRepository: _FakeChildRepository(db, userId),
      ),
      db: db,
    );
  }

  Future<String?> savedFor(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('active_child_$userId');
  }

  group('saving the selection', () {
    test('selecting a child saves it under this parent\'s key', () async {
      final harness = build(
        children: [
          child('a'),
          child('b', createdAt: DateTime(2026, 2, 1)),
        ],
      );
      await harness.provider.loadProfile();

      await harness.provider.selectChild('b');

      expect(await savedFor('user-1'), 'b');
    });

    test('the default choice on first load is saved too', () async {
      final harness = build(
        children: [
          child('a'),
          child('b', createdAt: DateTime(2026, 2, 1)),
        ],
      );

      await harness.provider.loadProfile();

      expect(harness.provider.activeChildId, 'a');
      expect(await savedFor('user-1'), 'a');
    });

    test('the first child added to an empty account is saved', () async {
      final harness = build();
      await harness.provider.loadProfile();

      final created = await harness.provider.addChild(
        displayName: 'Ana',
        birthDate: DateTime(2021, 6, 5),
        avatar: '🐻',
      );

      expect(await savedFor('user-1'), created.id);
    });

    test('deleting the active child saves the replacement', () async {
      final harness = build(
        children: [
          child('a'),
          child('b', createdAt: DateTime(2026, 2, 1)),
        ],
      );
      await harness.provider.loadProfile();

      await harness.provider.deleteChild('a');

      expect(harness.provider.activeChildId, 'b');
      expect(await savedFor('user-1'), 'b');
    });

    test('deleting the last child clears the saved selection', () async {
      final harness = build(children: [child('a')]);
      await harness.provider.loadProfile();

      await harness.provider.deleteChild('a');

      expect(harness.provider.hasProfile, isFalse);
      expect(await savedFor('user-1'), isNull);
    });
  });

  group('restoring the selection', () {
    test(
      'a rebuilt provider restores the saved child, not the oldest',
      () async {
        final children = [
          child('a'),
          child('b', createdAt: DateTime(2026, 2, 1)),
        ];
        final first = build(children: children);
        await first.provider.loadProfile();
        await first.provider.selectChild('b');

        // Simulates an app restart: a brand-new provider over the same storage.
        final second = build(children: children);
        await second.provider.loadProfile();

        expect(second.provider.activeChildId, 'b');
      },
    );

    test('the restored child gets its own preferences, not defaults', () async {
      SharedPreferences.setMockInitialValues({
        'active_child_user-1': 'b',
        'language_a': 'ceb',
        'difficulty_override_a': 3,
        'language_b': 'fil',
        'difficulty_override_b': 2,
      });
      final harness = build(
        children: [
          child('a'),
          child('b', createdAt: DateTime(2026, 2, 1)),
        ],
      );

      await harness.provider.loadProfile();

      expect(harness.provider.activeChildId, 'b');
      expect(harness.provider.language, GameLanguage.fromSlug('fil'));
      expect(harness.provider.difficultyOverride, 2);
    });

    test('no saved selection falls back to the oldest child', () async {
      final harness = build(
        children: [
          child('b', createdAt: DateTime(2026, 2, 1)),
          child('a'),
        ],
      );

      await harness.provider.loadProfile();

      expect(harness.provider.activeChildId, 'a');
    });

    test('a saved child that was deleted falls back and re-saves', () async {
      SharedPreferences.setMockInitialValues({'active_child_user-1': 'gone'});
      final harness = build(
        children: [
          child('a'),
          child('b', createdAt: DateTime(2026, 2, 1)),
        ],
      );

      await harness.provider.loadProfile();

      expect(harness.provider.activeChildId, 'a');
      // The fallback replaces the stale id, so the next launch agrees.
      expect(await savedFor('user-1'), 'a');
    });

    test(
      'a stale saved id with no children left clears the selection',
      () async {
        SharedPreferences.setMockInitialValues({'active_child_user-1': 'gone'});
        final harness = build();

        await harness.provider.loadProfile();

        expect(harness.provider.hasProfile, isFalse);
        expect(await savedFor('user-1'), isNull);
      },
    );

    test('a saved id pointing at another parent\'s child is ignored', () async {
      SharedPreferences.setMockInitialValues({'active_child_user-1': 'theirs'});
      final harness = build(
        children: [
          child('mine', userId: 'user-1'),
          child('theirs', userId: 'user-2'),
        ],
      );

      await harness.provider.loadProfile();

      expect(harness.provider.activeChildId, 'mine');
      expect(await savedFor('user-1'), 'mine');
    });

    test(
      'an in-session selection survives a reload over a stale saved id',
      () async {
        final harness = build(
          children: [
            child('a'),
            child('b', createdAt: DateTime(2026, 2, 1)),
          ],
        );
        await harness.provider.loadProfile();
        await harness.provider.selectChild('b');

        // Something else rewrote the key; the live session still wins.
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('active_child_user-1', 'a');
        await harness.provider.loadProfile();

        expect(harness.provider.activeChildId, 'b');
      },
    );

    test('a single child stays active with nothing saved', () async {
      final harness = build(children: [child('only')]);

      await harness.provider.loadProfile();

      expect(harness.provider.activeChildId, 'only');
      expect(await savedFor('user-1'), 'only');
    });
  });

  group('account isolation', () {
    test('two accounts on the same device keep separate selections', () async {
      final children = [
        child('a1', userId: 'user-1'),
        child('a2', userId: 'user-1', createdAt: DateTime(2026, 2, 1)),
        child('b1', userId: 'user-2'),
        child('b2', userId: 'user-2', createdAt: DateTime(2026, 2, 1)),
      ];
      final one = build(children: children);
      await one.provider.loadProfile();
      await one.provider.selectChild('a2');

      // The second parent signs in on the same device: they get their own
      // default, not the first parent's saved child.
      final two = build(children: children, userId: 'user-2');
      await two.provider.loadProfile();
      expect(two.provider.activeChildId, 'b1');
      await two.provider.selectChild('b2');

      // And the first parent's selection is still intact afterwards.
      final oneAgain = build(children: children);
      await oneAgain.provider.loadProfile();
      expect(oneAgain.provider.activeChildId, 'a2');
      expect(await savedFor('user-2'), 'b2');
    });

    test('a guest parent restores their own selection', () async {
      final children = [
        child('g1', userId: 'guest_abc'),
        child('g2', userId: 'guest_abc', createdAt: DateTime(2026, 2, 1)),
      ];
      final guest = build(children: children, userId: 'guest_abc', guest: true);
      await guest.provider.loadProfile();
      await guest.provider.selectChild('g2');

      final restarted = build(
        children: children,
        userId: 'guest_abc',
        guest: true,
      );
      await restarted.provider.loadProfile();

      expect(restarted.provider.activeChildId, 'g2');
    });

    test(
      'sign-out clears memory but re-login restores the selection',
      () async {
        final children = [
          child('a'),
          child('b', createdAt: DateTime(2026, 2, 1)),
        ];
        final harness = build(children: children);
        await harness.provider.loadProfile();
        await harness.provider.selectChild('b');

        harness.provider.clear();
        expect(harness.provider.hasProfile, isFalse);
        expect(harness.provider.activeChildId, isNull);

        final back = build(children: children);
        await back.provider.loadProfile();
        expect(back.provider.activeChildId, 'b');
      },
    );
  });

  group('guest migration and conversion', () {
    test('a re-minted guest id inherits the old guest\'s selection', () async {
      SharedPreferences.setMockInitialValues({'active_child_guest_old': 'b'});
      // The children were migrated to the new guest id by AuthService.
      final harness = build(
        children: [
          child('a', userId: 'guest_new'),
          child('b', userId: 'guest_new', createdAt: DateTime(2026, 2, 1)),
        ],
        userId: 'guest_new',
        guest: true,
        migratedFromGuestId: 'guest_old',
      );

      await harness.provider.loadProfile();

      expect(harness.provider.activeChildId, 'b');
      expect(await savedFor('guest_new'), 'b');
    });

    test('a converted account keeps the guest selection when the child '
        'came along', () async {
      SharedPreferences.setMockInitialValues({'active_child_guest_abc': 'b'});
      // Backfill moved the children to the permanent account id.
      final harness = build(
        children: [
          child('a', userId: 'user-1'),
          child('b', userId: 'user-1', createdAt: DateTime(2026, 2, 1)),
        ],
        storedGuestId: 'guest_abc',
      );

      await harness.provider.loadProfile();

      expect(harness.provider.activeChildId, 'b');
      expect(await savedFor('user-1'), 'b');
    });

    test('a converted account falls back when the guest child did not '
        'come along', () async {
      SharedPreferences.setMockInitialValues({
        'active_child_guest_abc': 'lost',
      });
      final harness = build(
        children: [child('a', userId: 'user-1')],
        storedGuestId: 'guest_abc',
      );

      await harness.provider.loadProfile();

      expect(harness.provider.activeChildId, 'a');
      expect(await savedFor('user-1'), 'a');
    });

    test(
      'the account\'s own saved selection wins over an inherited one',
      () async {
        SharedPreferences.setMockInitialValues({
          'active_child_user-1': 'a',
          'active_child_guest_abc': 'b',
        });
        final harness = build(
          children: [
            child('a', userId: 'user-1'),
            child('b', userId: 'user-1', createdAt: DateTime(2026, 2, 1)),
          ],
          storedGuestId: 'guest_abc',
        );

        await harness.provider.loadProfile();

        expect(harness.provider.activeChildId, 'a');
      },
    );
  });
}

/// In-memory stand-in for the children table.
///
/// Storage order is deliberately the reverse of creation order, so a passing
/// test can never be relying on "the first row storage returned".
class _FakeLocalDb extends LocalDbService {
  _FakeLocalDb(List<ChildProfile> children) : _children = [...children];

  final List<ChildProfile> _children;

  @override
  Future<List<ChildProfile>> getChildren({
    String? userId,
    bool includeDeleted = false,
  }) async {
    final rows = userId == null
        ? _children
        : _children.where((c) => c.userId == userId);
    return rows.toList().reversed.toList();
  }

  @override
  Future<ChildProfile?> getChild(String id) async {
    for (final child in _children) {
      if (child.id == id) return child;
    }
    return null;
  }

  @override
  Future<void> upsertChild(
    ChildProfile profile, {
    String? ownerId,
    bool markPending = true,
  }) async {
    _children.removeWhere((c) => c.id == profile.id);
    _children.add(profile);
  }

  @override
  Future<void> deleteChild(String id) async {
    _children.removeWhere((c) => c.id == id);
  }

  @override
  Future<void> purgeChildScopedData(String childId) async {}
}

/// A repository writing straight to the fake table — no sync, no network.
class _FakeChildRepository extends ChildRepository {
  _FakeChildRepository(this._db, this._userId)
    : super(
        localDb: _db,
        authService: FakeAuthService(userId: _userId, loggedIn: true),
      );

  final _FakeLocalDb _db;
  final String _userId;
  int _sequence = 0;

  @override
  Future<ChildProfile> createChild({
    required String displayName,
    required DateTime birthDate,
    required String avatar,
    ChildSex? sex,
    bool musicEnabled = true,
    double musicVolume = 0.5,
    String musicCategory = 'calm',
    double sfxVolume = 0.7,
    bool vibrationEnabled = true,
    double promptSpeed = 1.0,
    bool sensoryPreferencesSet = false,
    RewardPreference rewardPreference = RewardPreference.bubbles,
    bool useRandomReward = false,
  }) async {
    final now = DateTime.now().add(Duration(seconds: _sequence++));
    final created = ChildProfile(
      id: 'new-child-$_sequence',
      userId: _userId,
      displayName: displayName,
      birthDate: birthDate,
      avatar: avatar,
      sex: sex,
      rewardPreference: rewardPreference,
      useRandomReward: useRandomReward,
      createdAt: now,
      updatedAt: now,
    );
    await _db.upsertChild(created);
    return created;
  }

  @override
  Future<void> deleteChild(String id) async {
    await _db.deleteChild(id);
    await _db.purgeChildScopedData(id);
  }
}
