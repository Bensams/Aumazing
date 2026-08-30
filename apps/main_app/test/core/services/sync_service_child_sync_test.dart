import 'dart:async';

import 'package:aumazing/core/services/connectivity_service.dart';
import 'package:aumazing/core/services/local_db_service.dart';
import 'package:aumazing/core/services/supabase_service.dart';
import 'package:aumazing/core/services/sync_service.dart';
import 'package:aumazing/core/sync/sync_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SyncService child sync', () {
    late _SyncTestLocalDb localDb;
    late _FakeSupabaseService supabase;
    late SyncService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      localDb = _SyncTestLocalDb();
      supabase = _FakeSupabaseService();
      service = SyncService(
        localDb: localDb,
        supabase: supabase,
        connectivity: _FakeConnectivityService(),
      );

      await localDb.seedChildRow({
        'id': 'sync-child',
        'user_id': 'parent-1',
        'display_name': 'Mika',
        'birth_date': '2022-04-20',
        'avatar': 'lion',
        'music_enabled': 1,
        'vibration_enabled': 1,
        // Non-default character and costume: the whole point of AUM-328 is
        // that these reach the cloud rather than being dropped on the way.
        'character_id': 'lexianne',
        'equipped_costume': 'teddy',
        'comfort_settings': null,
        'sync_status': SyncStatus.pending.value,
        'last_synced_at': null,
        'deleted_at': null,
        'updated_at': '2026-04-21T00:00:00.000',
        'local_created_at': '2026-04-20T12:00:00.000',
        'owner_id': 'parent-1',
      });
      await localDb.seedChildRow({
        'id': 'legacy-child',
        'user_id': 'parent-1',
        'display_name': 'Legacy Child',
        'birth_date': null,
        'avatar': 'lion',
        'music_enabled': 1,
        'vibration_enabled': 1,
        'comfort_settings': null,
        'sync_status': SyncStatus.pending.value,
        'last_synced_at': null,
        'deleted_at': null,
        'updated_at': '2026-04-21T00:00:00.000',
        'local_created_at': '2026-04-20T11:00:00.000',
        'owner_id': 'parent-1',
      });
    });

    tearDown(() async {
      await localDb.close();
    });

    test(
      'syncs pending child rows and maps them to public.children fields',
      () async {
        await service.startSync();

        // Legacy rows (no birth date) still sync — eligibility is decided by
        // name/user/guest-ownership only, so nothing is stranded local-only.
        // Ordered by local_created_at, so the legacy row goes up first.
        expect(supabase.upsertedChildren, hasLength(2));
        expect(supabase.upsertedChildren.first, {
          'id': 'legacy-child',
          'parent_user_id': 'parent-1',
          'display_name': 'Legacy Child',
          'birth_date': null,
          'avatar': 'lion',
          'sex': null,
          'music_enabled': true,
          'music_volume': 0.5,
          'music_category': 'soft_relaxing',
          'sfx_volume': 0.7,
          'vibration_enabled': true,
          'animation_intensity': 1.0,
          'prompt_speed': 1.0,
          'sensory_preferences_set': false,
          'reward_preference': 'bubbles',
          'use_random_reward': false,
          'character_id': 'bps',
          'equipped_costume': 'none',
          'created_at': '2026-04-20T11:00:00.000',
          'updated_at': '2026-04-21T00:00:00.000',
        });
        expect(supabase.upsertedChildren.last, {
          'id': 'sync-child',
          'parent_user_id': 'parent-1',
          'display_name': 'Mika',
          'birth_date': '2022-04-20',
          'avatar': 'lion',
          'sex': null,
          'music_enabled': true,
          'music_volume': 0.5,
          'music_category': 'soft_relaxing',
          'sfx_volume': 0.7,
          'vibration_enabled': true,
          'animation_intensity': 1.0,
          'prompt_speed': 1.0,
          'sensory_preferences_set': false,
          'reward_preference': 'bubbles',
          'use_random_reward': false,
          // The regression this test now guards: the old hand-written mapper
          // sent six columns and silently dropped these two, so a child's
          // character and costume never left the device (AUM-328).
          'character_id': 'lexianne',
          'equipped_costume': 'teddy',
          'created_at': '2026-04-20T12:00:00.000',
          'updated_at': '2026-04-21T00:00:00.000',
        });
      },
    );

    test('resetStuckSyncing recovers records stranded mid-sync so they are '
        'picked up again', () async {
      final db = await localDb.database;
      await db.insert(LocalTables.gameSessions, {
        'id': 'stuck-session',
        'sync_status': SyncStatus.syncing.value,
        'local_created_at': '2026-04-20T12:00:00.000',
      });

      expect(
        await localDb.getPendingRecords(LocalTables.gameSessions),
        isEmpty,
      );

      final recovered = await localDb.resetStuckSyncing();

      expect(recovered, 1);
      final pending = await localDb.getPendingRecords(LocalTables.gameSessions);
      expect(pending, hasLength(1));
      expect(pending.single['id'], 'stuck-session');
    });

    test('falls back to per-record upserts when a batch fails, so one bad row '
        'does not poison the batch', () async {
      final db = await localDb.database;
      await db.insert(LocalTables.gameSessions, {
        'id': 'good-session',
        'sync_status': SyncStatus.pending.value,
        'local_created_at': '2026-04-20T12:00:00.000',
      });
      await db.insert(LocalTables.gameSessions, {
        'id': 'bad-session',
        'sync_status': SyncStatus.pending.value,
        'local_created_at': '2026-04-20T12:01:00.000',
      });
      supabase.failIds.add('bad-session');

      await service.startSync();

      final rows = await db.query(LocalTables.gameSessions);
      final byId = {for (final r in rows) r['id']: r};
      expect(byId['good-session']!['sync_status'], SyncStatus.synced.value);
      expect(byId['bad-session']!['sync_status'], SyncStatus.failed.value);
      expect(byId['bad-session']!['sync_attempts'], 1);
      expect(service.currentState.failedCount, 1);
      expect(service.currentState.lastSuccessfulSync, isFalse);
    });

    // Was: "…and never overwrites existing local rows". Insert-only
    // hydration is not a conflict rule: an edit made on another device could
    // never arrive, so this device kept a stale copy forever and whichever
    // device pushed last won regardless of which edit was newer. AUM-158
    // replaces it with a stated rule — the later updated_at wins, ties go
    // to local. See hydrate_conflict_rule_test.dart for the rule itself.
    test(
      'hydrateFromCloud pulls remote-only rows and takes the newer version',
      () async {
        final db = await localDb.database;
        // Local copy is older than the cloud's, so the cloud version wins.
        await db.insert(LocalTables.assessmentRuns, {
          'id': 'run-local',
          'child_id': 'sync-child',
          'type': 'pre',
          'started_at': '2026-04-20T13:00:00.000',
          'status': 'in_progress',
          'sync_status': SyncStatus.pending.value,
          'updated_at': '2026-04-20T13:00:00.000',
          'local_created_at': '2026-04-20T13:00:00.000',
        });

        supabase.remoteRows[RemoteTables.assessmentRuns] = [
          {
            // Same id as the local row, different content — must lose.
            // Spelled in the CLOUD's columns (assessment_type / ended_at /
            // completed), which is what hydration actually receives; the
            // fixture used to use the local spellings and so agreed with a
            // download mapper that was reading fields the cloud has never
            // had.
            'id': 'run-local',
            'child_id': 'sync-child',
            'assessment_type': 'pre_assessment',
            'started_at': '2026-04-20T13:00:00.000',
            'ended_at': '2026-04-20T13:20:00.000',
            'completed': true,
            'created_at': '2026-04-20T13:00:00.000',
            'updated_at': '2026-04-20T13:20:00.000',
          },
          {
            // Cloud-only row (e.g. from another device) — must be pulled
            'id': 'run-remote',
            'child_id': 'sync-child',
            'assessment_type': 'post_assessment',
            'started_at': '2026-05-01T10:00:00.000',
            'ended_at': '2026-05-01T10:15:00.000',
            'completed': true,
            'created_at': '2026-05-01T10:00:00.000',
            'updated_at': '2026-05-01T10:15:00.000',
          },
        ];

        final pulled = await service.hydrateFromCloud();

        expect(pulled, 2, reason: 'one updated, one inserted');
        final rows = await db.query(LocalTables.assessmentRuns);
        final byId = {for (final r in rows) r['id']: r};
        expect(byId, hasLength(2));
        // The cloud held a later version of this run (completed at 13:20
        // against the local 13:00), so it replaces the stale local copy.
        expect(byId['run-local']!['status'], 'completed');
        expect(byId['run-local']!['type'], 'pre');
        expect(byId['run-local']!['completed_at'], '2026-04-20T13:20:00.000');
        expect(byId['run-local']!['sync_status'], SyncStatus.synced.value);
        // Remote row inserted as already-synced
        expect(byId['run-remote']!['status'], 'completed');
        expect(byId['run-remote']!['type'], 'post');
        expect(byId['run-remote']!['sync_status'], SyncStatus.synced.value);
      },
    );

    test(
      'hydrateFromCloud expands one cloud result into a row per mini-game',
      () async {
        final db = await localDb.database;
        supabase.remoteRows[RemoteTables.assessmentRuns] = [
          {
            'id': 'run-post',
            'child_id': 'sync-child',
            'assessment_type': 'post_assessment',
            'started_at': '2026-05-01T10:00:00.000',
            'ended_at': '2026-05-01T10:15:00.000',
            'completed': true,
            'created_at': '2026-05-01T10:00:00.000',
            'updated_at': '2026-05-01T10:15:00.000',
          },
        ];
        // The cloud keeps ONE row per run, with the battery's four ordinal
        // levels and the per-game detail inside summary_json.
        supabase.remoteRows[RemoteTables.assessmentResults] = [
          {
            'id': 'run-post',
            'assessment_run_id': 'run-post',
            'child_id': 'sync-child',
            'assessment_date': '2026-05-01',
            'communication_level': 1,
            'social_level': 2,
            'play_level': 0,
            'attention_level': 2,
            'notes': 'Turn-taking is a strength.',
            'summary_json': {
              'model_source': 'rubric_based',
              'xgboost_ready': true,
              'sensory_preference_label': 'No Sensory Support Needed',
              'recommended_module': 'Play Skills Starter Module',
              'per_game': [
                {
                  'game_id': 'match_it',
                  'score': 9,
                  'total_items': 10,
                  'error_count': 1,
                  'random_touch_count': 2,
                  'avg_response_time_ms': 2400,
                },
                {
                  'game_id': 'copy_me',
                  'score': 7,
                  'total_items': 8,
                  'error_count': 0,
                  'random_touch_count': 1,
                  'avg_response_time_ms': 2100,
                },
              ],
            },
            'created_at': '2026-05-01T10:15:00.000',
            'updated_at': '2026-05-01T10:15:00.000',
          },
        ];

        await service.hydrateFromCloud();

        final rows = await db.query(LocalTables.assessmentResults);
        expect(rows, hasLength(2), reason: 'one local row per mini-game');
        final byGame = {for (final r in rows) r['game_id']: r};
        expect(byGame.keys.toSet(), {'match_it', 'copy_me'});

        final matchIt = byGame['match_it']!;
        expect(matchIt['score'], 9);
        expect(matchIt['total_items'], 10);
        expect(matchIt['error_count'], 1);
        expect(matchIt['random_touch_count'], 2);
        expect(matchIt['avg_response_time_ms'], 2400);
        // The type lives on the run, not on the result.
        expect(matchIt['type'], 'post');
        // Ordinals map back to the labels the rubric wrote.
        expect(matchIt['communication_label'], 'Emerging');
        expect(matchIt['social_interaction_label'], 'Strength');
        expect(matchIt['play_skills_label'], 'Needs Support');
        expect(matchIt['behavior_attention_label'], 'Sustained Attention');
        expect(matchIt['overall_summary'], 'Turn-taking is a strength.');
        expect(matchIt['recommended_module'], 'Play Skills Starter Module');
        expect(matchIt['sync_status'], SyncStatus.synced.value);
        // The labels describe the battery, so every game of the run shares
        // them.
        expect(byGame['copy_me']!['social_interaction_label'], 'Strength');
      },
    );

    test(
      'hydrateFromCloud reads summary_json that was stored double-encoded',
      () async {
        final db = await localDb.database;
        supabase.remoteRows[RemoteTables.assessmentRuns] = [
          {
            'id': 'run-pre',
            'child_id': 'sync-child',
            'assessment_type': 'pre_assessment',
            'started_at': '2026-05-01T10:00:00.000',
            'ended_at': '2026-05-01T10:15:00.000',
            'completed': true,
            'created_at': '2026-05-01T10:00:00.000',
            'updated_at': '2026-05-01T10:15:00.000',
          },
        ];
        // Rows uploaded before the jsonb double-encoding fix are stored as a
        // jsonb STRING holding JSON. They are already in the live database,
        // so hydration has to read them.
        supabase.remoteRows[RemoteTables.assessmentResults] = [
          {
            'id': 'run-pre',
            'assessment_run_id': 'run-pre',
            'child_id': 'sync-child',
            'assessment_date': '2026-05-01',
            'communication_level': null,
            'social_level': null,
            'play_level': null,
            'attention_level': null,
            'summary_json':
                '{"per_game":[{"game_id":"match_it","score":4,'
                '"total_items":4,"error_count":3,"random_touch_count":0,'
                '"avg_response_time_ms":4560}]}',
            'created_at': '2026-05-01T10:15:00.000',
            'updated_at': '2026-05-01T10:15:00.000',
          },
        ];

        await service.hydrateFromCloud();

        final rows = await db.query(LocalTables.assessmentResults);
        expect(rows, hasLength(1));
        expect(rows.single['game_id'], 'match_it');
        expect(rows.single['score'], 4);
        expect(rows.single['type'], 'pre');
        // Never scored in the cloud, so no label is invented here.
        expect(rows.single['communication_label'], isNull);
      },
    );

    test(
      'hydrateFromCloud drops a result it cannot expand rather than '
      'inventing a placeholder',
      () async {
        final db = await localDb.database;
        supabase.remoteRows[RemoteTables.assessmentRuns] = [
          {
            'id': 'run-empty',
            'child_id': 'sync-child',
            'assessment_type': 'pre_assessment',
            'started_at': '2026-05-01T10:00:00.000',
            'ended_at': '2026-05-01T10:15:00.000',
            'completed': true,
            'created_at': '2026-05-01T10:00:00.000',
            'updated_at': '2026-05-01T10:15:00.000',
          },
        ];
        supabase.remoteRows[RemoteTables.assessmentResults] = [
          // No per_game: nothing says which games this summarised.
          {
            'id': 'run-empty',
            'assessment_run_id': 'run-empty',
            'child_id': 'sync-child',
            'assessment_date': '2026-05-01',
            'summary_json': const <String, dynamic>{},
            'created_at': '2026-05-01T10:15:00.000',
            'updated_at': '2026-05-01T10:15:00.000',
          },
          // No hydrated run: its local FK could not be satisfied anyway.
          {
            'id': 'orphan',
            'assessment_run_id': 'run-that-was-never-pulled',
            'child_id': 'sync-child',
            'assessment_date': '2026-05-01',
            'summary_json': {
              'per_game': [
                {'game_id': 'match_it', 'score': 1, 'total_items': 1},
              ],
            },
            'created_at': '2026-05-01T10:15:00.000',
            'updated_at': '2026-05-01T10:15:00.000',
          },
        ];

        await service.hydrateFromCloud();

        // The old mapper wrote a game_id 'unknown', type 'pre', score 0 row
        // for each of these, which then showed up in the parent's history as
        // an assessment the child never sat.
        expect(await db.query(LocalTables.assessmentResults), isEmpty);
        // The run itself still hydrates, so the play is not lost.
        expect(await db.query(LocalTables.assessmentRuns), hasLength(1));
      },
    );

    test('hydrateFromCloud never resurrects a child deleted locally', () async {
      // Deleted on this device; the cloud row lives on until the deletion
      // is propagated, so hydration is the moment it could come back.
      await localDb.deleteChild('sync-child');
      supabase.remoteChildren.add({
        'id': 'sync-child',
        'parent_user_id': 'parent-1',
        'display_name': 'Mika',
        'birth_date': '2022-04-20',
        'created_at': '2026-04-20T12:00:00.000',
        'updated_at': '2026-04-20T12:00:00.000',
      });
      supabase.remoteRows[RemoteTables.assessmentRuns] = [
        {
          'id': 'run-of-deleted-child',
          'child_id': 'sync-child',
          'type': 'pre',
          'started_at': '2026-05-01T10:00:00.000',
          'status': 'completed',
          'created_at': '2026-05-01T10:00:00.000',
          'updated_at': '2026-05-01T10:00:00.000',
        },
      ];

      await service.hydrateFromCloud();

      expect(await localDb.getChild('sync-child'), isNull);
      expect(await localDb.getLocallyDeletedChildIds(), {'sync-child'});
      // Nor is the deleted child's cloud progress pulled back down.
      final db = await localDb.database;
      expect(await db.query(LocalTables.assessmentRuns), isEmpty);
    });

    test('hydrateFromCloud runs once per user unless forced', () async {
      supabase.remoteRows[RemoteTables.assessmentRuns] = [
        {
          'id': 'run-once',
          'child_id': 'sync-child',
          'type': 'pre',
          'started_at': '2026-04-20T13:00:00.000',
          'status': 'completed',
          'created_at': '2026-04-20T13:00:00.000',
          'updated_at': '2026-04-20T13:00:00.000',
        },
      ];

      expect(await service.hydrateFromCloud(), 1);
      // Second call is a no-op (flag set)
      expect(await service.hydrateFromCloud(), 0);
      // Forced re-run fetches again, but existing rows still win
      expect(await service.hydrateFromCloud(force: true), 0);
    });
  });
}

class _SyncTestLocalDb extends LocalDbService {
  Database? _testDatabase;

  @override
  Future<Database> get database async {
    _testDatabase ??= await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE ${LocalTables.children} (
            id TEXT PRIMARY KEY,
            user_id TEXT,
            display_name TEXT NOT NULL,
            birth_date TEXT,
            avatar TEXT NOT NULL,
            sex TEXT,
            music_enabled INTEGER NOT NULL DEFAULT 1,
            music_volume REAL NOT NULL DEFAULT 0.5,
            music_category TEXT NOT NULL DEFAULT 'soft_relaxing',
            sfx_volume REAL NOT NULL DEFAULT 0.7,
            vibration_enabled INTEGER NOT NULL DEFAULT 1,
            animation_intensity REAL NOT NULL DEFAULT 1.0,
            prompt_speed REAL NOT NULL DEFAULT 1.0,
            sensory_preferences_set INTEGER NOT NULL DEFAULT 0,
            reward_preference TEXT NOT NULL DEFAULT 'bubbles',
            use_random_reward INTEGER NOT NULL DEFAULT 0,
            character_id TEXT NOT NULL DEFAULT 'bps',
            equipped_costume TEXT NOT NULL DEFAULT 'none',
            comfort_settings TEXT,
            sync_status TEXT NOT NULL DEFAULT 'pending',
            sync_error TEXT,
            sync_attempts INTEGER NOT NULL DEFAULT 0,
            last_synced_at TEXT,
            deleted_at TEXT,
            updated_at TEXT NOT NULL,
            local_created_at TEXT NOT NULL,
            owner_id TEXT
          )
        ''');

        // Full schema for assessment runs so hydration can be exercised
        await db.execute('''
          CREATE TABLE ${LocalTables.assessmentRuns} (
            id TEXT PRIMARY KEY,
            child_id TEXT NOT NULL,
            type TEXT NOT NULL,
            started_at TEXT NOT NULL,
            completed_at TEXT,
            status TEXT NOT NULL DEFAULT 'in_progress',
            sync_status TEXT NOT NULL DEFAULT 'pending',
            sync_error TEXT,
            sync_attempts INTEGER NOT NULL DEFAULT 0,
            last_synced_at TEXT,
            deleted_at TEXT,
            updated_at TEXT NOT NULL,
            local_created_at TEXT NOT NULL,
            owner_id TEXT
          )
        ''');

        // Full schema for assessment results too: hydration expands one
        // cloud row into a row per mini-game, so the stub skeleton below
        // (an id and sync columns) cannot hold what it produces.
        await db.execute('''
          CREATE TABLE ${LocalTables.assessmentResults} (
            id TEXT PRIMARY KEY,
            child_id TEXT NOT NULL,
            assessment_run_id TEXT,
            game_id TEXT NOT NULL,
            type TEXT NOT NULL,
            score INTEGER NOT NULL,
            total_items INTEGER NOT NULL,
            error_count INTEGER NOT NULL,
            random_touch_count INTEGER NOT NULL DEFAULT 0,
            avg_response_time_ms INTEGER NOT NULL,
            completed_at TEXT,
            raw_metrics TEXT,
            play_skills_label TEXT,
            communication_label TEXT,
            social_interaction_label TEXT,
            behavior_attention_label TEXT,
            sensory_preference_label TEXT,
            recommended_module TEXT,
            overall_summary TEXT,
            model_source TEXT DEFAULT 'rubric_based',
            xgboost_ready INTEGER DEFAULT 1,
            sync_status TEXT NOT NULL DEFAULT 'pending',
            sync_error TEXT,
            sync_attempts INTEGER NOT NULL DEFAULT 0,
            last_synced_at TEXT,
            deleted_at TEXT,
            updated_at TEXT NOT NULL,
            local_created_at TEXT NOT NULL,
            owner_id TEXT
          )
        ''');

        for (final table in SyncOrder.dependencyOrder.where(
          (table) =>
              table != LocalTables.children &&
              table != LocalTables.assessmentRuns &&
              table != LocalTables.assessmentResults,
        )) {
          await db.execute('''
            CREATE TABLE $table (
              id TEXT PRIMARY KEY,
              sync_status TEXT NOT NULL DEFAULT 'pending',
              sync_error TEXT,
              sync_attempts INTEGER NOT NULL DEFAULT 0,
              deleted_at TEXT,
              local_created_at TEXT NOT NULL,
              last_synced_at TEXT
            )
          ''');
        }
      },
    );

    return _testDatabase!;
  }

  Future<void> seedChildRow(Map<String, Object?> row) async {
    final db = await database;
    await db.insert(LocalTables.children, row);
  }
}

class _FakeSupabaseService implements SupabaseService {
  final List<Map<String, dynamic>> upsertedChildren = [];

  /// Record ids that reject any upsert containing them (poison rows)
  final Set<String> failIds = {};

  /// Remote rows served by fetchRowsByColumn, keyed by remote table name
  final Map<String, List<Map<String, dynamic>>> remoteRows = {};

  @override
  Future<List<Map<String, dynamic>>> fetchRowsByColumn(
    String remoteTable,
    String column,
    List<String> values,
  ) async => [
    for (final r in remoteRows[remoteTable] ?? const [])
      if (values.contains(r[column])) Map<String, dynamic>.from(r),
  ];

  @override
  Future<void> upsertBatch(
    String remoteTable,
    List<Map<String, dynamic>> records,
  ) async {
    if (records.any((r) => failIds.contains(r['id']))) {
      throw Exception('upsert rejected');
    }
    if (remoteTable == RemoteTables.children) {
      upsertedChildren.addAll(records.map((r) => Map<String, dynamic>.from(r)));
    }
  }

  @override
  bool get isAuthenticated => true;

  @override
  String? get currentUserId => 'parent-1';

  @override
  Future<void> upsertChild(Map<String, dynamic> data, String id) async {
    upsertedChildren.add(Map<String, dynamic>.from(data));
  }

  /// Children the cloud reports for the parent.
  final List<Map<String, dynamic>> remoteChildren = [];

  @override
  Future<List<Map<String, dynamic>>> getChildren(String userId) async => [
    for (final c in remoteChildren) Map<String, dynamic>.from(c),
  ];

  @override
  Future<void> upsertAssessmentRun(
    Map<String, dynamic> data,
    String id,
  ) async {}

  @override
  Future<void> upsertGameSession(Map<String, dynamic> data, String id) async {}

  @override
  Future<void> upsertGameSessionsBatch(
    List<Map<String, dynamic>> records,
  ) async {}

  @override
  Future<void> upsertGameRound(Map<String, dynamic> data, String id) async {}

  @override
  Future<void> upsertGameRoundsBatch(
    List<Map<String, dynamic>> records,
  ) async {}

  @override
  Future<void> upsertSessionEvent(Map<String, dynamic> data, String id) async {}

  @override
  Future<void> upsertCaregiverQuestionnaire(
    Map<String, dynamic> data,
    String id,
  ) async {}

  @override
  Future<void> upsertAssessmentResult(
    Map<String, dynamic> data,
    String id,
  ) async {}

  @override
  Future<void> upsertAssessmentResultsBatch(
    List<Map<String, dynamic>> records,
  ) async {}

  @override
  Future<void> upsertModuleRecommendation(
    Map<String, dynamic> data,
    String id,
  ) async {}

  @override
  Future<void> upsertAssessmentComparison(
    Map<String, dynamic> data,
    String id,
  ) async {}

  @override
  Future<void> upsertSensoryConsent(
    Map<String, dynamic> data,
    String id,
  ) async {}

  @override
  Future<void> upsertSensoryRoundMetrics(
    Map<String, dynamic> data,
    String id,
  ) async {}

  @override
  Future<void> upsertSensoryPreferences(
    Map<String, dynamic> data,
    String id,
  ) async {}

  @override
  Future<List<Map<String, dynamic>>> fetchLearningModules() async => const [];

  @override
  Future<List<Map<String, dynamic>>> fetchModulePaths() async => const [];

  @override
  Future<List<Map<String, dynamic>>> fetchModulePathItems() async => const [];

  @override
  Future<DateTime?> getRemoteUpdatedAt(String table, String id) async => null;

  @override
  Future<void> softDeleteRemote(String table, String id) async {}
}

class _FakeConnectivityService implements ConnectivityService {
  @override
  bool get isOnline => true;

  @override
  bool get isOffline => false;

  @override
  Stream<bool> get onConnectivityChanged => const Stream<bool>.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> checkConnectivity() async => true;

  @override
  void dispose() {}
}
