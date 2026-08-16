import 'package:aumazing/core/services/local_db_service.dart';
import 'package:aumazing/core/sync/sync_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The sync conflict rule (AUM-158): when the cloud and the device both hold
/// a version of the same record, **the later `updated_at` wins, and a tie
/// goes to local**.
///
/// Hydration used to be insert-only, so an edit made on another device could
/// never arrive — a second device kept a stale copy forever and whichever
/// device pushed last overwrote the cloud regardless of which edit was
/// actually newer.
void main() {
  late _TestDb db;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = _TestDb();
    // sqflite's in-memory database is shared across opens in one process,
    // so each test starts by emptying it rather than inheriting rows.
    await db.clear();
  });

  Map<String, Object?> child({
    required String id,
    required String name,
    required String updatedAt,
    String syncStatus = 'synced',
    String? deletedAt,
  }) => {
    'id': id,
    'user_id': 'parent-1',
    'display_name': name,
    'birth_date': null,
    'avatar': 'lion',
    'music_enabled': 1,
    'vibration_enabled': 1,
    'sync_status': syncStatus,
    'last_synced_at': null,
    'deleted_at': deletedAt,
    'updated_at': updatedAt,
    'local_created_at': updatedAt,
    'owner_id': 'parent-1',
  };

  Future<String?> nameOf(String id) async => db.nameOf(id);
  Future<String?> statusOf(String id) async => db.statusOf(id);

  test('a record only in the cloud is inserted', () async {
    final written = await db.hydrateRecords(LocalTables.children, [
      child(id: 'c1', name: 'From Cloud', updatedAt: '2026-06-01T10:00:00.000'),
    ]);

    expect(written, 1);
    expect(await nameOf('c1'), 'From Cloud');
    expect(await statusOf('c1'), SyncStatus.synced.value);
  });

  test('a strictly newer cloud version replaces the local one', () async {
    await db.seed(
      child(id: 'c1', name: 'Old Local', updatedAt: '2026-06-01T10:00:00.000'),
    );

    final written = await db.hydrateRecords(LocalTables.children, [
      child(
        id: 'c1',
        name: 'Newer Cloud',
        updatedAt: '2026-06-02T10:00:00.000',
      ),
    ]);

    expect(written, 1);
    expect(await nameOf('c1'), 'Newer Cloud');
    expect(await statusOf('c1'), SyncStatus.synced.value);
  });

  test('an older cloud version never overwrites a newer local edit', () async {
    await db.seed(
      child(
        id: 'c1',
        name: 'Newer Local',
        updatedAt: '2026-06-05T10:00:00.000',
      ),
    );

    final written = await db.hydrateRecords(LocalTables.children, [
      child(
        id: 'c1',
        name: 'Stale Cloud',
        updatedAt: '2026-06-01T10:00:00.000',
      ),
    ]);

    expect(written, 0);
    expect(await nameOf('c1'), 'Newer Local');
  });

  test('a tie goes to local', () async {
    const sameMoment = '2026-06-01T10:00:00.000';
    await db.seed(child(id: 'c1', name: 'Local', updatedAt: sameMoment));

    final written = await db.hydrateRecords(LocalTables.children, [
      child(id: 'c1', name: 'Cloud', updatedAt: sameMoment),
    ]);

    expect(written, 0);
    expect(await nameOf('c1'), 'Local');
  });

  group('what the rule must never do', () {
    test('an older cloud row does not resurrect a local delete', () async {
      // Deleting bumped updated_at, so the delete is the newer version.
      await db.seed(
        child(
          id: 'c1',
          name: 'Deleted Here',
          updatedAt: '2026-06-05T10:00:00.000',
          syncStatus: 'pending',
          deletedAt: '2026-06-05T10:00:00.000',
        ),
      );

      final written = await db.hydrateRecords(LocalTables.children, [
        child(
          id: 'c1',
          name: 'Alive In Cloud',
          updatedAt: '2026-06-01T10:00:00.000',
        ),
      ]);

      expect(written, 0);
      expect(await db.deletedAtOf('c1'), isNotNull);
      expect(
        await statusOf('c1'),
        'pending',
        reason: 'the delete still pushes',
      );
    });

    test('an unsynced local edit survives an older cloud row', () async {
      await db.seed(
        child(
          id: 'c1',
          name: 'Edited Offline',
          updatedAt: '2026-06-05T10:00:00.000',
          syncStatus: 'pending',
        ),
      );

      final written = await db.hydrateRecords(LocalTables.children, [
        child(
          id: 'c1',
          name: 'Older Cloud',
          updatedAt: '2026-06-01T10:00:00.000',
        ),
      ]);

      expect(written, 0);
      expect(await nameOf('c1'), 'Edited Offline');
      // Still pending, so it will push and win in the cloud too.
      expect(await statusOf('c1'), 'pending');
    });

    test('a row with an unparseable timestamp is left alone', () async {
      await db.seed(child(id: 'c1', name: 'Local', updatedAt: 'not-a-date'));

      final written = await db.hydrateRecords(LocalTables.children, [
        child(id: 'c1', name: 'Cloud', updatedAt: '2026-06-01T10:00:00.000'),
      ]);

      expect(written, 0);
      expect(await nameOf('c1'), 'Local');
    });
  });

  test('a mixed batch inserts, updates and skips independently', () async {
    await db.seed(
      child(
        id: 'stale',
        name: 'Stale Local',
        updatedAt: '2026-06-01T00:00:00.000',
      ),
    );
    await db.seed(
      child(
        id: 'fresh',
        name: 'Fresh Local',
        updatedAt: '2026-06-09T00:00:00.000',
      ),
    );

    final written = await db.hydrateRecords(LocalTables.children, [
      child(
        id: 'stale',
        name: 'Cloud Wins',
        updatedAt: '2026-06-05T00:00:00.000',
      ),
      child(
        id: 'fresh',
        name: 'Cloud Loses',
        updatedAt: '2026-06-05T00:00:00.000',
      ),
      child(
        id: 'new',
        name: 'Cloud Only',
        updatedAt: '2026-06-05T00:00:00.000',
      ),
    ]);

    expect(written, 2, reason: 'one updated, one inserted, one skipped');
    expect(await nameOf('stale'), 'Cloud Wins');
    expect(await nameOf('fresh'), 'Fresh Local');
    expect(await nameOf('new'), 'Cloud Only');
  });

  test('an empty batch writes nothing', () async {
    expect(await db.hydrateRecords(LocalTables.children, const []), 0);
  });
}

class _TestDb extends LocalDbService {
  Database? _db;

  @override
  Future<Database> get database async {
    _db ??= await openDatabase(
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
      },
    );
    return _db!;
  }

  Future<void> clear() async {
    final db = await database;
    await db.delete(LocalTables.children);
  }

  Future<void> seed(Map<String, Object?> row) async {
    final db = await database;
    await db.insert(LocalTables.children, row);
  }

  Future<String?> _column(String id, String column) async {
    final db = await database;
    final rows = await db.query(
      LocalTables.children,
      columns: [column],
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : rows.first[column] as String?;
  }

  Future<String?> nameOf(String id) => _column(id, 'display_name');
  Future<String?> statusOf(String id) => _column(id, 'sync_status');
  Future<String?> deletedAtOf(String id) => _column(id, 'deleted_at');
}
