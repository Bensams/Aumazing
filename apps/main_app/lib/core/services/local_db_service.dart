import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:game_core/game_core.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import '../../model/assessment_run_record.dart';

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
      sex TEXT,
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
  static const _dbVersion = 18; // v18: gameplay_sessions.configuration_version

  /// Records failing more than this many upload attempts are quarantined:
  /// excluded from pending queries/counts so they stop driving the retry
  /// loop. They keep sync_status='failed' + sync_error for diagnosis.
  static const maxSyncAttempts = 10;
  static const _uuid = Uuid();
  static const _readableChildWhere = 'display_name IS NOT NULL';

  /// Children eligible for cloud sync. Guest-owned rows are excluded:
  /// their owner is a local id like `guest_<uuid>`, which Supabase's
  /// `parent_user_id` (a real uuid) rejects with 22P02. They stay local
  /// until sign-in backfills the real user id (see [backfillGuestData]).
  static const _syncableChildWhere =
      "display_name IS NOT NULL "
      "AND user_id IS NOT NULL "
      "AND user_id NOT LIKE 'guest_%' "
      "AND (owner_id IS NULL OR owner_id NOT LIKE 'guest_%')";

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
    sync_error TEXT,
    sync_attempts INTEGER NOT NULL DEFAULT 0,
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

    await _createStarTables(db);

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
        retry_count INTEGER NOT NULL DEFAULT 0,
        hint_count INTEGER NOT NULL DEFAULT 0,
        prompt_count INTEGER NOT NULL DEFAULT 0,
        idle_time_seconds REAL NOT NULL DEFAULT 0.0,
        random_touch_count INTEGER NOT NULL DEFAULT 0,
        avg_response_time REAL NOT NULL DEFAULT 0.0,
        avg_valid_response_time REAL NOT NULL DEFAULT 0.0,
        off_task_action_count INTEGER NOT NULL DEFAULT 0,
        improvement_score REAL NOT NULL DEFAULT 0.0,
        consistency_score REAL NOT NULL DEFAULT 0.0,
        bg_music_enabled INTEGER NOT NULL DEFAULT 1,
        haptic_feedback_enabled INTEGER NOT NULL DEFAULT 1,
        task_completion_rate REAL,
        prompt_dependency_score REAL,
        turn_taking_success_rate REAL,
        interruption_count INTEGER DEFAULT 0,
        waiting_tolerance_seconds REAL,
        time_to_first_touch REAL,
        time_to_first_valid_action REAL,
        time_to_completion REAL,
        sensory_condition TEXT,
        configuration_version TEXT,
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

    // Game rounds (per-round metrics matching Supabase game_rounds schema)
    await db.execute('''
      CREATE TABLE ${LocalTables.gameRounds} (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        round_no INTEGER NOT NULL,
        stimulus_type TEXT,
        valid_action_type TEXT,
        correct INTEGER,
        response_time REAL,
        valid_response_time REAL,
        time_to_first_hint REAL,
        retry_count INTEGER DEFAULT 0,
        hint_count INTEGER DEFAULT 0,
        prompt_count INTEGER DEFAULT 0,
        random_touch_count INTEGER DEFAULT 0,
        strong_prompt_triggered INTEGER DEFAULT 0,
        guided_assist_triggered INTEGER DEFAULT 0,
        completed INTEGER DEFAULT 0,
        music_enabled INTEGER NOT NULL DEFAULT 1,
        haptic_enabled INTEGER NOT NULL DEFAULT 1,
        created_at TEXT,
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

    // Sensory consent records
    await db.execute('''
      CREATE TABLE ${LocalTables.sensoryConsent} (
        id TEXT PRIMARY KEY,
        child_id TEXT NOT NULL,
        assessment_run_id TEXT,
        consent_given INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        $_syncColumns,
        FOREIGN KEY (child_id) REFERENCES ${LocalTables.children}(id)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_sensory_consent_child ON ${LocalTables.sensoryConsent}(child_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_sensory_consent_sync ON ${LocalTables.sensoryConsent}(sync_status)
    ''');

    // Per-round sensory metrics
    await db.execute('''
      CREATE TABLE ${LocalTables.sensoryRoundMetrics} (
        id TEXT PRIMARY KEY,
        child_id TEXT NOT NULL,
        assessment_run_id TEXT,
        game_id TEXT NOT NULL,
        round_number INTEGER NOT NULL,
        music_enabled INTEGER NOT NULL DEFAULT 0,
        haptic_enabled INTEGER NOT NULL DEFAULT 0,
        sensory_purpose TEXT NOT NULL,
        correct_count INTEGER NOT NULL DEFAULT 0,
        wrong_count INTEGER NOT NULL DEFAULT 0,
        accuracy REAL NOT NULL DEFAULT 0.0,
        total_response_time_ms INTEGER NOT NULL DEFAULT 0,
        avg_response_time_ms REAL NOT NULL DEFAULT 0.0,
        tap_count INTEGER NOT NULL DEFAULT 0,
        idle_time_seconds REAL NOT NULL DEFAULT 0.0,
        random_touch_count INTEGER NOT NULL DEFAULT 0,
        time_to_first_touch_ms REAL NOT NULL DEFAULT 0.0,
        time_to_completion_ms REAL NOT NULL DEFAULT 0.0,
        hint_count INTEGER NOT NULL DEFAULT 0,
        prompt_count INTEGER NOT NULL DEFAULT 0,
        retry_count INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        $_syncColumns,
        FOREIGN KEY (child_id) REFERENCES ${LocalTables.children}(id)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_sensory_round_metrics_child ON ${LocalTables.sensoryRoundMetrics}(child_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_sensory_round_metrics_sync ON ${LocalTables.sensoryRoundMetrics}(sync_status)
    ''');

    // Analyzed sensory preference results
    await db.execute('''
      CREATE TABLE ${LocalTables.sensoryPreferences} (
        id TEXT PRIMARY KEY,
        child_id TEXT NOT NULL,
        assessment_run_id TEXT,
        recommended_music_enabled INTEGER NOT NULL DEFAULT 0,
        recommended_haptic_enabled INTEGER NOT NULL DEFAULT 0,
        best_config TEXT NOT NULL,
        confidence TEXT NOT NULL,
        config_scores TEXT NOT NULL,
        attention_summary TEXT,
        analyzed_at TEXT NOT NULL,
        $_syncColumns,
        FOREIGN KEY (child_id) REFERENCES ${LocalTables.children}(id)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_sensory_preferences_child ON ${LocalTables.sensoryPreferences}(child_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_sensory_preferences_sync ON ${LocalTables.sensoryPreferences}(sync_status)
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

  /// Star Shop storage (STAR-E1, STAR-E2). Shared by `_onCreate` and the v17
  /// upgrade so a fresh install and a migrated one cannot drift apart.
  ///
  /// Note what is NOT here: a balance column. The balance is `SUM(delta)` over
  /// the ledger, because a mutable balance under last-write-wins sync silently
  /// discards stars a child watched themselves earn.
  Future<void> _createStarTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${LocalTables.starLedger} (
        id TEXT PRIMARY KEY,
        child_id TEXT NOT NULL,
        delta INTEGER NOT NULL,
        reason TEXT NOT NULL,
        game_session_id TEXT,
        item_id TEXT,
        created_at TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // The idempotency guarantee (STAR-E2): one payout per session per reason,
    // so a retried upload — which the sync layer does after any failure —
    // cannot pay a child twice. Partial index because purchase rows carry no
    // session id and must not collide with each other.
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_star_ledger_session
        ON ${LocalTables.starLedger}(child_id, game_session_id, reason)
        WHERE game_session_id IS NOT NULL
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_star_ledger_child
        ON ${LocalTables.starLedger}(child_id, created_at)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${LocalTables.childUnlocks} (
        child_id TEXT NOT NULL,
        item_id TEXT NOT NULL,
        unlocked_at TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (child_id, item_id)
      )
    ''');
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

    if (oldVersion < 4) {
      // Migration from v3 to v4: Add sex column to children table
      await db.execute(
        'ALTER TABLE ${LocalTables.children} ADD COLUMN sex TEXT',
      );
      debugPrint('[LocalDbService] Added sex column to children table');
    }

    if (oldVersion < 5) {
      // Migration from v4 to v5: Add extended sensory settings columns
      await db.execute(
        'ALTER TABLE ${LocalTables.children} ADD COLUMN music_volume REAL NOT NULL DEFAULT 0.5',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.children} ADD COLUMN sfx_volume REAL NOT NULL DEFAULT 0.7',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.children} ADD COLUMN animation_intensity REAL NOT NULL DEFAULT 1.0',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.children} ADD COLUMN prompt_speed REAL NOT NULL DEFAULT 1.0',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.children} ADD COLUMN sensory_preferences_set INTEGER NOT NULL DEFAULT 0',
      );
      debugPrint(
        '[LocalDbService] Added extended sensory settings columns to children table',
      );
    }

    if (oldVersion < 6) {
      // Migration from v5 to v6: Add reward preference columns
      await db.execute(
        "ALTER TABLE ${LocalTables.children} ADD COLUMN reward_preference TEXT NOT NULL DEFAULT 'bubbles'",
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.children} ADD COLUMN use_random_reward INTEGER NOT NULL DEFAULT 0',
      );
      debugPrint(
        '[LocalDbService] Added reward preference columns to children table',
      );
    }

    if (oldVersion < 7) {
      // Migration from v6 to v7: Add sensory persistence tables
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ${LocalTables.sensoryConsent} (
          id TEXT PRIMARY KEY,
          child_id TEXT NOT NULL,
          assessment_run_id TEXT,
          consent_given INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          sync_status TEXT NOT NULL DEFAULT 'pending',
          last_synced_at TEXT,
          deleted_at TEXT,
          updated_at TEXT NOT NULL,
          local_created_at TEXT NOT NULL,
          owner_id TEXT
        )
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_sensory_consent_child
        ON ${LocalTables.sensoryConsent}(child_id)
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_sensory_consent_sync
        ON ${LocalTables.sensoryConsent}(sync_status)
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS ${LocalTables.sensoryRoundMetrics} (
          id TEXT PRIMARY KEY,
          child_id TEXT NOT NULL,
          assessment_run_id TEXT,
          game_id TEXT NOT NULL,
          round_number INTEGER NOT NULL,
          music_enabled INTEGER NOT NULL DEFAULT 0,
          haptic_enabled INTEGER NOT NULL DEFAULT 0,
          sensory_purpose TEXT NOT NULL,
          correct_count INTEGER NOT NULL DEFAULT 0,
          wrong_count INTEGER NOT NULL DEFAULT 0,
          accuracy REAL NOT NULL DEFAULT 0.0,
          total_response_time_ms INTEGER NOT NULL DEFAULT 0,
          avg_response_time_ms REAL NOT NULL DEFAULT 0.0,
          tap_count INTEGER NOT NULL DEFAULT 0,
          idle_time_seconds REAL NOT NULL DEFAULT 0.0,
          random_touch_count INTEGER NOT NULL DEFAULT 0,
          time_to_first_touch_ms REAL NOT NULL DEFAULT 0.0,
          time_to_completion_ms REAL NOT NULL DEFAULT 0.0,
          hint_count INTEGER NOT NULL DEFAULT 0,
          prompt_count INTEGER NOT NULL DEFAULT 0,
          retry_count INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          sync_status TEXT NOT NULL DEFAULT 'pending',
          last_synced_at TEXT,
          deleted_at TEXT,
          updated_at TEXT NOT NULL,
          local_created_at TEXT NOT NULL,
          owner_id TEXT
        )
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_sensory_round_metrics_child
        ON ${LocalTables.sensoryRoundMetrics}(child_id)
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_sensory_round_metrics_sync
        ON ${LocalTables.sensoryRoundMetrics}(sync_status)
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS ${LocalTables.sensoryPreferences} (
          id TEXT PRIMARY KEY,
          child_id TEXT NOT NULL,
          assessment_run_id TEXT,
          recommended_music_enabled INTEGER NOT NULL DEFAULT 0,
          recommended_haptic_enabled INTEGER NOT NULL DEFAULT 0,
          best_config TEXT NOT NULL,
          confidence TEXT NOT NULL,
          config_scores TEXT NOT NULL,
          attention_summary TEXT,
          analyzed_at TEXT NOT NULL,
          sync_status TEXT NOT NULL DEFAULT 'pending',
          last_synced_at TEXT,
          deleted_at TEXT,
          updated_at TEXT NOT NULL,
          local_created_at TEXT NOT NULL,
          owner_id TEXT
        )
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_sensory_preferences_child
        ON ${LocalTables.sensoryPreferences}(child_id)
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_sensory_preferences_sync
        ON ${LocalTables.sensoryPreferences}(sync_status)
      ''');

      debugPrint('[LocalDbService] Added sensory persistence tables (v7)');
    }

    if (oldVersion < 8) {
      // Migration from v7 to v8: Recreate game_rounds_local with new schema
      // matching Supabase game_rounds table
      await db.execute('DROP TABLE IF EXISTS ${LocalTables.gameRounds}');
      await db.execute('''
        CREATE TABLE ${LocalTables.gameRounds} (
          id TEXT PRIMARY KEY,
          session_id TEXT NOT NULL,
          round_no INTEGER NOT NULL,
          stimulus_type TEXT,
          valid_action_type TEXT,
          correct INTEGER,
          response_time REAL,
          valid_response_time REAL,
          time_to_first_hint REAL,
          retry_count INTEGER DEFAULT 0,
          hint_count INTEGER DEFAULT 0,
          prompt_count INTEGER DEFAULT 0,
          random_touch_count INTEGER DEFAULT 0,
          strong_prompt_triggered INTEGER DEFAULT 0,
          guided_assist_triggered INTEGER DEFAULT 0,
          completed INTEGER DEFAULT 0,
          created_at TEXT,
          sync_status TEXT NOT NULL DEFAULT 'pending',
          last_synced_at TEXT,
          deleted_at TEXT,
          updated_at TEXT NOT NULL,
          local_created_at TEXT NOT NULL,
          owner_id TEXT,
          FOREIGN KEY (session_id) REFERENCES ${LocalTables.gameSessions}(id)
        )
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_game_rounds_session
        ON ${LocalTables.gameRounds}(session_id)
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_game_rounds_sync
        ON ${LocalTables.gameRounds}(sync_status)
      ''');
      debugPrint(
        '[LocalDbService] Recreated game_rounds_local with new schema (v8)',
      );
    }

    if (oldVersion < 9) {
      // Migration from v8 to v9: Add analytics + sensory columns to game_sessions_local
      await db.execute(
        'ALTER TABLE ${LocalTables.gameSessions} ADD COLUMN retry_count INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.gameSessions} ADD COLUMN hint_count INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.gameSessions} ADD COLUMN prompt_count INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.gameSessions} ADD COLUMN idle_time_seconds REAL NOT NULL DEFAULT 0.0',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.gameSessions} ADD COLUMN random_touch_count INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.gameSessions} ADD COLUMN avg_response_time REAL NOT NULL DEFAULT 0.0',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.gameSessions} ADD COLUMN avg_valid_response_time REAL NOT NULL DEFAULT 0.0',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.gameSessions} ADD COLUMN off_task_action_count INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.gameSessions} ADD COLUMN improvement_score REAL NOT NULL DEFAULT 0.0',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.gameSessions} ADD COLUMN consistency_score REAL NOT NULL DEFAULT 0.0',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.gameSessions} ADD COLUMN bg_music_enabled INTEGER NOT NULL DEFAULT 1',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.gameSessions} ADD COLUMN haptic_feedback_enabled INTEGER NOT NULL DEFAULT 1',
      );
      debugPrint(
        '[LocalDbService] Added analytics + sensory columns to game_sessions_local (v9)',
      );
    }

    if (oldVersion < 10) {
      // Migration from v9 to v10: Add sensory columns to game_rounds_local
      await db.execute(
        'ALTER TABLE ${LocalTables.gameRounds} ADD COLUMN music_enabled INTEGER NOT NULL DEFAULT 1',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.gameRounds} ADD COLUMN haptic_enabled INTEGER NOT NULL DEFAULT 1',
      );
      debugPrint(
        '[LocalDbService] Added sensory columns to game_rounds_local (v10)',
      );
    }

    if (oldVersion < 11) {
      // Migration from v10 to v11: Add rubric scoring columns to assessment_results_local
      await db.execute(
        'ALTER TABLE ${LocalTables.assessmentResults} ADD COLUMN play_skills_label TEXT',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.assessmentResults} ADD COLUMN communication_label TEXT',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.assessmentResults} ADD COLUMN social_interaction_label TEXT',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.assessmentResults} ADD COLUMN behavior_attention_label TEXT',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.assessmentResults} ADD COLUMN sensory_preference_label TEXT',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.assessmentResults} ADD COLUMN recommended_module TEXT',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.assessmentResults} ADD COLUMN overall_summary TEXT',
      );
      await db.execute(
        "ALTER TABLE ${LocalTables.assessmentResults} ADD COLUMN model_source TEXT DEFAULT 'rubric_based'",
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.assessmentResults} ADD COLUMN xgboost_ready INTEGER DEFAULT 1',
      );

      // Add missing telemetry columns to game_sessions_local
      await db.execute(
        'ALTER TABLE ${LocalTables.gameSessions} ADD COLUMN task_completion_rate REAL',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.gameSessions} ADD COLUMN prompt_dependency_score REAL',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.gameSessions} ADD COLUMN turn_taking_success_rate REAL',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.gameSessions} ADD COLUMN interruption_count INTEGER DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.gameSessions} ADD COLUMN waiting_tolerance_seconds REAL',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.gameSessions} ADD COLUMN time_to_first_touch REAL',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.gameSessions} ADD COLUMN time_to_first_valid_action REAL',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.gameSessions} ADD COLUMN time_to_completion REAL',
      );
      await db.execute(
        'ALTER TABLE ${LocalTables.gameSessions} ADD COLUMN sensory_condition TEXT',
      );

      debugPrint(
        '[LocalDbService] Added rubric scoring + telemetry columns (v11)',
      );
    }

    if (oldVersion < 12) {
      // Migration from v11 to v12: Add missing completed_at column to assessment_results_local
      await db.execute(
        'ALTER TABLE ${LocalTables.assessmentResults} ADD COLUMN completed_at TEXT',
      );
      debugPrint(
        '[LocalDbService] Added completed_at column to assessment_results_local (v12)',
      );
    }

    if (oldVersion < 13) {
      // Migration from v12 to v13: Add random_touch_count to assessment_results_local
      await db.execute(
        'ALTER TABLE ${LocalTables.assessmentResults} ADD COLUMN random_touch_count INTEGER NOT NULL DEFAULT 0',
      );
      debugPrint(
        '[LocalDbService] Added random_touch_count column to assessment_results_local (v13)',
      );
    }

    if (oldVersion < 14) {
      // Migration from v13 to v14: Add sync_error to all syncable tables.
      // markSyncFailed writes it, but existing databases were created before
      // the column existed, making the failure handler itself throw.
      const syncableTables = [
        LocalTables.children,
        LocalTables.assessmentRuns,
        LocalTables.gameSessions,
        LocalTables.gameRounds,
        LocalTables.sessionEvents,
        LocalTables.caregiverQuestionnaires,
        LocalTables.assessmentResults,
        LocalTables.moduleRecommendations,
        LocalTables.assessmentComparisons,
        LocalTables.sensoryConsent,
        LocalTables.sensoryRoundMetrics,
        LocalTables.sensoryPreferences,
      ];
      for (final table in syncableTables) {
        try {
          await db.execute('ALTER TABLE $table ADD COLUMN sync_error TEXT');
        } catch (_) {
          // Table missing or column already present — safe to skip.
        }
      }
      debugPrint(
        '[LocalDbService] Added sync_error column to syncable tables (v14)',
      );
    }

    if (oldVersion < 15) {
      // Migration from v14 to v15: Add sync_attempts to all syncable tables
      // so permanently failing records can be quarantined instead of
      // retrying forever.
      for (final table in SyncOrder.dependencyOrder) {
        try {
          await db.execute(
            'ALTER TABLE $table ADD COLUMN sync_attempts INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {
          // Table missing or column already present — safe to skip.
        }
      }
      debugPrint(
        '[LocalDbService] Added sync_attempts column to syncable tables (v15)',
      );
    }

    if (oldVersion < 16) {
      // Migration from v15 to v16: the parent can now pick a background-music
      // category. Existing children keep the calmest one, which is the safest
      // default for a child whose sensitivity has not been assessed.
      try {
        await db.execute(
          "ALTER TABLE ${LocalTables.children} ADD COLUMN music_category "
          "TEXT NOT NULL DEFAULT 'soft_relaxing'",
        );
      } catch (_) {
        // Column already present — safe to skip.
      }
      debugPrint(
        '[LocalDbService] Added music_category column to children (v16)',
      );
    }

    // Must stay LAST: earlier steps (v3) rebuild the children table wholesale,
    // and columns added before that runs would be dropped by it.
    if (oldVersion < 17) {
      await _createStarTables(db);
      for (final column in const [
        "character_id TEXT NOT NULL DEFAULT 'bps'",
        "equipped_costume TEXT NOT NULL DEFAULT 'none'",
      ]) {
        try {
          await db.execute(
            'ALTER TABLE ${LocalTables.children} ADD COLUMN $column',
          );
        } catch (_) {
          // Column already present — safe to skip, same as v16 above.
        }
      }
      // Existing children keep BPS, the character the app has always shown
      // them. A migration silently reassigning a familiar companion is exactly
      // the kind of surprise this feature is meant to avoid; the parent picks
      // deliberately from Settings instead (STAR-A2).
      debugPrint('[LocalDbService] v17: star ledger, unlocks, character');
    }
    if (oldVersion < 18) {
      try {
        await db.execute(
          'ALTER TABLE ${LocalTables.gameSessions} '
          'ADD COLUMN configuration_version TEXT',
        );
      } catch (_) {
        // Column already present — safe to skip.
      }
      debugPrint('[LocalDbService] v18: configuration_version column');
    }
  }

  // ─── Generic Sync Operations ──────────────────────────────────────────

  /// Shared predicate for records that still need uploading. Quarantined
  /// records (sync_attempts >= [maxSyncAttempts]) are excluded so they stop
  /// driving the retry loop.
  static const _needsSyncWhere =
      "sync_status IN ('pending', 'failed') AND deleted_at IS NULL "
      'AND sync_attempts < $maxSyncAttempts';

  /// Get all pending records for a table
  Future<List<Map<String, dynamic>>> getPendingRecords(String table) async {
    final db = await database;
    return db.query(
      table,
      where: _needsSyncWhere,
      orderBy: 'local_created_at ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getPendingChildRecords() async {
    final db = await database;
    return db.query(
      LocalTables.children,
      where: '$_needsSyncWhere AND $_syncableChildWhere',
      orderBy: 'local_created_at ASC',
    );
  }

  /// IDs of non-deleted children owned by [userId] (cheap, model-free)
  Future<List<String>> getChildIds(String userId) async {
    final db = await database;
    final rows = await db.query(
      LocalTables.children,
      columns: ['id'],
      where: 'user_id = ? AND deleted_at IS NULL',
      whereArgs: [userId],
    );
    return [for (final r in rows) r['id'] as String];
  }

  /// Merges cloud rows into the local table, newest version wins (AUM-158).
  ///
  /// The conflict rule, in one line: **the row with the later `updated_at`
  /// is kept, and a tie goes to the local copy.**
  ///
  /// Hydration used to be insert-only — any row that already existed locally
  /// was skipped. That is safe but not a conflict rule: an edit made on
  /// another device could never arrive, so a second device silently kept a
  /// stale copy forever and whichever device pushed last overwrote the
  /// cloud regardless of which edit was actually newer.
  ///
  /// Why a tie goes to local: equal timestamps mean neither side is newer,
  /// and the local row may be carrying an unsynced edit that is about to
  /// push. Keeping it loses nothing, while overwriting could.
  ///
  /// A local row is only replaced when the remote is *strictly* newer, so:
  /// * a locally deleted record is not resurrected by an older remote row
  ///   (the delete bumped `updated_at`);
  /// * a pending local edit survives unless the cloud genuinely holds a
  ///   later one, in which case the local edit is the stale version and
  ///   losing it is the point of the rule.
  ///
  /// A row whose timestamp is missing or unparseable on either side is left
  /// alone — without a comparable timestamp there is no basis to overwrite.
  ///
  /// Returns how many rows were written (inserted or updated).
  Future<int> hydrateRecords(
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return 0;
    final db = await database;
    final now = DateTime.now().toIso8601String();
    var written = 0;

    for (var i = 0; i < rows.length; i += _idChunkSize) {
      final chunk = rows.sublist(
        i,
        i + _idChunkSize > rows.length ? rows.length : i + _idChunkSize,
      );
      final ids = [for (final r in chunk) r['id'] as String];
      final placeholders = List.filled(ids.length, '?').join(',');
      final existing = await db.query(
        table,
        columns: ['id', 'updated_at'],
        where: 'id IN ($placeholders)',
        whereArgs: ids,
      );
      final localUpdatedAt = {
        for (final r in existing) r['id'] as String: r['updated_at'] as String?,
      };

      final batch = db.batch();
      for (final row in chunk) {
        final id = row['id'] as String;
        if (!localUpdatedAt.containsKey(id)) {
          batch.insert(table, {
            ...row,
            'sync_status': SyncStatus.synced.value,
            'last_synced_at': now,
          });
          written++;
          continue;
        }
        if (!_remoteIsNewer(localUpdatedAt[id], row['updated_at'])) continue;
        batch.update(
          table,
          {
            ...row,
            'sync_status': SyncStatus.synced.value,
            'last_synced_at': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        written++;
      }
      await batch.commit(noResult: true);
    }
    return written;
  }

  /// True when [remote] is strictly later than [local]. Unparseable or
  /// missing timestamps on either side mean "no", so the local row stands.
  static bool _remoteIsNewer(String? local, Object? remote) {
    if (local == null || remote is! String) return false;
    final localAt = DateTime.tryParse(local);
    final remoteAt = DateTime.tryParse(remote);
    if (localAt == null || remoteAt == null) return false;
    return remoteAt.isAfter(localAt);
  }

  /// Recover records stranded in 'syncing' by a crash or kill mid-sync.
  ///
  /// Pending queries only select pending/failed, so without this a record
  /// marked 'syncing' when the app died would never be retried. Call once
  /// on startup before the first sync.
  Future<int> resetStuckSyncing() async {
    final db = await database;
    var recovered = 0;
    for (final table in SyncOrder.dependencyOrder) {
      recovered += await db.update(
        table,
        {'sync_status': SyncStatus.pending.value},
        where: 'sync_status = ?',
        whereArgs: [SyncStatus.syncing.value],
      );
    }
    if (recovered > 0) {
      debugPrint('[LocalDbService] Recovered $recovered stuck syncing records');
    }
    return recovered;
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

  /// SQLite caps bound parameters (999 in older versions); chunk IN lists
  /// well below it.
  static const _idChunkSize = 500;

  /// Mark many records as syncing in one UPDATE per chunk
  Future<void> markSyncingBatch(String table, List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    for (var i = 0; i < ids.length; i += _idChunkSize) {
      final chunk = ids.sublist(
        i,
        i + _idChunkSize > ids.length ? ids.length : i + _idChunkSize,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      await db.update(
        table,
        {'sync_status': SyncStatus.syncing.value},
        where: 'id IN ($placeholders)',
        whereArgs: chunk,
      );
    }
  }

  /// Mark many records as synced in one UPDATE per chunk
  Future<void> markSyncedBatch(
    String table,
    List<String> ids, {
    DateTime? syncedAt,
  }) async {
    if (ids.isEmpty) return;
    final db = await database;
    final timestamp = (syncedAt ?? DateTime.now()).toIso8601String();
    for (var i = 0; i < ids.length; i += _idChunkSize) {
      final chunk = ids.sublist(
        i,
        i + _idChunkSize > ids.length ? ids.length : i + _idChunkSize,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      await db.update(
        table,
        {
          'sync_status': SyncStatus.synced.value,
          'sync_error': null,
          'sync_attempts': 0,
          'last_synced_at': timestamp,
        },
        where: 'id IN ($placeholders)',
        whereArgs: chunk,
      );
    }
  }

  /// Mark a record as synced
  Future<void> markSynced(String table, String id, {DateTime? syncedAt}) async {
    final db = await database;
    await db.update(
      table,
      {
        'sync_status': SyncStatus.synced.value,
        'sync_error': null,
        'sync_attempts': 0,
        'last_synced_at': (syncedAt ?? DateTime.now()).toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Mark a record as failed
  Future<void> markSyncFailed(String table, String id, {String? error}) async {
    final db = await database;
    await db.rawUpdate(
      '''
      UPDATE $table
      SET sync_status = ?,
          sync_attempts = sync_attempts + 1
          ${error != null ? ', sync_error = ?' : ''}
      WHERE id = ?
      ''',
      [SyncStatus.failed.value, if (error != null) error, id],
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
    // Only the children table has a user_id column; every other sync table
    // tracks ownership via owner_id alone. Referencing user_id on those
    // tables is a SQLITE_ERROR that aborts the whole guest backfill.
    final hasUserId = table == LocalTables.children;
    // Match by prefix as well as exactly: guest ids are minted as
    // `guest_<uuid>`, but callers backfill with the generic 'guest' prefix
    // (see SyncService.onUserAuthenticated) — exact matching alone would
    // never remap those rows.
    await db.update(
      table,
      {
        'owner_id': newOwnerId,
        if (hasUserId) 'user_id': newOwnerId,
        'updated_at': DateTime.now().toIso8601String(),
        'sync_status': SyncStatus.pending.value,
      },
      where:
          hasUserId
              ? 'owner_id = ? OR user_id = ? OR owner_id LIKE ? OR user_id LIKE ?'
              : 'owner_id = ? OR owner_id LIKE ?',
      whereArgs:
          hasUserId
              ? [oldOwnerId, oldOwnerId, '$oldOwnerId%', '$oldOwnerId%']
              : [oldOwnerId, '$oldOwnerId%'],
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
        WHERE $_needsSyncWhere
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

  /// Ids of children the parent deleted locally but whose deletion has not
  /// reached the cloud yet.
  ///
  /// Cloud hydration must skip these: the remote row still exists until the
  /// next successful sync, and re-inserting it would resurrect a profile the
  /// parent already removed.
  Future<Set<String>> getLocallyDeletedChildIds() async {
    final db = await database;
    final rows = await db.query(
      LocalTables.children,
      columns: ['id'],
      where: 'deleted_at IS NOT NULL',
    );
    return {for (final r in rows) r['id'] as String};
  }

  /// Every local table holding rows that belong to a single child.
  static const _childScopedTables = [
    LocalTables.assessmentRuns,
    LocalTables.gameSessions,
    LocalTables.caregiverQuestionnaires,
    LocalTables.assessmentResults,
    LocalTables.moduleRecommendations,
    LocalTables.assessmentComparisons,
    LocalTables.sensoryConsent,
    LocalTables.sensoryRoundMetrics,
    LocalTables.sensoryPreferences,
  ];

  /// Removes the local gameplay, assessment and recommendation rows of a
  /// deleted child.
  ///
  /// The child row itself is only soft-deleted, so the deletion can still be
  /// propagated to Supabase; its dependent rows go for good locally, because
  /// keeping a removed child's progress on the device serves nobody and the
  /// remote copies are removed with the child. Rows that hang off a game
  /// session (rounds, events) go with their sessions.
  Future<void> purgeChildScopedData(String childId) async {
    final db = await database;

    final sessions = await db.query(
      LocalTables.gameSessions,
      columns: ['id'],
      where: 'child_id = ?',
      whereArgs: [childId],
    );
    final sessionIds = [for (final r in sessions) r['id'] as String];

    for (var i = 0; i < sessionIds.length; i += _idChunkSize) {
      final chunk = sessionIds.sublist(
        i,
        i + _idChunkSize > sessionIds.length
            ? sessionIds.length
            : i + _idChunkSize,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      for (final table in [LocalTables.gameRounds, LocalTables.sessionEvents]) {
        await db.delete(
          table,
          where: 'session_id IN ($placeholders)',
          whereArgs: chunk,
        );
      }
    }

    for (final table in _childScopedTables) {
      await db.delete(table, where: 'child_id = ?', whereArgs: [childId]);
    }
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

    debugPrint(
      '[LocalDbService] insertGameSession map keys: ${map.keys.toList()}',
    );
    debugPrint('[LocalDbService] insertGameSession map: $map');
    try {
      await db.insert(
        LocalTables.gameSessions,
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint(
        '[LocalDbService] insertGameSession SUCCESS for id=${session.id}',
      );
    } catch (e, st) {
      debugPrint('[LocalDbService] insertGameSession FAILED: $e');
      debugPrint('[LocalDbService] insertGameSession stacktrace: $st');
      rethrow;
    }
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

  // ─── Game Rounds ───────────────────────────────────────────────────────

  /// Insert a single game round from [GameRoundMetrics] into the local DB.
  ///
  /// Maps game_core analytics fields to the Supabase-aligned local schema.
  Future<void> insertGameRound({
    required String sessionId,
    required GameRoundMetrics round,
    required String ownerId,
    bool markPending = true,
  }) async {
    final db = await database;
    final now = DateTime.now();
    final id = _uuid.v4();

    await db.insert(LocalTables.gameRounds, {
      'id': id,
      'session_id': sessionId,
      'round_no': round.roundNumber,
      'stimulus_type': round.gameSpecificData['stimulusType'] as String?,
      'valid_action_type': round.gameSpecificData['validActionType'] as String?,
      'correct': round.isSuccessful ? 1 : 0,
      'response_time': round.timeToFirstTouch,
      'valid_response_time': round.timeToFirstValidAction,
      'time_to_first_hint': round.hintCount > 0 ? round.timeToCompletion : null,
      'retry_count': round.retryCount,
      'hint_count': round.hintCount,
      'prompt_count': round.promptCount,
      'random_touch_count': round.randomTouchCount,
      'strong_prompt_triggered': round.promptCount >= 3 ? 1 : 0,
      'guided_assist_triggered': round.hintCount >= 2 ? 1 : 0,
      'completed': round.isSuccessful ? 1 : 0,
      'music_enabled': round.musicEnabled ? 1 : 0,
      'haptic_enabled': round.hapticEnabled ? 1 : 0,
      'created_at': now.toUtc().toIso8601String(),
      // sync columns
      'owner_id': ownerId,
      'sync_status':
          markPending ? SyncStatus.pending.value : SyncStatus.synced.value,
      'local_created_at': now.toUtc().toIso8601String(),
      'updated_at': now.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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

    debugPrint(
      '[LocalDbService] insertAssessmentResult map keys: ${map.keys.toList()}',
    );
    debugPrint('[LocalDbService] insertAssessmentResult map: $map');
    try {
      await db.insert(
        LocalTables.assessmentResults,
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint(
        '[LocalDbService] insertAssessmentResult SUCCESS for id=${result.id}',
      );
    } catch (e, st) {
      debugPrint('[LocalDbService] insertAssessmentResult FAILED: $e');
      debugPrint('[LocalDbService] insertAssessmentResult stacktrace: $st');
      rethrow;
    }
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

  /// Assessment runs for a child, newest first.
  Future<List<AssessmentRunRecord>> getAssessmentRuns({
    required String childId,
    bool includeDeleted = false,
  }) async {
    final db = await database;
    final conditions = ['child_id = ?'];
    final args = <Object?>[childId];
    if (!includeDeleted) {
      conditions.add('deleted_at IS NULL');
    }
    final rows = await db.query(
      LocalTables.assessmentRuns,
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: 'started_at DESC',
    );
    return rows.map((r) => AssessmentRunRecord.fromMap(r)).toList();
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

  // ─── Sensory Consent ───────────────────────────────────────────────────

  /// Insert a sensory consent record for a child.
  Future<void> insertSensoryConsent({
    required String childId,
    String? assessmentRunId,
    required bool consentGiven,
    String? ownerId,
  }) async {
    final db = await database;
    final now = DateTime.now();
    final id = _uuid.v4();

    await db.insert(LocalTables.sensoryConsent, {
      'id': id,
      'child_id': childId,
      'assessment_run_id': assessmentRunId,
      'consent_given': consentGiven ? 1 : 0,
      'created_at': now.toIso8601String(),
      'sync_status': SyncStatus.pending.value,
      'updated_at': now.toIso8601String(),
      'local_created_at': now.toIso8601String(),
      'owner_id': ownerId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Get the latest sensory consent record for a child.
  Future<Map<String, dynamic>?> getLatestSensoryConsent(String childId) async {
    final db = await database;
    final rows = await db.query(
      LocalTables.sensoryConsent,
      where: 'child_id = ? AND deleted_at IS NULL',
      whereArgs: [childId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  // ─── Sensory Round Metrics ─────────────────────────────────────────────

  /// Insert a batch of sensory round metrics for a child.
  Future<void> insertSensoryRoundMetrics({
    required String childId,
    String? assessmentRunId,
    required List<Map<String, dynamic>> metricsMapList,
    String? ownerId,
  }) async {
    final db = await database;
    final now = DateTime.now();

    await db.transaction((txn) async {
      for (final metricsMap in metricsMapList) {
        final id = _uuid.v4();
        await txn.insert(
          LocalTables.sensoryRoundMetrics,
          {
            'id': id,
            'child_id': childId,
            'assessment_run_id': assessmentRunId,
            'game_id': metricsMap['game_id'],
            'round_number': metricsMap['round_number'],
            'music_enabled': metricsMap['music_enabled'],
            'haptic_enabled': metricsMap['haptic_enabled'],
            'sensory_purpose': metricsMap['sensory_purpose'],
            'correct_count': metricsMap['correct_count'] ?? 0,
            'wrong_count': metricsMap['wrong_count'] ?? 0,
            'accuracy': metricsMap['accuracy'] ?? 0.0,
            'total_response_time_ms': metricsMap['total_response_time_ms'] ?? 0,
            'avg_response_time_ms': metricsMap['avg_response_time_ms'] ?? 0.0,
            'tap_count': metricsMap['tap_count'] ?? 0,
            'idle_time_seconds': metricsMap['idle_time_seconds'] ?? 0.0,
            'random_touch_count': metricsMap['random_touch_count'] ?? 0,
            'time_to_first_touch_ms':
                metricsMap['time_to_first_touch_ms'] ?? 0.0,
            'time_to_completion_ms': metricsMap['time_to_completion_ms'] ?? 0.0,
            'hint_count': metricsMap['hint_count'] ?? 0,
            'prompt_count': metricsMap['prompt_count'] ?? 0,
            'retry_count': metricsMap['retry_count'] ?? 0,
            'created_at': now.toIso8601String(),
            'sync_status': SyncStatus.pending.value,
            'updated_at': now.toIso8601String(),
            'local_created_at': now.toIso8601String(),
            'owner_id': ownerId,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// Get sensory round metrics for a child, optionally filtered by run.
  Future<List<Map<String, dynamic>>> getSensoryRoundMetrics({
    required String childId,
    String? assessmentRunId,
  }) async {
    final db = await database;
    final conditions = ['child_id = ?', 'deleted_at IS NULL'];
    final args = <Object?>[childId];

    if (assessmentRunId != null) {
      conditions.add('assessment_run_id = ?');
      args.add(assessmentRunId);
    }

    return db.query(
      LocalTables.sensoryRoundMetrics,
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at DESC',
    );
  }

  // ─── Sensory Preferences ──────────────────────────────────────────────

  /// Insert an analyzed sensory preference result for a child.
  Future<void> insertSensoryPreference({
    required String childId,
    String? assessmentRunId,
    required Map<String, dynamic> preferenceMap,
    String? ownerId,
  }) async {
    final db = await database;
    final now = DateTime.now();
    final id = _uuid.v4();

    // Serialize complex fields as JSON strings
    final configScores = preferenceMap['config_scores'];
    final attentionSummary = preferenceMap['attention_summary'];

    await db.insert(LocalTables.sensoryPreferences, {
      'id': id,
      'child_id': childId,
      'assessment_run_id': assessmentRunId,
      'recommended_music_enabled':
          preferenceMap['recommended_music_enabled'] ?? 0,
      'recommended_haptic_enabled':
          preferenceMap['recommended_haptic_enabled'] ?? 0,
      'best_config': preferenceMap['best_config'] ?? '',
      'confidence': preferenceMap['confidence'] ?? '',
      'config_scores':
          configScores is String ? configScores : jsonEncode(configScores),
      'attention_summary':
          attentionSummary is String
              ? attentionSummary
              : (attentionSummary != null
                  ? jsonEncode(attentionSummary)
                  : null),
      'analyzed_at': preferenceMap['analyzed_at'] ?? now.toIso8601String(),
      'sync_status': SyncStatus.pending.value,
      'updated_at': now.toIso8601String(),
      'local_created_at': now.toIso8601String(),
      'owner_id': ownerId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Get the latest sensory preference result for a child.
  Future<Map<String, dynamic>?> getLatestSensoryPreference(
    String childId,
  ) async {
    final db = await database;
    final rows = await db.query(
      LocalTables.sensoryPreferences,
      where: 'child_id = ? AND deleted_at IS NULL',
      whereArgs: [childId],
      orderBy: 'analyzed_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;

    // Deserialize JSON strings back to maps
    final row = Map<String, dynamic>.from(rows.first);
    if (row['config_scores'] is String) {
      row['config_scores'] = jsonDecode(row['config_scores'] as String);
    }
    if (row['attention_summary'] is String) {
      row['attention_summary'] = jsonDecode(row['attention_summary'] as String);
    }
    return row;
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
    await updateOwnerId(
      LocalTables.sensoryConsent,
      guestId,
      authenticatedUserId,
    );
    await updateOwnerId(
      LocalTables.sensoryRoundMetrics,
      guestId,
      authenticatedUserId,
    );
    await updateOwnerId(
      LocalTables.sensoryPreferences,
      guestId,
      authenticatedUserId,
    );

    debugPrint('[LocalDbService] Guest data backfill complete');
  }

  // ─── Guest User ID Migration ──────────────────────────────────────────

  /// Migrate child profiles (and related data) from an old guest user ID to a
  /// new one. This is used when the stored guest refresh token fails to restore
  /// and a brand-new anonymous account is created. Without this migration the
  /// child profiles keyed to the old user ID would be orphaned.
  Future<void> migrateGuestUserId(String oldUserId, String newUserId) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    // Update user_id (and owner_id where applicable) in the children table
    final updatedRows = await db.update(
      LocalTables.children,
      {
        'user_id': newUserId,
        'owner_id': newUserId,
        'updated_at': now,
        'sync_status': SyncStatus.pending.value,
      },
      where: 'user_id = ?',
      whereArgs: [oldUserId],
    );

    debugPrint(
      '[LocalDbService] migrateGuestUserId: $oldUserId -> $newUserId '
      '($updatedRows children rows updated)',
    );

    // Also migrate owner_id references in related tables so that sync and
    // backfill logic can still find them.
    for (final table in [
      LocalTables.assessmentRuns,
      LocalTables.gameSessions,
      LocalTables.gameRounds,
      LocalTables.sessionEvents,
      LocalTables.caregiverQuestionnaires,
      LocalTables.assessmentResults,
      LocalTables.moduleRecommendations,
      LocalTables.assessmentComparisons,
      LocalTables.sensoryConsent,
      LocalTables.sensoryRoundMetrics,
      LocalTables.sensoryPreferences,
    ]) {
      await db.update(
        table,
        {
          'owner_id': newUserId,
          'updated_at': now,
          'sync_status': SyncStatus.pending.value,
        },
        where: 'owner_id = ?',
        whereArgs: [oldUserId],
      );
    }

    debugPrint('[LocalDbService] Guest user ID migration complete');
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
