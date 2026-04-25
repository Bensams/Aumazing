import 'dart:async';

import 'package:aumazing/core/services/connectivity_service.dart';
import 'package:aumazing/core/services/local_db_service.dart';
import 'package:aumazing/core/services/supabase_service.dart';
import 'package:aumazing/core/services/sync_service.dart';
import 'package:aumazing/core/sync/sync_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('SyncService child sync', () {
    late _SyncTestLocalDb localDb;
    late _FakeSupabaseService supabase;
    late SyncService service;

    setUp(() async {
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
      'syncs only canonical child rows and maps them to public.children fields',
      () async {
        await service.startSync();

        expect(supabase.upsertedChildren, hasLength(1));
        expect(supabase.upsertedChildren.single, {
          'id': 'sync-child',
          'parent_user_id': 'parent-1',
          'display_name': 'Mika',
          'birth_date': '2022-04-20',
          'created_at': '2026-04-20T12:00:00.000',
          'updated_at': '2026-04-21T00:00:00.000',
        });
      },
    );
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
            music_enabled INTEGER NOT NULL DEFAULT 1,
            vibration_enabled INTEGER NOT NULL DEFAULT 1,
            comfort_settings TEXT,
            sync_status TEXT NOT NULL DEFAULT 'pending',
            last_synced_at TEXT,
            deleted_at TEXT,
            updated_at TEXT NOT NULL,
            local_created_at TEXT NOT NULL,
            owner_id TEXT
          )
        ''');

        for (final table in SyncOrder.dependencyOrder.where(
          (table) => table != LocalTables.children,
        )) {
          await db.execute('''
            CREATE TABLE $table (
              id TEXT PRIMARY KEY,
              sync_status TEXT NOT NULL DEFAULT 'pending',
              deleted_at TEXT,
              local_created_at TEXT NOT NULL
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

  @override
  bool get isAuthenticated => true;

  @override
  String? get currentUserId => 'parent-1';

  @override
  Future<void> upsertChild(Map<String, dynamic> data, String id) async {
    upsertedChildren.add(Map<String, dynamic>.from(data));
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
