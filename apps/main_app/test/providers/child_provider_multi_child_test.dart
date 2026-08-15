import 'package:aumazing/core/repositories/child_repository.dart';
import 'package:aumazing/core/services/local_db_service.dart';
import 'package:aumazing/core/services/sync_service.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';

import '../support/fake_auth.dart';

/// AUM-150 — multiple child profiles.
///
/// Covers loading several children, switching the active one, adding,
/// editing and deleting, and the cross-child isolation that has to hold
/// through all of it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ChildProfile child(
    String id, {
    String name = 'Child',
    String userId = 'user-1',
    DateTime? birthDate,
    DateTime? createdAt,
  }) =>
      ChildProfile(
        id: id,
        userId: userId,
        displayName: name,
        birthDate: birthDate ?? DateTime(2020, 1, 1),
        avatar: '🐻',
        createdAt: createdAt ?? DateTime(2026, 1, 1),
        updatedAt: createdAt ?? DateTime(2026, 1, 1),
      );

  ({ChildProvider provider, _FakeLocalDb db}) build({
    List<ChildProfile> children = const [],
    String userId = 'user-1',
    bool guest = false,
  }) {
    final db = _FakeLocalDb(children);
    final auth = guest
        ? FakeAuthService.guest(userId)
        : FakeAuthService.boundAccount(userId);
    return (
      provider: ChildProvider(
        localDb: db,
        authService: auth,
        childRepository: _FakeChildRepository(db, userId),
      ),
      db: db,
    );
  }

  group('loading', () {
    test('loads every child of the parent, oldest first', () async {
      final harness = build(children: [
        child('b', name: 'Bea', createdAt: DateTime(2026, 3, 1)),
        child('a', name: 'Ana', createdAt: DateTime(2026, 1, 1)),
        child('c', name: 'Cyd', createdAt: DateTime(2026, 5, 1)),
      ]);

      await harness.provider.loadProfile();

      expect(
        harness.provider.children.map((c) => c.displayName),
        ['Ana', 'Bea', 'Cyd'],
      );
      // Not "whatever storage returned first" — the oldest profile.
      expect(harness.provider.profile?.id, 'a');
      expect(harness.provider.isActive('a'), isTrue);
    });

    test('keeps the selected child active across a reload', () async {
      final harness = build(children: [child('a'), child('b')]);
      await harness.provider.loadProfile();
      await harness.provider.selectChild('b');

      await harness.provider.loadProfile();

      expect(harness.provider.activeChildId, 'b');
    });

    test('a guest parent sees their own children', () async {
      final harness = build(
        userId: 'guest_abc',
        guest: true,
        children: [child('g1', name: 'Guest Kid', userId: 'guest_abc')],
      );

      await harness.provider.loadProfile();

      expect(harness.provider.children, hasLength(1));
      expect(harness.provider.profile?.displayName, 'Guest Kid');
    });

    test('a bound account never sees another parent\'s children', () async {
      final harness = build(
        userId: 'user-1',
        children: [
          child('mine', userId: 'user-1'),
          child('theirs', userId: 'user-2'),
        ],
      );

      await harness.provider.loadProfile();

      expect(harness.provider.children.map((c) => c.id), ['mine']);
    });
  });

  group('selecting a child', () {
    test('switches the active child and reloads its own preferences',
        () async {
      SharedPreferences.setMockInitialValues({
        'theme_override_a': GameTheme.boy.slug,
        'language_a': 'ceb',
        'difficulty_override_a': 3,
        'world_override_a': WorldTheme.classic.slug,
        'language_b': 'fil',
        'difficulty_override_b': 1,
      });
      final harness = build(children: [child('a'), child('b')]);
      await harness.provider.loadProfile();

      expect(harness.provider.language, GameLanguage.cebuano);
      expect(harness.provider.difficultyOverride, 3);
      expect(harness.provider.isThemeOverridden, isTrue);

      await harness.provider.selectChild('b');

      expect(harness.provider.activeChildId, 'b');
      expect(harness.provider.language, GameLanguage.fromSlug('fil'));
      expect(harness.provider.difficultyOverride, 1);
      // Nothing of child A survives the switch.
      expect(harness.provider.isThemeOverridden, isFalse);
      expect(harness.provider.isWorldOverridden, isFalse);
      expect(harness.provider.hasCustomBackground, isFalse);
    });

    test('selecting an unknown child changes nothing', () async {
      final harness = build(children: [child('a')]);
      await harness.provider.loadProfile();

      expect(await harness.provider.selectChild('nope'), isFalse);
      expect(harness.provider.activeChildId, 'a');
    });

    test('per-child settings written for one child do not reach the other',
        () async {
      final harness = build(children: [child('a'), child('b')]);
      await harness.provider.loadProfile();
      await harness.provider.setDifficultyOverride(3);
      await harness.provider.setLanguage(GameLanguage.cebuano);

      await harness.provider.selectChild('b');
      expect(harness.provider.difficultyOverride, isNull);
      expect(harness.provider.language, GameLanguage.english);

      await harness.provider.selectChild('a');
      expect(harness.provider.difficultyOverride, 3);
      expect(harness.provider.language, GameLanguage.cebuano);
    });
  });

  group('adding a child', () {
    test('adds a separate record without touching the existing child',
        () async {
      final harness = build(children: [child('a', name: 'Ana')]);
      await harness.provider.loadProfile();

      final created = await harness.provider.addChild(
        displayName: 'Bea',
        birthDate: DateTime(2021, 6, 5),
        avatar: '🦊',
      );

      expect(harness.provider.children.map((c) => c.displayName),
          ['Ana', 'Bea']);
      expect(created.id, isNot('a'));
      expect(harness.db.children.map((c) => c.id), containsAll(['a', created.id]));
      expect(harness.db.childById('a')!.displayName, 'Ana');
    });

    test('does not take over the session unless the parent asks', () async {
      final harness = build(children: [child('a')]);
      await harness.provider.loadProfile();

      await harness.provider.addChild(
        displayName: 'Bea',
        birthDate: DateTime(2021, 6, 5),
        avatar: '🦊',
      );
      expect(harness.provider.activeChildId, 'a');

      final third = await harness.provider.addChild(
        displayName: 'Cyd',
        birthDate: DateTime(2019, 6, 5),
        avatar: '🐸',
        makeActive: true,
      );
      expect(harness.provider.activeChildId, third.id);
    });

    test('the first child of an empty account becomes active', () async {
      final harness = build();
      await harness.provider.loadProfile();

      final created = await harness.provider.addChild(
        displayName: 'Ana',
        birthDate: DateTime(2021, 6, 5),
        avatar: '🐻',
      );

      expect(harness.provider.activeChildId, created.id);
    });

    test('accepts plausible birth dates outside the old 2–6 range', () async {
      final harness = build();
      await harness.provider.loadProfile();
      final today = DateTime.now();

      final infant = await harness.provider.addChild(
        displayName: 'Baby',
        birthDate: DateTime(today.year - 1, today.month, today.day),
        avatar: '🐻',
      );
      final teen = await harness.provider.addChild(
        displayName: 'Teen',
        birthDate: DateTime(today.year - 14, today.month, today.day),
        avatar: '🦊',
      );

      expect(infant.ageYears(), 1);
      expect(teen.ageYears(), 14);
      expect(harness.provider.children, hasLength(2));
    });

    test("adding a child does not re-language the child still playing",
        () async {
      final harness = build(children: [child('a')]);
      await harness.provider.loadProfile();
      await harness.provider.setLanguage(GameLanguage.english);

      final created = await harness.provider.addChild(
        displayName: 'Bea',
        birthDate: DateTime(2021, 6, 5),
        avatar: '🦊',
      );
      await harness.provider.applyInitialPreferences(
        childId: created.id,
        language: GameLanguage.cebuano,
        voicePackId: 'ceb_lexianne',
      );

      expect(harness.provider.language, GameLanguage.english);

      await harness.provider.selectChild(created.id);
      expect(harness.provider.language, GameLanguage.cebuano);
      expect(harness.provider.voicePack.id, 'ceb_lexianne');
    });
  });

  group('editing a child', () {
    test('edits only the intended child', () async {
      final harness = build(children: [
        child('a', name: 'Ana'),
        child('b', name: 'Bea', createdAt: DateTime(2026, 2, 1)),
      ]);
      await harness.provider.loadProfile();

      final updated = await harness.provider.editChild(
        'b',
        displayName: 'Beatriz',
        birthDate: DateTime(2015, 3, 4),
      );

      expect(updated!.displayName, 'Beatriz');
      expect(harness.db.childById('b')!.displayName, 'Beatriz');
      expect(harness.db.childById('b')!.birthDate, DateTime(2015, 3, 4));
      // The active child (a) is untouched, in memory and in storage.
      expect(harness.provider.profile!.displayName, 'Ana');
      expect(harness.db.childById('a')!.displayName, 'Ana');
      expect(harness.db.childById('a')!.birthDate, DateTime(2020, 1, 1));
    });

    test('editing the active child refreshes what the app shows', () async {
      final harness = build(children: [child('a', name: 'Ana')]);
      await harness.provider.loadProfile();

      await harness.provider.editChild('a', displayName: 'Anna');

      expect(harness.provider.profile!.displayName, 'Anna');
      expect(harness.provider.children.single.displayName, 'Anna');
    });

    test('accepts a birth date outside the old 2–6 range', () async {
      final harness = build(children: [child('a')]);
      await harness.provider.loadProfile();

      final updated =
          await harness.provider.editChild('a', birthDate: DateTime(2014, 2, 2));

      expect(updated!.birthDate, DateTime(2014, 2, 2));
    });
  });

  group('deleting a child', () {
    test('deleting a non-active child leaves the active one alone', () async {
      final harness = build(children: [
        child('a', name: 'Ana'),
        child('b', name: 'Bea', createdAt: DateTime(2026, 2, 1)),
      ]);
      await harness.provider.loadProfile();

      final outcome = await harness.provider.deleteChild('b');

      expect(outcome, ChildDeletionOutcome.otherChildDeleted);
      expect(harness.provider.activeChildId, 'a');
      expect(harness.provider.children.map((c) => c.id), ['a']);
      expect(harness.db.deleted, ['b']);
      expect(harness.db.childById('a'), isNotNull);
    });

    test('deleting the active child promotes another one', () async {
      final harness = build(children: [
        child('a', name: 'Ana'),
        child('b', name: 'Bea', createdAt: DateTime(2026, 2, 1)),
      ]);
      await harness.provider.loadProfile();

      final outcome = await harness.provider.deleteChild('a');

      expect(outcome, ChildDeletionOutcome.switchedToAnotherChild);
      expect(harness.provider.activeChildId, 'b');
      expect(harness.provider.children.map((c) => c.id), ['b']);
    });

    test('deleting the last child leaves the parent with no profile',
        () async {
      final harness = build(children: [child('a')]);
      await harness.provider.loadProfile();

      final outcome = await harness.provider.deleteChild('a');

      expect(outcome, ChildDeletionOutcome.noChildrenLeft);
      expect(harness.provider.hasProfile, isFalse);
      expect(harness.provider.children, isEmpty);
    });

    test('removes the deleted child\'s stored preferences and progress',
        () async {
      SharedPreferences.setMockInitialValues({
        'theme_override_b': GameTheme.boy.slug,
        'language_b': 'ceb',
        'difficulty_override_b': 2,
        'screen_time_limit_b': 30,
        'ai_prediction_b': '{}',
        'path_progress_b': <String>['match_it'],
        'language_a': 'fil',
      });
      final harness = build(children: [
        child('a'),
        child('b', createdAt: DateTime(2026, 2, 1)),
      ]);
      await harness.provider.loadProfile();

      await harness.provider.deleteChild('b');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.endsWith('_b')), isEmpty);
      // The surviving child keeps everything.
      expect(prefs.getString('language_a'), 'fil');
    });

    test('a re-added child does not inherit the deleted child\'s settings',
        () async {
      SharedPreferences.setMockInitialValues({'difficulty_override_a': 3});
      final harness = build(children: [child('a')]);
      await harness.provider.loadProfile();
      expect(harness.provider.difficultyOverride, 3);

      await harness.provider.deleteChild('a');
      final replacement = await harness.provider.addChild(
        displayName: 'New',
        birthDate: DateTime(2021, 1, 1),
        avatar: '🐻',
      );

      expect(harness.provider.activeChildId, replacement.id);
      expect(harness.provider.difficultyOverride, isNull);
      expect(harness.provider.language, GameLanguage.english);
    });
  });

  group('offline behaviour', () {
    test('creates, edits and deletes locally while offline, queued for sync',
        () async {
      final db = _FakeLocalDb([]);
      final sync = _RecordingSyncService();
      final provider = ChildProvider(
        localDb: db,
        authService: FakeAuthService.guest('guest_abc'),
        // The real repository, with only the network call stubbed out — the
        // offline path is local write first, sync request after.
        childRepository: ChildRepository(
          localDb: db,
          authService: FakeAuthService.guest('guest_abc'),
          overrideSyncService: sync,
        ),
      );
      await provider.loadProfile();

      final created = await provider.addChild(
        displayName: 'Ana',
        birthDate: DateTime(2021, 1, 1),
        avatar: '🐻',
      );
      expect(db.childById(created.id), isNotNull);
      expect(db.pending[created.id], isTrue,
          reason: 'a new child must be queued for the next sync');

      await provider.editChild(created.id, displayName: 'Anna');
      expect(db.childById(created.id)!.displayName, 'Anna');
      expect(db.pending[created.id], isTrue);

      await provider.deleteChild(created.id);
      expect(db.deleted, [created.id]);
      expect(provider.children, isEmpty);
      // Sync was asked for after each write; offline it is a no-op that the
      // queued rows survive.
      expect(sync.syncRequests, 3);
    });
  });
}

/// In-memory stand-in for the children table.
class _FakeLocalDb extends LocalDbService {
  _FakeLocalDb(List<ChildProfile> children) : _children = [...children];

  final List<ChildProfile> _children;
  final List<String> deleted = [];
  final Map<String, bool> pending = {};

  List<ChildProfile> get children => List.unmodifiable(_children);

  ChildProfile? childById(String id) {
    for (final child in _children) {
      if (child.id == id) return child;
    }
    return null;
  }

  @override
  Future<List<ChildProfile>> getChildren({
    String? userId,
    bool includeDeleted = false,
  }) async {
    final rows = userId == null
        ? _children
        : _children.where((c) => c.userId == userId);
    // Storage order is deliberately the opposite of creation order, so a test
    // that passes cannot be relying on "the first row".
    return rows.toList().reversed.toList();
  }

  @override
  Future<ChildProfile?> getChild(String id) async => childById(id);

  @override
  Future<void> upsertChild(
    ChildProfile profile, {
    String? ownerId,
    bool markPending = true,
  }) async {
    _children.removeWhere((c) => c.id == profile.id);
    _children.add(profile);
    pending[profile.id] = markPending;
  }

  @override
  Future<void> deleteChild(String id) async {
    deleted.add(id);
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
  Future<ChildProfile> updateChild(
    ChildProfile child, {
    String? displayName,
    DateTime? birthDate,
    String? avatar,
    ChildSex? sex,
    bool? musicEnabled,
    bool? vibrationEnabled,
    RewardPreference? rewardPreference,
    bool? useRandomReward,
  }) async {
    final updated = child.copyWith(
      displayName: displayName,
      birthDate: birthDate,
      avatar: avatar,
      sex: sex,
      rewardPreference: rewardPreference,
      useRandomReward: useRandomReward,
    );
    await _db.upsertChild(updated);
    return updated;
  }

  @override
  Future<void> deleteChild(String id) async {
    await _db.deleteChild(id);
    await _db.purgeChildScopedData(id);
  }
}

/// Stands in for the network leg of a sync: records that one was requested.
class _RecordingSyncService extends SyncService {
  int syncRequests = 0;

  @override
  Future<void> syncNow() async {
    syncRequests++;
  }
}
