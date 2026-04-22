import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../sync/sync_status.dart';
import '../../model/child_profile.dart';
import '../../model/gameplay_session.dart';
import '../../model/assessment_result.dart';
import '../../model/module_progress.dart';

Future<void> migrateChildrenTableToBirthDateSchema(Database db) async {
  await db.execute(
    'ALTER TABLE ${LocalTables.children} RENAME TO ${LocalTables.children}_legacy_v2',
  );
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
  await db.execute('''
    INSERT INTO ${LocalTables.children} (
      id,
      user_id,
      display_name,
      birth_date,
      avatar,
      music_enabled,
      vibration_enabled,
      comfort_settings,
      sync_status,
      last_synced_at,
      deleted_at,
      updated_at,
      local_created_at,
      owner_id
    )
    SELECT
      id,
      user_id,
      name,
      NULL,
      avatar,
      music_enabled,
      vibration_enabled,
      comfort_settings,
      sync_status,
      last_synced_at,
      deleted_at,
      updated_at,
      local_created_at,
      owner_id
    FROM ${LocalTables.children}_legacy_v2
  ''');
  await db.execute('DROP TABLE ${LocalTables.children}_legacy_v2');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_children_user_id
    ON ${LocalTables.children}(user_id)
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_children_sync
    ON ${LocalTables.children}(sync_status)
  ''');
}

/// Enhanced SQLite database service for offline-first data.
///
/// All tables include sync metadata fields:
/// - sync_status: pending, syncing, synced, failed
/// - last_synced_at: When last successfully synced
/// - deleted_at: Soft delete timestamp (null = not deleted)
/// - updated_at: Local modification timestamp
/// - local_created_at: When record was created locally
/// - owner_id: User ID (for guest mode backfill)
///
/// The UI always reads from this local database. Sync happens
/// separately via SyncService when connectivity allows.
class LocalDbService {
  static const _dbName = 'aumazing_offline.db';
  static const _dbVersion = 3; // Incremented for child birth-date storage
  static const _readableChildWhere = 'display_name IS NOT NULL';
  static const _syncableChildWhere =
      'display_name IS NOT NULL AND birth_date IS NOT NULL';

  static Database? _database;

  Future<Database> get database async {
    _database ??= await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // ─── Schema Definition ────────────────────────────────────────────────

  /// Common sync metadata columns for all tables
  static const String _syncColumns = '''
    sync_status TEXT NOT NULL DEFAULT 'pending',
    last_synced_at TEXT,
    deleted_at TEXT,
    updated_at TEXT NOT NULL,
    local_created_at TEXT NOT NULL,
    owner_id TEXT
  ''';

  Future<void> _onCreate(Database db, int version) async {
    // Children table (renamed from child_profiles)
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
        $_syncColumns
      )
    ''');

    // Create index on user_id for faster lookups
    await db.execute('''
      CREATE INDEX idx_children_user_id ON ${LocalTables.children}(user_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_children_sync ON ${LocalTables.children}(sync_status)
    ''');

    // Assessment runs (assessment sessions)
    await db.execute('''
      CREATE TABLE ${LocalTables.assessmentRuns} (
        id TEXT PRIMARY KEY,
        child_id TEXT NOT NULL,
        type TEXT NOT NULL,
        started_at TEXT NOT NULL,
        completed_at TEXT,
        status TEXT NOT NULL DEFAULT 'in_progress',
        $_syncColumns,
        FOREIGN KEY (child_id) REFERENCES ${LocalTables.children}(id)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_assessment_runs_child ON ${LocalTables.assessmentRuns}(child_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_assessment_runs_sync ON ${LocalTables.assessmentRuns}(sync_status)
    ''');

    // Game sessions (enhanced gameplay sessions)
    await db.execute('''
      CREATE TABLE ${LocalTables.gameSessions} (
        id TEXT PRIMARY KEY,
        child_id TEXT NOT NULL,
        game_id TEXT NOT NULL,
        context TEXT NOT NULL,
        assessment_run_id TEXT,
        score INTEGER NOT NULL,
        total_items INTEGER NOT NULL,
        error_count INTEGER NOT NULL,
        total_response_time_ms INTEGER NOT NULL,
        started_at TEXT NOT NULL,
        ended_at TEXT NOT NULL,
        settings_snapshot TEXT,
        $_syncColumns,
        FOREIGN KEY (child_id) REFERENCES ${LocalTables.children}(id),
        FOREIGN KEY (assessment_run_id) REFERENCES ${LocalTables.assessmentRuns}(id)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_game_sessions_child ON ${LocalTables.gameSessions}(child_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_game_sessions_sync ON ${LocalTables.gameSessions}(sync_status)
    ''');

    // Game rounds (granular game data)
    await db.execute('''
      CREATE TABLE ${LocalTables.gameRounds} (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        round_number INTEGER NOT NULL,
        stimulus TEXT,
        response TEXT,
        is_correct INTEGER,
        response_time_ms INTEGER,
        started_at TEXT,
        ended_at TEXT,
        metadata TEXT,
        $_syncColumns,
        FOREIGN KEY (session_id) REFERENCES ${LocalTables.gameSessions}(id)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_game_rounds_session ON ${LocalTables.gameRounds}(session_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_game_rounds_sync ON ${LocalTables.gameRounds}(sync_status)
    ''');

    // Session events (detailed analytics)
    await db.execute('''
      CREATE TABLE ${LocalTables.sessionEvents} (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        event_type TEXT NOT NULL,
        event_data TEXT,
        occurred_at TEXT NOT NULL,
        $_syncColumns,
        FOREIGN KEY (session_id) REFERENCES ${LocalTables.gameSessions}(id)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_session_events_session ON ${LocalTables.sessionEvents}(session_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_session_events_sync ON ${LocalTables.sessionEvents}(sync_status)
    ''');

    // Caregiver questionnaires
    await db.execute('''
      CREATE TABLE ${LocalTables.caregiverQuestionnaires} (
        id TEXT PRIMARY KEY,
        child_id TEXT NOT NULL,
        questionnaire_type TEXT NOT NULL,
        responses TEXT NOT NULL,
        completed_at TEXT,
        $_syncColumns,
        FOREIGN KEY (child_id) REFERENCES ${LocalTables.children}(id)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_questionnaires_child ON ${LocalTables.caregiverQuestionnaires}(child_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_questionnaires_sync ON ${LocalTables.caregiverQuestionnaires}(sync_status)
    ''');

    // Assessment results (computed/summarized results)
    await db.execute('''
      CREATE TABLE ${LocalTables.assessmentResults} (
        id TEXT PRIMARY KEY,
        child_id TEXT NOT NULL,
        assessment_run_id TEXT NOT NULL,
        game_id TEXT NOT NULL,
        type TEXT NOT NULL,
        score INTEGER NOT NULL,
        total_items INTEGER NOT NULL,
        error_count INTEGER NOT NULL,
        avg_response_time_ms INTEGER NOT NULL,
        raw_metrics TEXT,
        $_syncColumns,
        FOREIGN KEY (child_id) REFERENCES ${LocalTables.children}(id),
        FOREIGN KEY (assessment_run_id) REFERENCES ${LocalTables.assessmentRuns}(id)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_assessment_results_child ON ${LocalTables.assessmentResults}(child_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_assessment_results_sync ON ${LocalTables.assessmentResults}(sync_status)
    ''');

    // Module recommendations
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
        $_syncColumns,
        FOREIGN KEY (child_id) REFERENCES ${LocalTables.children}(id)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_recommendations_child ON ${LocalTables.moduleRecommendations}(child_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_recommendations_sync ON ${LocalTables.moduleRecommendations}(sync_status)
    ''');

    // Assessment comparisons (pre vs post)
    await db.execute('''
      CREATE TABLE ${LocalTables.assessmentComparisons} (
        id TEXT PRIMARY KEY,
        child_id TEXT NOT NULL,
        pre_assessment_id TEXT NOT NULL,
        post_assessment_id TEXT NOT NULL,
        accuracy_improvement REAL,
        response_time_improvement_ms INTEGER,
        overall_improvement_percent REAL,
        summary TEXT,
        $_syncColumns,
        FOREIGN KEY (child_id) REFERENCES ${LocalTables.children}(id)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_comparisons_child ON ${LocalTables.assessmentComparisons}(child_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_comparisons_sync ON ${LocalTables.assessmentComparisons}(sync_status)
    ''');

    // Cached reference tables (from Supabase)
    await db.execute('''
      CREATE TABLE ${LocalTables.learningModulesCache} (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        icon_url TEXT,
        settings_schema TEXT,
        cached_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ${LocalTables.modulePathsCache} (
        id TEXT PRIMARY KEY,
        module_id TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        sequence_order INTEGER,
        cached_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ${LocalTables.modulePathItemsCache} (
        id TEXT PRIMARY KEY,
        path_id TEXT NOT NULL,
        item_type TEXT NOT NULL,
        item_id TEXT NOT NULL,
        sequence_order INTEGER,
        settings TEXT,
        cached_at TEXT NOT NULL
      )
    ''');

    // Sync queue for tracking pending operations
    await db.execute('''
      CREATE TABLE ${LocalTables.syncQueue} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        priority INTEGER DEFAULT 0,
        retry_count INTEGER DEFAULT 0,
        error_message TEXT,
        created_at TEXT NOT NULL,
        processed_at TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_sync_queue_pending ON ${LocalTables.syncQueue}(processed_at, priority)
    ''');

    debugPrint('[LocalDbService] Database created with sync schema v$version');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Migration from v1 to v2: Add sync columns to existing tables
      // Note: In production, you'd migrate existing data carefully
      debugPrint(
        '[LocalDbService] Upgrading from v$oldVersion to v$newVersion',
      );
    }

    if (oldVersion < 3) {
      await migrateChildrenTableToBirthDateSchema(db);
    }
  }

  // ─── Generic Sync Operations ──────────────────────────────────────────

  /// Get all pending records for a table
  Future<List<Map<String, dynamic>>> getPendingRecords(String table) async {
    final db = await database;
    return db.query(
      table,
      where: "sync_status IN ('pending', 'failed') AND deleted_at IS NULL",
      orderBy: 'local_created_at ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getPendingChildRecords() async {
    final db = await database;
    return db.query(
      LocalTables.children,
      where:
          "sync_status IN ('pending', 'failed') AND deleted_at IS NULL AND $_syncableChildWhere",
      orderBy: 'local_created_at ASC',
    );
  }

  /// Get all soft-deleted records that need deletion propagated
  Future<List<Map<String, dynamic>>> getDeletedRecords(String table) async {
    final db = await database;
    final childDeletionGuard =
        table == LocalTables.children ? ' AND $_syncableChildWhere' : '';
    return db.query(
      table,
      where:
          "deleted_at IS NOT NULL AND sync_status != 'synced'$childDeletionGuard",
    );
  }

  /// Mark a record as syncing
  Future<void> markSyncing(String table, String id) async {
    final db = await database;
    await db.update(
      table,
      {'sync_status': SyncStatus.syncing.value},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Mark a record as synced
  Future<void> markSynced(String table, String id, {DateTime? syncedAt}) async {
    final db = await database;
    await db.update(
      table,
      {
        'sync_status': SyncStatus.synced.value,
        'last_synced_at': (syncedAt ?? DateTime.now()).toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Mark a record as failed
  Future<void> markSyncFailed(String table, String id, {String? error}) async {
    final db = await database;
    await db.update(
      table,
      {
        'sync_status': SyncStatus.failed.value,
        if (error != null) 'sync_error': error,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Soft delete a record locally
  Future<void> softDelete(String table, String id) async {
    final db = await database;
    await db.update(
      table,
      {
        'deleted_at': DateTime.now().toIso8601String(),
        'sync_status': SyncStatus.pending.value,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Hard delete a record after successful remote deletion
  Future<void> hardDelete(String table, String id) async {
    final db = await database;
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  /// Update owner_id for guest-created records after auth
  Future<void> updateOwnerId(
    String table,
    String oldOwnerId,
    String newOwnerId,
  ) async {
    final db = await database;
    await db.update(
      table,
      {
        'owner_id': newOwnerId,
        'user_id': newOwnerId,
        'updated_at': DateTime.now().toIso8601String(),
        'sync_status': SyncStatus.pending.value,
      },
      where: 'owner_id = ? OR user_id = ?',
      whereArgs: [oldOwnerId, oldOwnerId],
    );
    debugPrint(
      '[LocalDbService] Updated owner_id in $table: $oldOwnerId -> $newOwnerId',
    );
  }

  /// Get count of pending records across all tables
  Future<Map<String, int>> getPendingCounts() async {
    final db = await database;
    final counts = <String, int>{};

    for (final table in SyncOrder.dependencyOrder) {
      final result = await db.rawQuery('''
        SELECT COUNT(*) as count FROM $table
        WHERE sync_status IN ('pending', 'failed') AND deleted_at IS NULL
        ${table == LocalTables.children ? 'AND $_syncableChildWhere' : ''}
      ''');
      counts[table] = Sqflite.firstIntValue(result) ?? 0;
    }

    return counts;
  }

  // ─── Children ─────────────────────────────────────────────────────────

  Future<void> upsertChild(
    ChildProfile profile, {
    String? ownerId,
    bool markPending = true,
  }) async {
    final db = await database;
    final now = DateTime.now();

    final map = profile.toMap();
    map.remove('created_at');
    map['local_created_at'] = profile.createdAt.toIso8601String();
    map['updated_at'] = now.toIso8601String();
    map['sync_status'] =
        markPending ? SyncStatus.pending.value : SyncStatus.synced.value;
    map['owner_id'] = ownerId ?? profile.userId;

    await db.insert(
      LocalTables.children,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ChildProfile>> getChildren({
    String? userId,
    bool includeDeleted = false,
  }) async {
    final db = await database;
    String? where;
    List<Object?>? whereArgs;

    if (userId != null) {
      where = 'user_id = ? AND $_readableChildWhere';
      whereArgs = [userId];
      if (!includeDeleted) {
        where += ' AND deleted_at IS NULL';
      }
    } else if (!includeDeleted) {
      where = 'deleted_at IS NULL AND $_readableChildWhere';
    } else {
      where = _readableChildWhere;
    }

    final rows = await db.query(
      LocalTables.children,
      where: where,
      whereArgs: whereArgs,
      orderBy: 'local_created_at DESC',
    );

    return rows.map((r) => ChildProfile.fromMap(r)).toList();
  }

  Future<ChildProfile?> getChild(String id) async {
    final db = await database;
    final rows = await db.query(
      LocalTables.children,
      where: 'id = ? AND deleted_at IS NULL AND $_readableChildWhere',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ChildProfile.fromMap(rows.first);
  }

  Future<void> deleteChild(String id) async {
    await softDelete(LocalTables.children, id);
  }

  // ─── Game Sessions ────────────────────────────────────────────────────

  Future<void> insertGameSession(
    GameplaySession session, {
    String? ownerId,
    bool markPending = true,
  }) async {
    final db = await database;
    final now = DateTime.now();

    final map = session.toMap();
    // Remove old 'synced' field, use sync_status instead
    map.remove('synced');
    map['local_created_at'] = session.startedAt.toIso8601String();
    map['updated_at'] = now.toIso8601String();
    map['sync_status'] =
        markPending ? SyncStatus.pending.value : SyncStatus.synced.value;
    map['owner_id'] = ownerId;

    await db.insert(
      LocalTables.gameSessions,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<GameplaySession>> getGameSessions({
    String? childId,
    String? context,
    bool includeDeleted = false,
  }) async {
    final db = await database;
    final conditions = <String>[];
    final args = <Object?>[];

    if (childId != null) {
      conditions.add('child_id = ?');
      args.add(childId);
    }
    if (context != null) {
      conditions.add('context = ?');
      args.add(context);
    }
    if (!includeDeleted) {
      conditions.add('deleted_at IS NULL');
    }

    final where = conditions.isNotEmpty ? conditions.join(' AND ') : null;

    final rows = await db.query(
      LocalTables.gameSessions,
      where: where,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'started_at DESC',
    );

    return rows.map((r) => GameplaySession.fromMap(r)).toList();
  }

  Future<List<GameplaySession>> getPendingGameSessions() async {
    final db = await database;
    final rows = await db.query(
      LocalTables.gameSessions,
      where: "sync_status IN ('pending', 'failed') AND deleted_at IS NULL",
      orderBy: 'started_at ASC',
    );
    return rows.map((r) => GameplaySession.fromMap(r)).toList();
  }

  // ─── Assessment Results ───────────────────────────────────────────────

  Future<void> insertAssessmentResult(
    AssessmentResult result, {
    String? ownerId,
    bool markPending = true,
  }) async {
    final db = await database;
    final now = DateTime.now();

    final map = result.toMap();
    map['local_created_at'] = result.completedAt.toIso8601String();
    map['updated_at'] = now.toIso8601String();
    map['sync_status'] =
        markPending ? SyncStatus.pending.value : SyncStatus.synced.value;
    map['owner_id'] = ownerId;

    await db.insert(
      LocalTables.assessmentResults,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<AssessmentResult>> getAssessmentResults({
    required String childId,
    String? type,
    bool includeDeleted = false,
  }) async {
    final db = await database;
    final conditions = ['child_id = ?'];
    final args = <Object?>[childId];

    if (type != null) {
      conditions.add('type = ?');
      args.add(type);
    }
    if (!includeDeleted) {
      conditions.add('deleted_at IS NULL');
    }

    final rows = await db.query(
      LocalTables.assessmentResults,
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: 'completed_at DESC',
    );

    return rows.map((r) => AssessmentResult.fromMap(r)).toList();
  }

  // ─── Module Progress ──────────────────────────────────────────────────

  Future<void> upsertModuleProgress(
    ModuleProgress progress, {
    bool markPending = true,
  }) async {
    final db = await database;
    final now = DateTime.now();

    final map = progress.toMap();
    // Ensure we have the required sync fields
    map['local_created_at'] = (progress.startedAt ?? now).toIso8601String();
    map['updated_at'] = now.toIso8601String();
    map['sync_status'] =
        markPending ? SyncStatus.pending.value : SyncStatus.synced.value;

    await db.insert(
      'module_progress',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ModuleProgress>> getModuleProgress(String childId) async {
    final db = await database;
    final rows = await db.query(
      'module_progress',
      where: 'child_id = ?',
      whereArgs: [childId],
      orderBy: 'updated_at DESC',
    );
    return rows.map((r) => ModuleProgress.fromMap(r)).toList();
  }

  // ─── Cached Reference Data ───────────────────────────────────────────

  Future<void> cacheLearningModules(List<Map<String, dynamic>> modules) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      // Clear existing cache
      await txn.delete(LocalTables.learningModulesCache);

      // Insert new data
      for (final module in modules) {
        await txn.insert(LocalTables.learningModulesCache, {
          'id': module['id'],
          'name': module['name'],
          'description': module['description'],
          'icon_url': module['icon_url'],
          'settings_schema': module['settings_schema']?.toString(),
          'cached_at': now,
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> getCachedLearningModules() async {
    final db = await database;
    return db.query(LocalTables.learningModulesCache);
  }

  Future<void> cacheModulePaths(List<Map<String, dynamic>> paths) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      await txn.delete(LocalTables.modulePathsCache);

      for (final path in paths) {
        await txn.insert(LocalTables.modulePathsCache, {
          'id': path['id'],
          'module_id': path['module_id'],
          'name': path['name'],
          'description': path['description'],
          'sequence_order': path['sequence_order'],
          'cached_at': now,
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> getCachedModulePaths() async {
    final db = await database;
    return db.query(LocalTables.modulePathsCache);
  }

  // ─── Sync Queue Operations ────────────────────────────────────────────

  Future<void> addToSyncQueue({
    required String table,
    required String recordId,
    required String operation,
    int priority = 0,
  }) async {
    final db = await database;
    await db.insert(LocalTables.syncQueue, {
      'table_name': table,
      'record_id': recordId,
      'operation': operation,
      'priority': priority,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getPendingSyncQueueItems() async {
    final db = await database;
    return db.query(
      LocalTables.syncQueue,
      where: 'processed_at IS NULL',
      orderBy: 'priority DESC, created_at ASC',
    );
  }

  Future<void> markQueueItemProcessed(int id) async {
    final db = await database;
    await db.update(
      LocalTables.syncQueue,
      {'processed_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ─── Guest Mode: Backfill Owner IDs ───────────────────────────────────

  /// Update all records created as guest to associate with authenticated user
  Future<void> backfillGuestData(
    String guestId,
    String authenticatedUserId,
  ) async {
    debugPrint(
      '[LocalDbService] Backfilling guest data: $guestId -> $authenticatedUserId',
    );

    // Update all tables that have owner_id
    await updateOwnerId(LocalTables.children, guestId, authenticatedUserId);
    await updateOwnerId(
      LocalTables.assessmentRuns,
      guestId,
      authenticatedUserId,
    );
    await updateOwnerId(LocalTables.gameSessions, guestId, authenticatedUserId);
    await updateOwnerId(LocalTables.gameRounds, guestId, authenticatedUserId);
    await updateOwnerId(
      LocalTables.sessionEvents,
      guestId,
      authenticatedUserId,
    );
    await updateOwnerId(
      LocalTables.caregiverQuestionnaires,
      guestId,
      authenticatedUserId,
    );
    await updateOwnerId(
      LocalTables.assessmentResults,
      guestId,
      authenticatedUserId,
    );
    await updateOwnerId(
      LocalTables.moduleRecommendations,
      guestId,
      authenticatedUserId,
    );
    await updateOwnerId(
      LocalTables.assessmentComparisons,
      guestId,
      authenticatedUserId,
    );

    debugPrint('[LocalDbService] Guest data backfill complete');
  }

  // ─── Utility ──────────────────────────────────────────────────────────

  Future<void> clearAll() async {
    final db = await database;
    await db.transaction((txn) async {
      for (final table in SyncOrder.dependencyOrder) {
        await txn.delete(table);
      }
      await txn.delete(LocalTables.learningModulesCache);
      await txn.delete(LocalTables.modulePathsCache);
      await txn.delete(LocalTables.modulePathItemsCache);
      await txn.delete(LocalTables.syncQueue);
    });
    debugPrint('[LocalDbService] All tables cleared');
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}

/// Global instance for app-wide access
final localDbService = LocalDbService();
