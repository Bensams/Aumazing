import 'package:aumazing/core/services/local_db_service.dart';
import 'package:aumazing/core/sync/sync_status.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/model/module_progress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// AUM-150 — deleting a child takes that child's local data with it, leaves a
/// tombstone for the cloud deletion, and never touches a sibling.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalDbService localDb;

  ChildProfile child(String id) => ChildProfile(
    id: id,
    userId: 'user-1',
    displayName: 'Child $id',
    birthDate: DateTime(2020, 1, 1),
    avatar: '🐻',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  Future<void> seedResult(String childId, String id) async {
    final db = await localDb.database;
    await db.insert(LocalTables.assessmentResults, {
      'id': id,
      'child_id': childId,
      'type': 'pre',
      'game_id': 'match_it',
      'score': 5,
      'total_items': 10,
      'error_count': 1,
      'avg_response_time_ms': 1200,
      'completed_at': '2026-06-01T00:00:00.000',
      'sync_status': SyncStatus.pending.value,
      'updated_at': '2026-06-01T00:00:00.000',
      'local_created_at': '2026-06-01T00:00:00.000',
      'owner_id': 'user-1',
    });
  }

  // LocalDbService caches its database statically, so the file is created
  // once and the tables are re-seeded per test instead.
  Future<void> seedProgress(String childId, String moduleId) async {
    await localDb.upsertModuleProgress(
      ModuleProgress(
        id: '$moduleId-$childId',
        childId: childId,
        moduleId: moduleId,
        moduleName: 'Module $moduleId',
        updatedAt: DateTime(2026, 6, 1),
      ),
    );
  }

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.deleteDatabase(
      '${await getDatabasesPath()}/aumazing_offline.db',
    );
    localDb = LocalDbService();
  });

  setUp(() async {
    final db = await localDb.database;
    await db.delete(LocalTables.assessmentResults);
    await db.delete(LocalTables.children);
    await localDb.upsertChild(child('a'));
    await localDb.upsertChild(child('b'));
    await seedResult('a', 'result-a');
    await seedResult('b', 'result-b');
    // Module progress is local-only parent history (AUM-308).
    await seedProgress('a', 'module-a');
    await seedProgress('b', 'module-b');
  });

  test('a deleted child is hidden but kept as a sync tombstone', () async {
    await localDb.deleteChild('a');

    expect((await localDb.getChildren(userId: 'user-1')).map((c) => c.id), [
      'b',
    ]);
    expect(await localDb.getChild('a'), isNull);
    expect(await localDb.getLocallyDeletedChildIds(), {'a'});
    expect(
      (await localDb.getDeletedRecords(
        LocalTables.children,
      )).map((r) => r['id']),
      ['a'],
    );
  });

  test('purging a child removes only that child\'s records', () async {
    await localDb.purgeChildScopedData('a');

    final db = await localDb.database;
    final remaining = await db.query(LocalTables.assessmentResults);
    expect(remaining.map((r) => r['id']), ['result-b']);
    final progress = await db.query(LocalTables.moduleProgress);
    expect(progress.map((r) => r['id']), ['module-b-b']);
  });

  test('clearAll wipes local-only module progress too', () async {
    await localDb.clearAll();

    final db = await localDb.database;
    expect(await db.query(LocalTables.moduleProgress), isEmpty);
    expect(await db.query(LocalTables.assessmentResults), isEmpty);
  });

  test('a sibling is untouched by the deletion', () async {
    await localDb.deleteChild('a');
    await localDb.purgeChildScopedData('a');

    expect((await localDb.getChild('b'))!.displayName, 'Child b');
    final db = await localDb.database;
    expect(await db.query(LocalTables.assessmentResults), hasLength(1));
  });
}
