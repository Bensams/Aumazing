import 'dart:async';

import 'package:flutter/foundation.dart';

import '../sync/sync_status.dart';
import 'connectivity_service.dart';
import 'local_db_service.dart';
import 'supabase_service.dart';

/// Service that orchestrates synchronization between local SQLite and Supabase.
///
/// Key responsibilities:
/// - Monitors connectivity and triggers sync when online
/// - Syncs records in dependency order (children → assessments → sessions → rounds → events)
/// - Uses upsert to prevent duplicate records
/// - Handles soft deletes by propagating deleted_at to Supabase
/// - Retries failed records with exponential backoff
/// - Supports guest mode by backfilling owner IDs after auth
///
/// Usage:
/// ```dart
/// final syncService = SyncService();
/// await syncService.initialize();
/// // Sync happens automatically when online
/// ```
class SyncService {
  final LocalDbService _localDb;
  final SupabaseService _supabase;
  final ConnectivityService _connectivity;

  StreamSubscription<bool>? _connectivitySubscription;
  Timer? _retryTimer;
  bool _isSyncing = false;
  bool _isInitialized = false;

  // Expose state for UI
  final _syncStateController = StreamController<SyncState>.broadcast();
  SyncState _currentState = SyncState.idle();

  SyncService({
    LocalDbService? localDb,
    SupabaseService? supabase,
    ConnectivityService? connectivity,
  }) : _localDb = localDb ?? localDbService,
       _supabase = supabase ?? supabaseService,
       _connectivity = connectivity ?? connectivityService;

  /// Stream of sync state changes
  Stream<SyncState> get onSyncStateChanged => _syncStateController.stream;

  /// Current sync state
  SyncState get currentState => _currentState;

  /// Whether a sync is currently in progress
  bool get isSyncing => _isSyncing;

  /// Initialize and start listening to connectivity changes
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _connectivity.initialize();

    // Listen for connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
    );

    _isInitialized = true;
    debugPrint('[SyncService] Initialized');

    // If already online, trigger initial sync
    if (_connectivity.isOnline) {
      _scheduleSync();
    }
  }

  /// Handle connectivity changes
  void _onConnectivityChanged(bool isOnline) {
    if (isOnline) {
      debugPrint('[SyncService] Online - scheduling sync');
      _scheduleSync();
    } else {
      debugPrint('[SyncService] Offline - sync paused');
      _updateState(_currentState.copyWith(status: SyncStatusEnum.offline));
    }
  }

  /// Schedule a sync operation (debounced)
  void _scheduleSync() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 2), () {
      startSync();
    });
  }

  /// Start the sync process
  ///
  /// This is the main entry point for syncing. It processes records
  /// in dependency order to avoid foreign key violations.
  Future<void> startSync() async {
    if (_isSyncing) {
      debugPrint('[SyncService] Sync already in progress');
      return;
    }

    if (!_connectivity.isOnline) {
      debugPrint('[SyncService] Cannot sync - offline');
      return;
    }

    if (!_supabase.isAuthenticated) {
      debugPrint('[SyncService] Cannot sync - not authenticated');
      return;
    }

    _isSyncing = true;
    _updateState(const SyncState(status: SyncStatusEnum.syncing));

    try {
      // Sync in dependency order
      await _syncChildren();
      await _syncAssessmentRuns();
      await _syncGameSessions();
      await _syncGameRounds();
      await _syncSessionEvents();
      await _syncCaregiverQuestionnaires();
      await _syncAssessmentResults();
      await _syncModuleRecommendations();
      await _syncAssessmentComparisons();
      await _syncSensoryConsent();
      await _syncSensoryRoundMetrics();
      await _syncSensoryPreferences();

      // Sync soft deletes last
      await _propagateDeletes();

      _updateState(
        const SyncState(
          status: SyncStatusEnum.completed,
          lastSuccessfulSync: true,
        ),
      );
      debugPrint('[SyncService] Sync completed successfully');
    } catch (e) {
      debugPrint('[SyncService] Sync failed: $e');
      _updateState(
        SyncState(status: SyncStatusEnum.error, error: e.toString()),
      );
    } finally {
      _isSyncing = false;

      // Schedule retry if there are still pending records
      if (_connectivity.isOnline) {
        final counts = await _localDb.getPendingCounts();
        final totalPending = counts.values.fold<int>(0, (a, b) => a + b);
        if (totalPending > 0) {
          _scheduleRetry();
        }
      }
    }
  }

  /// Schedule a retry with exponential backoff
  void _scheduleRetry() {
    _retryTimer?.cancel();
    // Retry after 30 seconds
    _retryTimer = Timer(const Duration(seconds: 30), () {
      startSync();
    });
    debugPrint('[SyncService] Scheduled retry in 30s');
  }

  /// Update sync state and notify listeners
  void _updateState(SyncState state) {
    _currentState = state;
    _syncStateController.add(state);
  }

  // ─── Entity-Specific Sync Methods ─────────────────────────────────────

  Future<void> _syncChildren() async {
    final records = await _localDb.getPendingChildRecords();
    if (records.isEmpty) return;

    debugPrint('[SyncService] Syncing ${records.length} children');

    for (final record in records) {
      final id = record['id'] as String;
      try {
        await _localDb.markSyncing(LocalTables.children, id);

        // Convert local format to Supabase format
        final supabaseData = _mapChildToSupabase(record);
        await _supabase.upsertChild(supabaseData, id);

        await _localDb.markSynced(LocalTables.children, id);
      } catch (e) {
        debugPrint('[SyncService] Failed to sync child $id: $e');
        await _localDb.markSyncFailed(
          LocalTables.children,
          id,
          error: e.toString(),
        );
      }
    }
  }

  Future<void> _syncAssessmentRuns() async {
    final records = await _localDb.getPendingRecords(
      LocalTables.assessmentRuns,
    );
    if (records.isEmpty) return;

    debugPrint('[SyncService] Syncing ${records.length} assessment runs');

    for (final record in records) {
      final id = record['id'] as String;
      try {
        await _localDb.markSyncing(LocalTables.assessmentRuns, id);
        final supabaseData = _mapAssessmentRunToSupabase(record);
        await _supabase.upsertAssessmentRun(supabaseData, id);
        await _localDb.markSynced(LocalTables.assessmentRuns, id);
      } catch (e) {
        await _localDb.markSyncFailed(
          LocalTables.assessmentRuns,
          id,
          error: e.toString(),
        );
      }
    }
  }

  Future<void> _syncGameSessions() async {
    final records = await _localDb.getPendingRecords(LocalTables.gameSessions);
    if (records.isEmpty) return;

    debugPrint('[SyncService] Syncing ${records.length} game sessions');

    // Batch sync for better performance
    final batch = <Map<String, dynamic>>[];
    final ids = <String>[];

    for (final record in records) {
      final id = record['id'] as String;
      await _localDb.markSyncing(LocalTables.gameSessions, id);
      batch.add(_mapGameSessionToSupabase(record));
      ids.add(id);
    }

    try {
      await _supabase.upsertGameSessionsBatch(batch);
      for (final id in ids) {
        await _localDb.markSynced(LocalTables.gameSessions, id);
      }
    } catch (e) {
      // Fall back to individual syncs on batch failure
      for (final id in ids) {
        await _localDb.markSyncFailed(
          LocalTables.gameSessions,
          id,
          error: e.toString(),
        );
      }
    }
  }

  Future<void> _syncGameRounds() async {
    final records = await _localDb.getPendingRecords(LocalTables.gameRounds);
    if (records.isEmpty) return;

    debugPrint('[SyncService] Syncing ${records.length} game rounds');

    final batch = <Map<String, dynamic>>[];
    final ids = <String>[];

    for (final record in records) {
      final id = record['id'] as String;
      await _localDb.markSyncing(LocalTables.gameRounds, id);
      batch.add(_mapGameRoundToSupabase(record));
      ids.add(id);
    }

    try {
      await _supabase.upsertGameRoundsBatch(batch);
      for (final id in ids) {
        await _localDb.markSynced(LocalTables.gameRounds, id);
      }
    } catch (e) {
      for (final id in ids) {
        await _localDb.markSyncFailed(
          LocalTables.gameRounds,
          id,
          error: e.toString(),
        );
      }
    }
  }

  Future<void> _syncSessionEvents() async {
    final records = await _localDb.getPendingRecords(LocalTables.sessionEvents);
    if (records.isEmpty) return;

    debugPrint('[SyncService] Syncing ${records.length} session events');

    for (final record in records) {
      final id = record['id'] as String;
      try {
        await _localDb.markSyncing(LocalTables.sessionEvents, id);
        final supabaseData = _mapSessionEventToSupabase(record);
        await _supabase.upsertSessionEvent(supabaseData, id);
        await _localDb.markSynced(LocalTables.sessionEvents, id);
      } catch (e) {
        await _localDb.markSyncFailed(
          LocalTables.sessionEvents,
          id,
          error: e.toString(),
        );
      }
    }
  }

  Future<void> _syncCaregiverQuestionnaires() async {
    final records = await _localDb.getPendingRecords(
      LocalTables.caregiverQuestionnaires,
    );
    if (records.isEmpty) return;

    for (final record in records) {
      final id = record['id'] as String;
      try {
        await _localDb.markSyncing(LocalTables.caregiverQuestionnaires, id);
        final supabaseData = _mapQuestionnaireToSupabase(record);
        await _supabase.upsertCaregiverQuestionnaire(supabaseData, id);
        await _localDb.markSynced(LocalTables.caregiverQuestionnaires, id);
      } catch (e) {
        await _localDb.markSyncFailed(
          LocalTables.caregiverQuestionnaires,
          id,
          error: e.toString(),
        );
      }
    }
  }

  Future<void> _syncAssessmentResults() async {
    final records = await _localDb.getPendingRecords(
      LocalTables.assessmentResults,
    );
    if (records.isEmpty) return;

    debugPrint('[SyncService] Syncing ${records.length} assessment results');

    final batch = <Map<String, dynamic>>[];
    final ids = <String>[];

    for (final record in records) {
      final id = record['id'] as String;
      await _localDb.markSyncing(LocalTables.assessmentResults, id);
      batch.add(_mapAssessmentResultToSupabase(record));
      ids.add(id);
    }

    try {
      await _supabase.upsertAssessmentResultsBatch(batch);
      for (final id in ids) {
        await _localDb.markSynced(LocalTables.assessmentResults, id);
      }
    } catch (e) {
      for (final id in ids) {
        await _localDb.markSyncFailed(
          LocalTables.assessmentResults,
          id,
          error: e.toString(),
        );
      }
    }
  }

  Future<void> _syncModuleRecommendations() async {
    final records = await _localDb.getPendingRecords(
      LocalTables.moduleRecommendations,
    );
    if (records.isEmpty) return;

    for (final record in records) {
      final id = record['id'] as String;
      try {
        await _localDb.markSyncing(LocalTables.moduleRecommendations, id);
        final supabaseData = _mapRecommendationToSupabase(record);
        await _supabase.upsertModuleRecommendation(supabaseData, id);
        await _localDb.markSynced(LocalTables.moduleRecommendations, id);
      } catch (e) {
        await _localDb.markSyncFailed(
          LocalTables.moduleRecommendations,
          id,
          error: e.toString(),
        );
      }
    }
  }

  Future<void> _syncAssessmentComparisons() async {
    final records = await _localDb.getPendingRecords(
      LocalTables.assessmentComparisons,
    );
    if (records.isEmpty) return;

    for (final record in records) {
      final id = record['id'] as String;
      try {
        await _localDb.markSyncing(LocalTables.assessmentComparisons, id);
        final supabaseData = _mapComparisonToSupabase(record);
        await _supabase.upsertAssessmentComparison(supabaseData, id);
        await _localDb.markSynced(LocalTables.assessmentComparisons, id);
      } catch (e) {
        await _localDb.markSyncFailed(
          LocalTables.assessmentComparisons,
          id,
          error: e.toString(),
        );
      }
    }
  }

  Future<void> _syncSensoryConsent() async {
    final records = await _localDb.getPendingRecords(
      LocalTables.sensoryConsent,
    );
    if (records.isEmpty) return;

    debugPrint('[SyncService] Syncing ${records.length} sensory consent records');

    for (final record in records) {
      final id = record['id'] as String;
      try {
        await _localDb.markSyncing(LocalTables.sensoryConsent, id);
        final supabaseData = _mapSensoryConsentToSupabase(record);
        await _supabase.upsertSensoryConsent(supabaseData, id);
        await _localDb.markSynced(LocalTables.sensoryConsent, id);
      } catch (e) {
        await _localDb.markSyncFailed(
          LocalTables.sensoryConsent,
          id,
          error: e.toString(),
        );
      }
    }
  }

  Future<void> _syncSensoryRoundMetrics() async {
    final records = await _localDb.getPendingRecords(
      LocalTables.sensoryRoundMetrics,
    );
    if (records.isEmpty) return;

    debugPrint('[SyncService] Syncing ${records.length} sensory round metrics');

    for (final record in records) {
      final id = record['id'] as String;
      try {
        await _localDb.markSyncing(LocalTables.sensoryRoundMetrics, id);
        final supabaseData = _mapSensoryRoundMetricsToSupabase(record);
        await _supabase.upsertSensoryRoundMetrics(supabaseData, id);
        await _localDb.markSynced(LocalTables.sensoryRoundMetrics, id);
      } catch (e) {
        await _localDb.markSyncFailed(
          LocalTables.sensoryRoundMetrics,
          id,
          error: e.toString(),
        );
      }
    }
  }

  Future<void> _syncSensoryPreferences() async {
    final records = await _localDb.getPendingRecords(
      LocalTables.sensoryPreferences,
    );
    if (records.isEmpty) return;

    debugPrint('[SyncService] Syncing ${records.length} sensory preferences');

    for (final record in records) {
      final id = record['id'] as String;
      try {
        await _localDb.markSyncing(LocalTables.sensoryPreferences, id);
        final supabaseData = _mapSensoryPreferencesToSupabase(record);
        await _supabase.upsertSensoryPreferences(supabaseData, id);
        await _localDb.markSynced(LocalTables.sensoryPreferences, id);
      } catch (e) {
        await _localDb.markSyncFailed(
          LocalTables.sensoryPreferences,
          id,
          error: e.toString(),
        );
      }
    }
  }

  /// Propagate soft deletes to Supabase
  Future<void> _propagateDeletes() async {
    for (final table in SyncOrder.dependencyOrder.reversed) {
      final records = await _localDb.getDeletedRecords(table);
      if (records.isEmpty) continue;

      debugPrint(
        '[SyncService] Propagating ${records.length} deletions from $table',
      );

      final remoteTable = SyncOrder.getRemoteTable(table);
      if (remoteTable == null) continue;

      for (final record in records) {
        final id = record['id'] as String;
        try {
          await _supabase.softDeleteRemote(remoteTable, id);
          await _localDb.hardDelete(table, id);
        } catch (e) {
          debugPrint('[SyncService] Failed to propagate delete $table/$id: $e');
        }
      }
    }
  }

  // ─── Data Mapping Methods ────────────────────────────────────────────

  Map<String, dynamic> _mapChildToSupabase(Map<String, dynamic> local) {
    return {
      'id': local['id'],
      'parent_user_id': local['user_id'],
      'display_name': local['display_name'],
      'birth_date': local['birth_date'] != null
          ? DateTime.parse(
              local['birth_date'] as String,
            ).toIso8601String().split('T').first
          : null,
      'created_at': local['local_created_at'],
      'updated_at': local['updated_at'],
    };
  }

  Map<String, dynamic> _mapAssessmentRunToSupabase(Map<String, dynamic> local) {
    return {
      'id': local['id'],
      'child_id': local['child_id'],
      'type': local['type'],
      'started_at': local['started_at'],
      'completed_at': local['completed_at'],
      'status': local['status'],
    };
  }

  Map<String, dynamic> _mapGameSessionToSupabase(Map<String, dynamic> local) {
    return {
      'id': local['id'],
      'child_id': local['child_id'],
      'game_id': local['game_id'],
      'context': local['context'],
      // Remote schema requires session_type (NOT NULL); mirror context. A DB
      // trigger also defaults it server-side for older builds.
      'session_type': local['context'] ?? 'practice',
      'assessment_run_id': local['assessment_run_id'],
      'score': local['score'],
      'total_items': local['total_items'],
      'error_count': local['error_count'],
      'total_response_time_ms': local['total_response_time_ms'],
      'retry_count': local['retry_count'] ?? 0,
      'hint_count': local['hint_count'] ?? 0,
      'prompt_count': local['prompt_count'] ?? 0,
      'idle_time_seconds': local['idle_time_seconds'] ?? 0.0,
      'random_touch_count': local['random_touch_count'] ?? 0,
      'avg_response_time': local['avg_response_time'] ?? 0.0,
      'avg_valid_response_time': local['avg_valid_response_time'] ?? 0.0,
      'off_task_action_count': local['off_task_action_count'] ?? 0,
      'improvement_score': local['improvement_score'] ?? 0.0,
      'consistency_score': local['consistency_score'] ?? 0.0,
      'bg_music_enabled': (local['bg_music_enabled'] ?? 1) == 1,
      'haptic_feedback_enabled': (local['haptic_feedback_enabled'] ?? 1) == 1,
      // Rubric telemetry fields
      if (local['task_completion_rate'] != null)
        'task_completion_rate': local['task_completion_rate'],
      if (local['prompt_dependency_score'] != null)
        'prompt_dependency_score': local['prompt_dependency_score'],
      if (local['turn_taking_success_rate'] != null)
        'turn_taking_success_rate': local['turn_taking_success_rate'],
      if (local['interruption_count'] != null)
        'interruption_count': local['interruption_count'],
      if (local['waiting_tolerance_seconds'] != null)
        'waiting_tolerance_seconds': local['waiting_tolerance_seconds'],
      if (local['time_to_first_touch'] != null)
        'time_to_first_touch': local['time_to_first_touch'],
      if (local['time_to_first_valid_action'] != null)
        'time_to_first_valid_action': local['time_to_first_valid_action'],
      if (local['time_to_completion'] != null)
        'time_to_completion': local['time_to_completion'],
      if (local['sensory_condition'] != null)
        'sensory_condition': local['sensory_condition'],
      'started_at': local['started_at'],
      'ended_at': local['ended_at'],
      'settings_snapshot':
          local['settings_snapshot'] != null
              ? local['settings_snapshot'] as String
              : null,
    };
  }

  Map<String, dynamic> _mapGameRoundToSupabase(Map<String, dynamic> local) {
    return {
      'id': local['id'],
      'session_id': local['session_id'],
      'round_no': local['round_no'],
      'stimulus_type': local['stimulus_type'],
      'valid_action_type': local['valid_action_type'],
      'correct': (local['correct'] as int?) == 1,
      'response_time': local['response_time'],
      'valid_response_time': local['valid_response_time'],
      'time_to_first_hint': local['time_to_first_hint'],
      'retry_count': local['retry_count'] ?? 0,
      'hint_count': local['hint_count'] ?? 0,
      'prompt_count': local['prompt_count'] ?? 0,
      'random_touch_count': local['random_touch_count'] ?? 0,
      'strong_prompt_triggered': (local['strong_prompt_triggered'] as int?) == 1,
      'guided_assist_triggered': (local['guided_assist_triggered'] as int?) == 1,
      'completed': (local['completed'] as int?) == 1,
      'music_enabled': (local['music_enabled'] as int?) == 1,
      'haptic_enabled': (local['haptic_enabled'] as int?) == 1,
      'created_at': local['created_at'],
    };
  }

  Map<String, dynamic> _mapSessionEventToSupabase(Map<String, dynamic> local) {
    return {
      'id': local['id'],
      'session_id': local['session_id'],
      'event_type': local['event_type'],
      'event_data':
          local['event_data'] != null ? local['event_data'] as String : null,
      'occurred_at': local['occurred_at'],
    };
  }

  Map<String, dynamic> _mapQuestionnaireToSupabase(Map<String, dynamic> local) {
    return {
      'id': local['id'],
      'child_id': local['child_id'],
      'questionnaire_type': local['questionnaire_type'],
      'responses': local['responses'],
      'completed_at': local['completed_at'],
    };
  }

  Map<String, dynamic> _mapAssessmentResultToSupabase(
    Map<String, dynamic> local,
  ) {
    return {
      'id': local['id'],
      'child_id': local['child_id'],
      'assessment_run_id': local['assessment_run_id'],
      'game_id': local['game_id'],
      'type': local['type'],
      'score': local['score'],
      'total_items': local['total_items'],
      'error_count': local['error_count'],
      'random_touch_count': local['random_touch_count'] ?? 0,
      'avg_response_time_ms': local['avg_response_time_ms'],
      'completed_at': local['completed_at'],
      'raw_metrics':
          local['raw_metrics'] != null ? local['raw_metrics'] as String : null,
      // Rubric scoring fields
      if (local['play_skills_label'] != null)
        'play_skills_label': local['play_skills_label'],
      if (local['communication_label'] != null)
        'communication_label': local['communication_label'],
      if (local['social_interaction_label'] != null)
        'social_interaction_label': local['social_interaction_label'],
      if (local['behavior_attention_label'] != null)
        'behavior_attention_label': local['behavior_attention_label'],
      if (local['sensory_preference_label'] != null)
        'sensory_preference_label': local['sensory_preference_label'],
      if (local['recommended_module'] != null)
        'recommended_module': local['recommended_module'],
      if (local['overall_summary'] != null)
        'overall_summary': local['overall_summary'],
      if (local['model_source'] != null)
        'model_source': local['model_source'],
      if (local['xgboost_ready'] != null)
        'xgboost_ready': (local['xgboost_ready'] as int?) == 1,
    };
  }

  Map<String, dynamic> _mapRecommendationToSupabase(
    Map<String, dynamic> local,
  ) {
    return {
      'id': local['id'],
      'child_id': local['child_id'],
      'assessment_run_id': local['assessment_run_id'],
      'module_id': local['module_id'],
      'module_name': local['module_name'],
      'starting_level': local['starting_level'],
      'confidence': local['confidence'],
      'rationale': local['rationale'],
    };
  }

  Map<String, dynamic> _mapComparisonToSupabase(Map<String, dynamic> local) {
    return {
      'id': local['id'],
      'child_id': local['child_id'],
      'pre_assessment_id': local['pre_assessment_id'],
      'post_assessment_id': local['post_assessment_id'],
      'accuracy_improvement': local['accuracy_improvement'],
      'response_time_improvement_ms': local['response_time_improvement_ms'],
      'overall_improvement_percent': local['overall_improvement_percent'],
      'summary': local['summary'],
    };
  }

  Map<String, dynamic> _mapSensoryConsentToSupabase(Map<String, dynamic> local) {
    return {
      'id': local['id'],
      'child_id': local['child_id'],
      'assessment_run_id': local['assessment_run_id'],
      'consent_given': (local['consent_given'] as int?) == 1,
      'created_at': local['created_at'],
    };
  }

  Map<String, dynamic> _mapSensoryRoundMetricsToSupabase(Map<String, dynamic> local) {
    return {
      'id': local['id'],
      'child_id': local['child_id'],
      'assessment_run_id': local['assessment_run_id'],
      'game_id': local['game_id'],
      'round_number': local['round_number'],
      'music_enabled': (local['music_enabled'] as int?) == 1,
      'haptic_enabled': (local['haptic_enabled'] as int?) == 1,
      'sensory_purpose': local['sensory_purpose'],
      'correct_count': local['correct_count'] ?? 0,
      'wrong_count': local['wrong_count'] ?? 0,
      'accuracy': local['accuracy'] ?? 0.0,
      'total_response_time_ms': local['total_response_time_ms'] ?? 0,
      'avg_response_time_ms': local['avg_response_time_ms'] ?? 0.0,
      'tap_count': local['tap_count'] ?? 0,
      'idle_time_seconds': local['idle_time_seconds'] ?? 0.0,
      'random_touch_count': local['random_touch_count'] ?? 0,
      'time_to_first_touch_ms': local['time_to_first_touch_ms'] ?? 0.0,
      'time_to_completion_ms': local['time_to_completion_ms'] ?? 0.0,
      'hint_count': local['hint_count'] ?? 0,
      'prompt_count': local['prompt_count'] ?? 0,
      'retry_count': local['retry_count'] ?? 0,
      'created_at': local['created_at'],
    };
  }

  Map<String, dynamic> _mapSensoryPreferencesToSupabase(Map<String, dynamic> local) {
    return {
      'id': local['id'],
      'child_id': local['child_id'],
      'assessment_run_id': local['assessment_run_id'],
      'recommended_music_enabled': (local['recommended_music_enabled'] as int?) == 1,
      'recommended_haptic_enabled': (local['recommended_haptic_enabled'] as int?) == 1,
      'best_config': local['best_config'],
      'confidence': local['confidence'],
      'config_scores': local['config_scores'],
      'attention_summary': local['attention_summary'],
      'analyzed_at': local['analyzed_at'],
    };
  }

  // ─── Public API ───────────────────────────────────────────────────────

  /// Force a sync now (bypasses debounce)
  Future<void> syncNow() => startSync();

  /// Get pending sync counts for all tables
  Future<Map<String, int>> getPendingCounts() => _localDb.getPendingCounts();

  /// Get total pending count
  Future<int> getTotalPendingCount() async {
    final counts = await getPendingCounts();
    return counts.values.fold<int>(0, (a, b) => a + b);
  }

  /// Refresh cached reference data from Supabase
  Future<void> refreshReferenceCache() async {
    if (!_connectivity.isOnline || !_supabase.isAuthenticated) return;

    try {
      final modules = await _supabase.fetchLearningModules();
      await _localDb.cacheLearningModules(modules);

      final paths = await _supabase.fetchModulePaths();
      await _localDb.cacheModulePaths(paths);

      debugPrint('[SyncService] Reference cache refreshed');
    } catch (e) {
      debugPrint('[SyncService] Failed to refresh reference cache: $e');
    }
  }

  /// Handle user authentication change (backfill guest data)
  Future<void> onUserAuthenticated(String userId) async {
    // Backfill any guest-created records
    await _localDb.backfillGuestData('guest', userId);

    // Trigger sync to upload backfilled data
    if (_connectivity.isOnline) {
      _scheduleSync();
    }
  }

  /// Dispose and clean up resources
  void dispose() {
    _connectivitySubscription?.cancel();
    _retryTimer?.cancel();
    _syncStateController.close();
  }
}

/// Sync state for UI feedback
class SyncState {
  final SyncStatusEnum status;
  final bool lastSuccessfulSync;
  final String? error;
  final DateTime? timestamp;

  const SyncState({
    required this.status,
    this.lastSuccessfulSync = false,
    this.error,
    this.timestamp,
  });

  factory SyncState.idle() =>
      SyncState(status: SyncStatusEnum.idle, timestamp: DateTime.now());

  SyncState copyWith({
    SyncStatusEnum? status,
    bool? lastSuccessfulSync,
    String? error,
    DateTime? timestamp,
  }) {
    return SyncState(
      status: status ?? this.status,
      lastSuccessfulSync: lastSuccessfulSync ?? this.lastSuccessfulSync,
      error: error ?? this.error,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  bool get isIdle => status == SyncStatusEnum.idle;
  bool get isSyncing => status == SyncStatusEnum.syncing;
  bool get isOffline => status == SyncStatusEnum.offline;
  bool get hasError => status == SyncStatusEnum.error;
}

enum SyncStatusEnum { idle, syncing, completed, offline, error }

/// Global instance for app-wide access
final syncService = SyncService();
