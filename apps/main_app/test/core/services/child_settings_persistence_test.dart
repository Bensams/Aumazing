import 'package:aumazing/core/services/local_db_service.dart';
import 'package:aumazing/core/sync/sync_status.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A child's character and costume must survive closing the app (AUM-328).
///
/// They did not. Every online launch hydrated the cloud copy of the child row
/// over the local one with a blind `ConflictAlgorithm.replace` — no timestamp
/// comparison, no pending check — so a character chosen a moment before the
/// app was killed was gone on the next open. The replacement also stamped the
/// row back to `synced`, so the lost choice was never pushed either.
///
/// [LocalDbService.hydrateChild] puts children under the same conflict rule
/// every other table already had: **the later `updated_at` wins, and a tie
/// goes to local.**
void main() {
  late _FullSchemaDb db;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = _FullSchemaDb();
    // sqflite's in-memory database is shared across opens in one process, so
    // each test starts by emptying it rather than inheriting rows.
    await db.clear();
  });

  ChildProfile profile({
    required String updatedAt,
    String characterId = 'bps',
    String equippedCostume = 'none',
    String displayName = 'Mika',
  }) => ChildProfile.fromMap({
    'id': 'child-1',
    'user_id': 'parent-1',
    'display_name': displayName,
    'birth_date': '2022-04-20',
    'avatar': 'lion',
    'character_id': characterId,
    'equipped_costume': equippedCostume,
    'created_at': '2026-04-20T00:00:00.000',
    'updated_at': updatedAt,
  });

  test('a local costume change is not overwritten by an older cloud row', () async {
    // The parent equips a costume at 12:00; the cloud still holds the 10:00
    // copy from before the change, without it.
    await db.upsertChildAt(
      profile(
        updatedAt: '2026-08-29T12:00:00.000',
        characterId: 'lexianne',
        equippedCostume: 'teddy',
      ),
      updatedAt: '2026-08-29T12:00:00.000',
    );

    final written = await db.hydrateChild(
      profile(updatedAt: '2026-08-29T10:00:00.000'),
      ownerId: 'parent-1',
    );

    expect(written, isFalse);
    final stored = await db.getChild('child-1');
    expect(stored!.characterId, 'lexianne');
    expect(stored.equippedCostume, 'teddy');
  });

  test('the local row keeps its pending status so the change still pushes', () async {
    await db.upsertChildAt(
      profile(
        updatedAt: '2026-08-29T12:00:00.000',
        characterId: 'reiz',
      ),
      updatedAt: '2026-08-29T12:00:00.000',
    );

    await db.hydrateChild(
      profile(updatedAt: '2026-08-29T10:00:00.000'),
      ownerId: 'parent-1',
    );

    // The old code cleared this to synced, which is what turned "did not sync
    // yet" into "will never sync".
    expect(await db.syncStatusOf('child-1'), SyncStatus.pending.value);
    expect(await db.getPendingChildRecords(), hasLength(1));
  });

  test('a child only in the cloud is inserted', () async {
    final written = await db.hydrateChild(
      profile(updatedAt: '2026-08-29T10:00:00.000', characterId: 'lexianne'),
      ownerId: 'parent-1',
    );

    expect(written, isTrue);
    final stored = await db.getChild('child-1');
    expect(stored!.characterId, 'lexianne');
    expect(await db.syncStatusOf('child-1'), SyncStatus.synced.value);
  });

  test('a genuinely newer cloud edit does arrive', () async {
    await db.upsertChildAt(
      profile(updatedAt: '2026-08-29T10:00:00.000', characterId: 'bps'),
      updatedAt: '2026-08-29T10:00:00.000',
    );

    // The other device picked Reiz after this device last wrote.
    final written = await db.hydrateChild(
      profile(updatedAt: '2026-08-29T14:00:00.000', characterId: 'reiz'),
      ownerId: 'parent-1',
    );

    expect(written, isTrue);
    expect((await db.getChild('child-1'))!.characterId, 'reiz');
  });

  test('a tie goes to the local copy', () async {
    const sameMoment = '2026-08-29T12:00:00.000';
    await db.upsertChildAt(
      profile(updatedAt: sameMoment, characterId: 'lexianne'),
      updatedAt: sameMoment,
    );

    final written = await db.hydrateChild(
      profile(updatedAt: sameMoment),
      ownerId: 'parent-1',
    );

    expect(written, isFalse);
    expect((await db.getChild('child-1'))!.characterId, 'lexianne');
  });

  test('a hydrated row keeps the cloud timestamp, not the moment it landed', () async {
    // Stamping `now` here would make the local copy out-rank every later cloud
    // edit for good — the second device could never win again.
    await db.hydrateChild(
      profile(updatedAt: '2026-08-29T10:00:00.000'),
      ownerId: 'parent-1',
    );

    expect(await db.updatedAtOf('child-1'), '2026-08-29T10:00:00.000');
  });

  test('every settings field the app writes survives a local round trip', () async {
    // The push mapper is `ChildProfile.fromMap(row).toSupabase()`, so what the
    // cloud receives is exactly what a local row round-trips to. Pinning that
    // here keeps the two halves of the fix honest.
    final row = {
      'id': 'child-1',
      'user_id': 'parent-1',
      'display_name': 'Mika',
      'birth_date': '2022-04-20',
      'avatar': 'lion',
      'music_enabled': 0,
      'music_volume': 0.25,
      'music_category': 'playful',
      'sfx_volume': 0.4,
      'vibration_enabled': 0,
      'animation_intensity': 0.5,
      'prompt_speed': 1.5,
      'sensory_preferences_set': 1,
      'reward_preference': 'fireworks',
      'use_random_reward': 1,
      'character_id': 'reiz',
      'equipped_costume': 'panda',
      'local_created_at': '2026-04-20T00:00:00.000',
      'updated_at': '2026-08-29T12:00:00.000',
    };

    final remote = ChildProfile.fromMap(row).toSupabase();

    expect(remote['character_id'], 'reiz');
    expect(remote['equipped_costume'], 'panda');
    expect(remote['avatar'], 'lion');
    expect(remote['music_enabled'], false);
    expect(remote['music_volume'], 0.25);
    expect(remote['music_category'], 'playful');
    expect(remote['sfx_volume'], 0.4);
    expect(remote['vibration_enabled'], false);
    expect(remote['animation_intensity'], 0.5);
    expect(remote['prompt_speed'], 1.5);
    expect(remote['sensory_preferences_set'], true);
    expect(remote['reward_preference'], 'fireworks');
    expect(remote['use_random_reward'], true);
  });
}

/// The real children schema, so the settings columns under test actually exist.
class _FullSchemaDb extends LocalDbService {
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
      },
    );
    return _db!;
  }

  Future<void> clear() async {
    final db = await database;
    await db.delete(LocalTables.children);
  }

  /// [upsertChild] stamps `updated_at` with the wall clock, which no test can
  /// predict. Tests that need an exact local timestamp set it afterwards.
  Future<void> upsertChildAt(
    ChildProfile profile, {
    required String updatedAt,
  }) async {
    await upsertChild(profile);
    final db = await database;
    await db.update(
      LocalTables.children,
      {'updated_at': updatedAt},
      where: 'id = ?',
      whereArgs: [profile.id],
    );
  }

  Future<String?> syncStatusOf(String id) => _column(id, 'sync_status');
  Future<String?> updatedAtOf(String id) => _column(id, 'updated_at');

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
}
