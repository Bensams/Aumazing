import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../model/assessment_result.dart';
import '../model/child_profile.dart';
import '../model/gameplay_session.dart';
import '../model/module_progress.dart';

/// SQLite database for offline caching and unsynced gameplay data.
class LocalDbService {
  static const _dbName = 'aumazing.db';
  static const _dbVersion = 1;

  static Database? _database;

  Future<Database> get database async {
    _database ??= await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = '$dbPath/$_dbName';

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE child_profiles (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        name TEXT NOT NULL,
        age INTEGER NOT NULL,
        avatar TEXT NOT NULL,
        music_enabled INTEGER NOT NULL DEFAULT 1,
        vibration_enabled INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE assessment_results (
        id TEXT PRIMARY KEY,
        child_id TEXT NOT NULL,
        type TEXT NOT NULL,
        game_id TEXT NOT NULL,
        score INTEGER NOT NULL,
        total_items INTEGER NOT NULL,
        error_count INTEGER NOT NULL,
        avg_response_time_ms INTEGER NOT NULL,
        completed_at TEXT NOT NULL,
        raw_metrics TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE gameplay_sessions (
        id TEXT PRIMARY KEY,
        child_id TEXT NOT NULL,
        game_id TEXT NOT NULL,
        context TEXT NOT NULL,
        score INTEGER NOT NULL,
        total_items INTEGER NOT NULL,
        error_count INTEGER NOT NULL,
        total_response_time_ms INTEGER NOT NULL,
        started_at TEXT NOT NULL,
        ended_at TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE module_progress (
        id TEXT PRIMARY KEY,
        child_id TEXT NOT NULL,
        module_id TEXT NOT NULL,
        module_name TEXT NOT NULL,
        current_level INTEGER NOT NULL DEFAULT 1,
        max_level INTEGER NOT NULL DEFAULT 5,
        status TEXT NOT NULL DEFAULT 'not_started',
        started_at TEXT,
        completed_at TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  // ── Child Profile ─────────────────────────────────────────────────────

  Future<void> upsertChildProfile(ChildProfile profile) async {
    final db = await database;
    await db.insert(
      'child_profiles',
      profile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ChildProfile?> getChildProfile(String userId) async {
    final db = await database;
    final rows = await db.query(
      'child_profiles',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ChildProfile.fromMap(rows.first);
  }

  // ── Gameplay Sessions ─────────────────────────────────────────────────

  Future<void> insertSession(GameplaySession session) async {
    final db = await database;
    await db.insert('gameplay_sessions', session.toMap());
  }

  Future<List<GameplaySession>> getUnsyncedSessions() async {
    final db = await database;
    final rows = await db.query(
      'gameplay_sessions',
      where: 'synced = 0',
      orderBy: 'ended_at ASC',
    );
    return rows.map(GameplaySession.fromMap).toList();
  }

  Future<void> markSessionSynced(String sessionId) async {
    final db = await database;
    await db.update(
      'gameplay_sessions',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<List<GameplaySession>> getSessionsForChild(String childId) async {
    final db = await database;
    final rows = await db.query(
      'gameplay_sessions',
      where: 'child_id = ?',
      whereArgs: [childId],
      orderBy: 'ended_at DESC',
    );
    return rows.map(GameplaySession.fromMap).toList();
  }

  // ── Assessment Results ────────────────────────────────────────────────

  Future<void> insertAssessmentResult(AssessmentResult result) async {
    final db = await database;
    await db.insert(
      'assessment_results',
      result.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<AssessmentResult>> getAssessmentResults(
    String childId, {
    String? type,
  }) async {
    final db = await database;
    final where = type != null
        ? 'child_id = ? AND type = ?'
        : 'child_id = ?';
    final whereArgs = type != null ? [childId, type] : [childId];
    final rows = await db.query(
      'assessment_results',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'completed_at DESC',
    );
    return rows.map(AssessmentResult.fromMap).toList();
  }

  // ── Module Progress ───────────────────────────────────────────────────

  Future<void> upsertModuleProgress(ModuleProgress progress) async {
    final db = await database;
    await db.insert(
      'module_progress',
      progress.toMap(),
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
    return rows.map(ModuleProgress.fromMap).toList();
  }

  // ── Utility ───────────────────────────────────────────────────────────

  /// Sync all unsynced gameplay sessions to Supabase.
  /// Call this when the device regains connectivity.
  Future<List<GameplaySession>> pendingSyncSessions() => getUnsyncedSessions();

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('gameplay_sessions');
    await db.delete('assessment_results');
    await db.delete('module_progress');
    await db.delete('child_profiles');
    debugPrint('[LocalDB] All tables cleared');
  }
}
