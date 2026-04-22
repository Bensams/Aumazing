import 'package:aumazing/core/services/local_db_service.dart';
import 'package:aumazing/core/sync/sync_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('LocalDbService children', () {
    late _TestLocalDbService localDb;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      localDb = _TestLocalDbService();
      await localDb.seedChildRow({
        'id': 'legacy-child',
        'user_id': 'parent-1',
        'display_name': 'Legacy Child',
        'birth_date': null,
        'avatar': 'lion',
        'music_enabled': 1,
        'vibration_enabled': 1,
        'sync_status': SyncStatus.pending.value,
        'last_synced_at': null,
        'deleted_at': null,
        'updated_at': '2026-04-21T00:00:00.000',
        'local_created_at': '2026-04-21T00:00:00.000',
        'owner_id': 'parent-1',
      });
    });

    tearDown(() async {
      await localDb.close();
    });

    test(
      'returns legacy child rows with null birth dates from normal reads',
      () async {
        final children = await localDb.getChildren(userId: 'parent-1');
        final child = await localDb.getChild('legacy-child');

        expect(children, hasLength(1));
        expect(children.single.id, 'legacy-child');
        expect(children.single.birthDate, isNull);
        expect(child, isNotNull);
        expect(child!.birthDate, isNull);
      },
    );

    test(
      'excludes legacy child rows with null birth dates from child sync pending reads',
      () async {
        final pendingChildren = await localDb.getPendingChildRecords();
        final pendingCounts = await localDb.getPendingCounts();

        expect(pendingChildren, isEmpty);
        expect(pendingCounts[LocalTables.children], 0);
      },
    );

    test(
      'excludes deleted legacy child rows with null birth dates from delete propagation',
      () async {
        await localDb.seedChildRow({
          'id': 'deleted-legacy-child',
          'user_id': 'parent-1',
          'display_name': 'Deleted Legacy Child',
          'birth_date': null,
          'avatar': 'lion',
          'music_enabled': 1,
          'vibration_enabled': 1,
          'sync_status': SyncStatus.pending.value,
          'last_synced_at': null,
          'deleted_at': '2026-04-22T00:00:00.000',
          'updated_at': '2026-04-21T00:00:00.000',
          'local_created_at': '2026-04-21T00:00:00.000',
          'owner_id': 'parent-1',
        });
        await localDb.seedChildRow({
          'id': 'deleted-canonical-child',
          'user_id': 'parent-1',
          'display_name': 'Deleted Canonical Child',
          'birth_date': '2022-04-20',
          'avatar': 'lion',
          'music_enabled': 1,
          'vibration_enabled': 1,
          'sync_status': SyncStatus.pending.value,
          'last_synced_at': null,
          'deleted_at': '2026-04-22T00:00:00.000',
          'updated_at': '2026-04-21T00:00:00.000',
          'local_created_at': '2026-04-21T00:00:00.000',
          'owner_id': 'parent-1',
        });

        final deletedChildren = await localDb.getDeletedRecords(
          LocalTables.children,
        );

        expect(deletedChildren, hasLength(1));
        expect(deletedChildren.single['id'], 'deleted-canonical-child');
      },
    );

    test(
      'migrates v2 child rows to display_name with null birth dates',
      () async {
        final migrationPath =
            'legacy_v2_migration_${DateTime.now().microsecondsSinceEpoch}.db';
        final database = await openDatabase(
          migrationPath,
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
            CREATE TABLE ${LocalTables.children} (
              id TEXT PRIMARY KEY,
              user_id TEXT,
              name TEXT NOT NULL,
              age INTEGER NOT NULL,
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
          },
        );
        addTearDown(() async {
          await database.close();
          await databaseFactory.deleteDatabase(migrationPath);
        });

        await database.insert(LocalTables.children, {
          'id': 'legacy-child',
          'user_id': 'parent-1',
          'name': 'Legacy Child',
          'age': 5,
          'avatar': 'lion',
          'music_enabled': 1,
          'vibration_enabled': 0,
          'comfort_settings': null,
          'sync_status': SyncStatus.failed.value,
          'last_synced_at': null,
          'deleted_at': null,
          'updated_at': '2026-04-21T00:00:00.000',
          'local_created_at': '2026-04-21T00:00:00.000',
          'owner_id': 'parent-1',
        });

        await migrateChildrenTableToBirthDateSchema(database);

        final rows = await database.query(LocalTables.children);
        expect(rows, hasLength(1));
        expect(rows.single['display_name'], 'Legacy Child');
        expect(rows.single['birth_date'], isNull);
        expect(rows.single.containsKey('name'), isFalse);
        expect(rows.single.containsKey('age'), isFalse);
        expect(rows.single['sync_status'], SyncStatus.failed.value);
        expect(rows.single['owner_id'], 'parent-1');
      },
    );
  });
}

class _TestLocalDbService extends LocalDbService {
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
