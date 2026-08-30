import 'dart:async';

import 'package:aumazing/core/services/connectivity_service.dart';
import 'package:aumazing/core/services/local_db_service.dart';
import 'package:aumazing/core/services/supabase_service.dart';
import 'package:aumazing/core/services/sync_service.dart';
import 'package:aumazing/core/sync/sync_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The local SQLite schema and the cloud Postgres schema were designed
/// separately, and for a long time the upload mappers spoke the local
/// vocabulary at a remote table that had never heard of it. Every
/// assessment upload was rejected — `assessment_runs` sent `type` /
/// `completed_at` / `status` where the cloud has `assessment_type` /
/// `ended_at` / `completed`, and `assessment_results` shared only three
/// column names with its remote counterpart. Nothing surfaced the failure
/// except a permanent "some changes haven't synced yet" banner, because a
/// rejected row simply stays pending and is retried forever.
///
/// These tests pin the payloads that actually go over the wire to the
/// columns and CHECK vocabularies the cloud schema really has. They fail
/// loudly if a mapper drifts back to local field names.
///
/// The column lists below are copied from the live database; a mapper that
/// invents a column outside them is exactly the bug this guards against.
const _cloudAssessmentRunColumns = {
  'id',
  'child_id',
  'assessment_type',
  'baseline_assessment_run_id',
  'related_recommendation_id',
  'assessor_type',
  'started_at',
  'ended_at',
  'age_months_at_assessment',
  'completed',
  'version',
  'notes',
  'created_at',
  'updated_at',
};

const _cloudAssessmentResultColumns = {
  'id',
  'assessment_run_id',
  'child_id',
  'assessment_date',
  'baseline_result_id',
  'communication_score',
  'social_score',
  'play_score',
  'attention_score',
  'sensory_score',
  'social_communication_score',
  'rrb_flexibility_score',
  'support_band_social',
  'support_band_rrb',
  'overall_support_band',
  'overall_band',
  'screening_flag',
  'requires_followup',
  'improvement_percent',
  'progress_status',
  'summary_json',
  'change_summary_json',
  'notes',
  'created_at',
  'updated_at',
  'communication_level',
  'social_level',
  'play_level',
  'attention_level',
  'communication_confidence',
  'social_confidence',
  'play_confidence',
  'attention_confidence',
};

const _cloudRecommendationColumns = {
  'id',
  'child_id',
  'source_assessment_id',
  'model_version_id',
  'recommended_by',
  'recommended_path_json',
  'top_module',
  'confidence',
  'explanation_json',
  'input_snapshot_json',
  'accepted_by_parent',
  'status',
  'created_at',
  'updated_at',
};

/// CHECK (assessment_type IN (...)) on public.assessment_runs.
const _cloudAssessmentTypes = {
  'pre_assessment',
  'post_assessment',
  'follow_up',
  'progress_check',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ContractLocalDb localDb;
  late _CapturingSupabase supabase;
  late _AlwaysOnline connectivity;
  late SyncService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    localDb = _ContractLocalDb();
    supabase = _CapturingSupabase();
    connectivity = _AlwaysOnline();
    service = SyncService(
      localDb: localDb,
      supabase: supabase,
      connectivity: connectivity,
      syncDebounce: Duration.zero,
    );

    await localDb.seedChildRow({
      'id': 'child-1',
      'user_id': 'parent-1',
      'display_name': 'Mika',
      'birth_date': '2022-04-20',
      'avatar': 'lion',
      'music_enabled': 1,
      'vibration_enabled': 1,
      'comfort_settings': null,
      'sync_status': SyncStatus.synced.value,
      'last_synced_at': '2026-04-20T12:00:00.000',
      'deleted_at': null,
      'updated_at': '2026-04-20T12:00:00.000',
      'local_created_at': '2026-04-20T12:00:00.000',
      'owner_id': 'parent-1',
    });
  });

  tearDown(() async {
    service.dispose();
    connectivity.dispose();
    await localDb.close();
  });

  Future<void> seedRun({String type = 'pre'}) async {
    final db = await localDb.database;
    await db.insert(LocalTables.assessmentRuns, {
      'id': 'run-1',
      'child_id': 'child-1',
      'type': type,
      'started_at': '2026-08-23T10:00:00.000',
      'status': 'completed',
      'completed_at': '2026-08-23T10:12:00.000',
      'sync_status': SyncStatus.pending.value,
      'sync_attempts': 0,
      'updated_at': '2026-08-23T10:12:00.000',
      'local_created_at': '2026-08-23T10:00:00.000',
      'owner_id': 'parent-1',
    });
  }

  /// One local result row per mini-game, which is how the app scores a
  /// battery. The cloud keeps a single row for the whole run.
  Future<void> seedResultForGame(
    String id,
    String gameId, {
    String completedAt = '2026-08-23T10:12:00.000',
    String? communicationLabel,
    String? playLabel,
    String? socialLabel,
    String? attentionLabel,
  }) async {
    final db = await localDb.database;
    await db.insert(LocalTables.assessmentResults, {
      'id': id,
      'child_id': 'child-1',
      'assessment_run_id': 'run-1',
      'game_id': gameId,
      'type': 'pre',
      'score': 8,
      'total_items': 10,
      'error_count': 2,
      'avg_response_time_ms': 1500,
      'completed_at': completedAt,
      if (communicationLabel != null) 'communication_label': communicationLabel,
      if (playLabel != null) 'play_skills_label': playLabel,
      if (socialLabel != null) 'social_interaction_label': socialLabel,
      if (attentionLabel != null) 'behavior_attention_label': attentionLabel,
      'sync_status': SyncStatus.pending.value,
      'sync_attempts': 0,
      'local_created_at': completedAt,
      'last_synced_at': null,
    });
  }

  group('assessment_runs payload', () {
    test('uses cloud column names, not the local ones', () async {
      await seedRun();
      await service.startSync();

      final row = supabase.single(RemoteTables.assessmentRuns);

      expect(
        row.keys.toSet().difference(_cloudAssessmentRunColumns),
        isEmpty,
        reason: 'payload contains columns the cloud table does not have',
      );
      // The exact fields whose absence caused every run upload to 400.
      expect(row.containsKey('type'), isFalse);
      expect(row.containsKey('completed_at'), isFalse);
      expect(row.containsKey('status'), isFalse);
      expect(row['ended_at'], '2026-08-23T10:12:00.000');
    });

    test('translates the type value to the cloud CHECK vocabulary', () async {
      await seedRun(type: 'pre');
      await service.startSync();

      final row = supabase.single(RemoteTables.assessmentRuns);
      expect(row['assessment_type'], 'pre_assessment');
      expect(_cloudAssessmentTypes, contains(row['assessment_type']));
    });

    test('collapses the local tri-state status to the cloud boolean', () async {
      await seedRun();
      await service.startSync();

      expect(supabase.single(RemoteTables.assessmentRuns)['completed'], isTrue);
    });
  });

  group('assessment_results payload', () {
    test('aggregates the per-game rows into one row per run', () async {
      await seedRun();
      await seedResultForGame('result-match', 'match_it');
      await seedResultForGame('result-copy', 'copy_me');
      await seedResultForGame('result-trace', 'trace_it');

      await service.startSync();

      expect(supabase.rowCount(RemoteTables.assessmentResults), 1);
      final row = supabase.single(RemoteTables.assessmentResults);
      expect(row['id'], 'run-1');
      expect(row['assessment_run_id'], 'run-1');

      // All three local rows are settled, not just the one that was chosen
      // to supply the labels — otherwise the other two retry forever.
      final db = await localDb.database;
      final statuses = [
        for (final r in await db.query(LocalTables.assessmentResults))
          r['sync_status'],
      ];
      expect(statuses, everyElement(SyncStatus.synced.value));
    });

    test('sends only columns the cloud table has', () async {
      await seedRun();
      await seedResultForGame('result-match', 'match_it');
      await service.startSync();

      final row = supabase.single(RemoteTables.assessmentResults);
      expect(
        row.keys.toSet().difference(_cloudAssessmentResultColumns),
        isEmpty,
        reason: 'payload contains columns the cloud table does not have',
      );
      // Per-game fields belong to game_sessions, never to this table.
      for (final local in ['game_id', 'score', 'total_items', 'error_count']) {
        expect(row.containsKey(local), isFalse, reason: '$local is per-game');
      }
    });

    test('encodes rubric labels as the documented 0/1/2 ordinals', () async {
      await seedRun();
      await seedResultForGame(
        'result-match',
        'match_it',
        communicationLabel: 'Needs Support',
        playLabel: 'Emerging',
        socialLabel: 'Strength',
        attentionLabel: 'Sustained Attention',
      );

      await service.startSync();

      final row = supabase.single(RemoteTables.assessmentResults);
      expect(row['communication_level'], 0);
      expect(row['play_level'], 1);
      expect(row['social_level'], 2);
      expect(row['attention_level'], 2);
    });

    test('leaves confidence and overall_band unset for rubric scoring', () async {
      await seedRun();
      await seedResultForGame(
        'result-match',
        'match_it',
        communicationLabel: 'Emerging',
      );

      await service.startSync();

      final row = supabase.single(RemoteTables.assessmentResults);
      // Rule-based scoring has no probability behind it, and the rubric
      // computes no overall band. Writing either would put a number in front
      // of a validator that the assessment never produced.
      for (final area in ['communication', 'social', 'play', 'attention']) {
        expect(row['${area}_confidence'], isNull);
      }
      expect(row['overall_band'], isNull);
    });

    test('preserves the per-game detail in summary_json', () async {
      await seedRun();
      await seedResultForGame('result-match', 'match_it');
      await seedResultForGame('result-copy', 'copy_me');

      await service.startSync();

      final row = supabase.single(RemoteTables.assessmentResults);
      // Sent as a Map, not as a pre-encoded string: a jsonb column given a
      // JSON string stores a jsonb *string*, which nothing can index into.
      final summary = row['summary_json'] as Map<String, dynamic>;
      final perGame = summary['per_game'] as List;
      expect(perGame, hasLength(2));
      expect(
        {for (final g in perGame) (g as Map)['game_id']},
        {'match_it', 'copy_me'},
      );
    });

    test('a result with no run stays local instead of retrying forever', () async {
      final db = await localDb.database;
      await db.insert(LocalTables.assessmentResults, {
        'id': 'orphan-1',
        'child_id': 'child-1',
        'assessment_run_id': null,
        'game_id': 'match_it',
        'type': 'practice',
        'score': 5,
        'total_items': 10,
        'error_count': 5,
        'avg_response_time_ms': 2000,
        'completed_at': '2026-08-23T11:00:00.000',
        'sync_status': SyncStatus.pending.value,
        'sync_attempts': 0,
        'local_created_at': '2026-08-23T11:00:00.000',
        'last_synced_at': null,
      });

      await service.startSync();

      // Nothing uploaded — the cloud column is NOT NULL, so there is no row
      // this could become.
      expect(supabase.rowCount(RemoteTables.assessmentResults), 0);
      // But it must not stay pending, or every later sync retries it.
      final row = (await db.query(
        LocalTables.assessmentResults,
        where: 'id = ?',
        whereArgs: ['orphan-1'],
      )).single;
      expect(row['sync_status'], SyncStatus.synced.value);
    });
  });

  group('module_recommendations payload', () {
    test('targets source_assessment_id, which is a FK to results', () async {
      await seedRun();
      await seedResultForGame('result-match', 'match_it');
      final db = await localDb.database;
      await db.insert(LocalTables.moduleRecommendations, {
        'id': 'rec-1',
        'child_id': 'child-1',
        'assessment_run_id': 'run-1',
        'module_id': 'basic_skills',
        'module_name': 'Basic Skills',
        'starting_level': 1,
        'confidence': 0.8,
        'rationale': 'Communication is emerging',
        'sync_status': SyncStatus.pending.value,
        'sync_attempts': 0,
        'updated_at': '2026-08-23T10:12:00.000',
        'local_created_at': '2026-08-23T10:12:00.000',
      });

      await service.startSync();

      final row = supabase.single(RemoteTables.moduleRecommendations);
      expect(
        row.keys.toSet().difference(_cloudRecommendationColumns),
        isEmpty,
        reason: 'payload contains columns the cloud table does not have',
      );
      expect(row.containsKey('assessment_run_id'), isFalse);
      expect(row['top_module'], 'basic_skills');
      expect(row['recommended_by'], 'rules');

      // The FK points at assessment_results, so this id must match the
      // aggregated result row that was uploaded in the same pass.
      expect(
        row['source_assessment_id'],
        supabase.single(RemoteTables.assessmentResults)['id'],
      );
    });
  });

  test('sensory tables are not uploaded — no cloud table exists', () async {
    expect(SyncOrder.dependencyOrder, isNot(contains('sensory_consent_local')));
    expect(
      SyncOrder.dependencyOrder,
      isNot(contains('sensory_round_metrics_local')),
    );
    expect(
      SyncOrder.dependencyOrder,
      isNot(contains('sensory_preferences_local')),
    );
    expect(SyncOrder.getRemoteTable('sensory_consent_local'), isNull);
  });
}

/// Minimal local schema: only the columns these mappers read, so the test
/// stays readable and does not drift with unrelated migrations.
class _ContractLocalDb extends LocalDbService {
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
            music_enabled INTEGER NOT NULL DEFAULT 1,
            vibration_enabled INTEGER NOT NULL DEFAULT 1,
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

        await db.execute('''
          CREATE TABLE ${LocalTables.assessmentResults} (
            id TEXT PRIMARY KEY,
            child_id TEXT,
            assessment_run_id TEXT,
            game_id TEXT,
            type TEXT,
            score INTEGER,
            total_items INTEGER,
            error_count INTEGER,
            random_touch_count INTEGER DEFAULT 0,
            avg_response_time_ms INTEGER,
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
            deleted_at TEXT,
            local_created_at TEXT NOT NULL,
            last_synced_at TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE ${LocalTables.moduleRecommendations} (
            id TEXT PRIMARY KEY,
            child_id TEXT NOT NULL,
            assessment_run_id TEXT NOT NULL,
            module_id TEXT NOT NULL,
            module_name TEXT NOT NULL,
            starting_level INTEGER NOT NULL,
            confidence REAL,
            rationale TEXT,
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
              table != LocalTables.assessmentResults &&
              table != LocalTables.moduleRecommendations,
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

  @override
  Future<void> close() async {
    await _testDatabase?.close();
    _testDatabase = null;
  }
}

class _CapturingSupabase implements SupabaseService {
  final Map<String, Map<String, Map<String, dynamic>>> cloud = {};

  int rowCount(String remoteTable) => cloud[remoteTable]?.length ?? 0;

  Map<String, dynamic> single(String remoteTable) {
    final rows = cloud[remoteTable]?.values.toList() ?? const [];
    expect(rows, hasLength(1), reason: 'expected one row in $remoteTable');
    return rows.single;
  }

  @override
  Future<void> upsertBatch(
    String remoteTable,
    List<Map<String, dynamic>> records,
  ) async {
    final table = cloud.putIfAbsent(remoteTable, () => {});
    for (final record in records) {
      table[record['id'] as String] = Map<String, dynamic>.from(record);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRowsByColumn(
    String remoteTable,
    String column,
    List<String> values,
  ) async => [
    for (final r in cloud[remoteTable]?.values ?? const Iterable.empty())
      if (values.contains(r[column])) Map<String, dynamic>.from(r),
  ];

  @override
  bool get isAuthenticated => true;

  @override
  String? get currentUserId => 'parent-1';

  @override
  Future<void> upsertChild(Map<String, dynamic> data, String id) async {
    await upsertBatch(RemoteTables.children, [data]);
  }

  @override
  Future<void> softDeleteRemote(String remoteTable, String id) async {
    cloud[remoteTable]?.remove(id);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AlwaysOnline implements ConnectivityService {
  final _controller = StreamController<bool>.broadcast();

  @override
  bool get isOnline => true;

  @override
  Stream<bool> get onConnectivityChanged => _controller.stream;

  @override
  Future<void> initialize() async {}

  @override
  void dispose() {
    _controller.close();
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
