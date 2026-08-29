import 'dart:async';

import 'package:aumazing/core/services/connectivity_service.dart';
import 'package:aumazing/core/services/local_db_service.dart';
import 'package:aumazing/core/services/supabase_service.dart';
import 'package:aumazing/core/services/sync_service.dart';
import 'package:aumazing/core/sync/sync_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// AUM-157: gameplay and assessment progress save locally while offline,
/// retry when connectivity returns, and upsert-by-id so retries cannot
/// duplicate cloud rows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _SyncTestLocalDb localDb;
  late _UpsertingFakeSupabase supabase;
  late _ControllableConnectivity connectivity;
  late SyncService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    localDb = _SyncTestLocalDb();
    supabase = _UpsertingFakeSupabase();
    connectivity = _ControllableConnectivity(online: false);
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

  Future<void> seedPendingProgress() async {
    final db = await localDb.database;
    await db.insert(LocalTables.assessmentRuns, {
      'id': 'run-1',
      'child_id': 'child-1',
      'type': 'pre',
      'started_at': '2026-08-23T10:00:00.000',
      'status': 'completed',
      'completed_at': '2026-08-23T10:12:00.000',
      'sync_status': SyncStatus.pending.value,
      'sync_attempts': 0,
      'updated_at': '2026-08-23T10:12:00.000',
      'local_created_at': '2026-08-23T10:00:00.000',
      'owner_id': 'parent-1',
    });
    await db.insert(LocalTables.gameSessions, {
      'id': 'session-1',
      'child_id': 'child-1',
      'game_id': 'match_it',
      'context': 'pre_assessment',
      'assessment_run_id': 'run-1',
      'score': 8,
      'total_items': 10,
      'error_count': 2,
      'total_response_time_ms': 15000,
      'started_at': '2026-08-23T10:01:00.000',
      'ended_at': '2026-08-23T10:04:00.000',
      'sync_status': SyncStatus.pending.value,
      'sync_attempts': 0,
      'local_created_at': '2026-08-23T10:01:00.000',
      'last_synced_at': null,
    });
    await db.insert(LocalTables.assessmentResults, {
      'id': 'result-1',
      'child_id': 'child-1',
      'assessment_run_id': 'run-1',
      'game_id': 'match_it',
      'type': 'pre',
      'score': 8,
      'total_items': 10,
      'error_count': 2,
      'avg_response_time_ms': 1500,
      'completed_at': '2026-08-23T10:12:00.000',
      'sync_status': SyncStatus.pending.value,
      'sync_attempts': 0,
      'local_created_at': '2026-08-23T10:12:00.000',
      'last_synced_at': null,
    });
  }

  Future<void> flushDebouncedSync() async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (service.isSyncing && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test(
    'gameplay and assessment progress save locally while offline and are not uploaded',
    () async {
      await seedPendingProgress();

      expect(
        await localDb.getPendingRecords(LocalTables.gameSessions),
        hasLength(1),
      );
      expect(
        await localDb.getPendingRecords(LocalTables.assessmentResults),
        hasLength(1),
      );
      expect(
        await localDb.getPendingRecords(LocalTables.assessmentRuns),
        hasLength(1),
      );

      await service.startSync();

      expect(supabase.upsertCallCount, 0);
      expect(supabase.rowCount(RemoteTables.gameSessions), 0);
      expect(supabase.rowCount(RemoteTables.assessmentResults), 0);
      expect(supabase.rowCount(RemoteTables.assessmentRuns), 0);

      final db = await localDb.database;
      final session = (await db.query(
        LocalTables.gameSessions,
        where: 'id = ?',
        whereArgs: ['session-1'],
      )).single;
      expect(session['sync_status'], SyncStatus.pending.value);
      expect(session['score'], 8);
    },
  );

  test(
    'pending progress retries and uploads when connectivity is restored',
    () async {
      await seedPendingProgress();
      await service.initialize();

      await service.startSync();
      expect(supabase.upsertCallCount, 0);

      connectivity.setOnline(true);
      await flushDebouncedSync();

      expect(supabase.rowCount(RemoteTables.gameSessions), 1);
      expect(supabase.ids(RemoteTables.gameSessions), {'session-1'});
      expect(supabase.rowCount(RemoteTables.assessmentResults), 1);
      // The cloud keeps one result per run, so the aggregated row is keyed on
      // the run id rather than on any single local per-game result id.
      expect(supabase.ids(RemoteTables.assessmentResults), {'run-1'});
      expect(supabase.rowCount(RemoteTables.assessmentRuns), 1);
      expect(supabase.ids(RemoteTables.assessmentRuns), {'run-1'});

      final db = await localDb.database;
      expect(
        (await db.query(
          LocalTables.gameSessions,
          where: 'id = ?',
          whereArgs: ['session-1'],
        )).single['sync_status'],
        SyncStatus.synced.value,
      );
      expect(
        (await db.query(
          LocalTables.assessmentResults,
          where: 'id = ?',
          whereArgs: ['result-1'],
        )).single['sync_status'],
        SyncStatus.synced.value,
      );
    },
  );

  test(
    'a successful retry upserts the same id and does not duplicate cloud rows',
    () async {
      await seedPendingProgress();
      connectivity.setOnline(true);

      await service.startSync();
      expect(supabase.rowCount(RemoteTables.gameSessions), 1);
      expect(supabase.ids(RemoteTables.gameSessions), {'session-1'});
      final callsAfterFirst = supabase.upsertCallCount;
      expect(callsAfterFirst, greaterThan(0));

      // Crash-after-upload: local rows look pending again, retry must not
      // create a second cloud row for the same id.
      final db = await localDb.database;
      for (final table in [
        LocalTables.gameSessions,
        LocalTables.assessmentResults,
        LocalTables.assessmentRuns,
      ]) {
        await db.update(table, {
          'sync_status': SyncStatus.pending.value,
          'last_synced_at': null,
        });
      }

      await service.startSync();

      expect(supabase.upsertCallCount, greaterThan(callsAfterFirst));
      expect(supabase.rowCount(RemoteTables.gameSessions), 1);
      expect(supabase.ids(RemoteTables.gameSessions), {'session-1'});
      expect(supabase.rowCount(RemoteTables.assessmentResults), 1);
      expect(supabase.ids(RemoteTables.assessmentResults), {'run-1'});
      expect(supabase.rowCount(RemoteTables.assessmentRuns), 1);
      expect(supabase.ids(RemoteTables.assessmentRuns), {'run-1'});
    },
  );
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
          CREATE TABLE ${LocalTables.gameSessions} (
            id TEXT PRIMARY KEY,
            child_id TEXT,
            game_id TEXT,
            context TEXT,
            assessment_run_id TEXT,
            score INTEGER,
            total_items INTEGER,
            error_count INTEGER,
            total_response_time_ms INTEGER,
            started_at TEXT,
            ended_at TEXT,
            sync_status TEXT NOT NULL DEFAULT 'pending',
            sync_error TEXT,
            sync_attempts INTEGER NOT NULL DEFAULT 0,
            deleted_at TEXT,
            local_created_at TEXT NOT NULL,
            last_synced_at TEXT
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
            avg_response_time_ms INTEGER,
            completed_at TEXT,
            sync_status TEXT NOT NULL DEFAULT 'pending',
            sync_error TEXT,
            sync_attempts INTEGER NOT NULL DEFAULT 0,
            deleted_at TEXT,
            local_created_at TEXT NOT NULL,
            last_synced_at TEXT
          )
        ''');

        for (final table in SyncOrder.dependencyOrder.where(
          (table) =>
              table != LocalTables.children &&
              table != LocalTables.assessmentRuns &&
              table != LocalTables.gameSessions &&
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

/// Cloud double that upserts by id (replace, never append a second row).
class _UpsertingFakeSupabase implements SupabaseService {
  final Map<String, Map<String, Map<String, dynamic>>> cloud = {};
  int upsertCallCount = 0;

  int rowCount(String remoteTable) => cloud[remoteTable]?.length ?? 0;

  Set<String> ids(String remoteTable) =>
      cloud[remoteTable]?.keys.toSet() ?? {};

  @override
  Future<void> upsertBatch(
    String remoteTable,
    List<Map<String, dynamic>> records,
  ) async {
    upsertCallCount++;
    final table = cloud.putIfAbsent(remoteTable, () => {});
    for (final record in records) {
      final id = record['id'] as String;
      table[id] = Map<String, dynamic>.from(record);
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
  Future<List<Map<String, dynamic>>> getChildren(String userId) async =>
      const [];

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

class _ControllableConnectivity implements ConnectivityService {
  bool _online;
  final _controller = StreamController<bool>.broadcast();

  _ControllableConnectivity({bool online = false}) : _online = online;

  void setOnline(bool value) {
    if (_online == value) return;
    _online = value;
    _controller.add(value);
  }

  @override
  bool get isOnline => _online;

  @override
  bool get isOffline => !_online;

  @override
  Stream<bool> get onConnectivityChanged => _controller.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> checkConnectivity() async => _online;

  @override
  void dispose() {
    _controller.close();
  }
}
