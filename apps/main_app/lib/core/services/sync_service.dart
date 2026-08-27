import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../model/child_profile.dart';
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
  bool _disposed = false;

  /// Consecutive retry passes since the last fully successful sync;
  /// indexes into [_retryDelays] for exponential backoff.
  int _retryAttempt = 0;

  /// Escalating retry delays; the last entry repeats once reached.
  static const _retryDelays = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];

  /// Max records per remote upsert call, to bound payload size.
  static const _uploadChunkSize = 200;

  /// Debounce before a connectivity-triggered sync. Tests pass
  /// [Duration.zero] so reconnect does not wait the production 2s.
  final Duration syncDebounce;

  // Expose state for UI
  final _syncStateController = StreamController<SyncState>.broadcast();
  SyncState _currentState = SyncState.idle();

  SyncService({
    LocalDbService? localDb,
    SupabaseService? supabase,
    ConnectivityService? connectivity,
    this.syncDebounce = const Duration(seconds: 2),
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

    // Recover records stranded in 'syncing' by a crash mid-sync — pending
    // queries would otherwise never pick them up again.
    await _localDb.resetStuckSyncing();

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
      _retryAttempt = 0; // fresh connection, restart backoff
      _scheduleSync();
    } else {
      debugPrint('[SyncService] Offline - sync paused');
      _updateState(_currentState.copyWith(status: SyncStatusEnum.offline));
    }
  }

  /// Schedule a sync operation (debounced)
  void _scheduleSync() {
    _retryTimer?.cancel();
    _retryTimer = Timer(syncDebounce, () {
      if (_disposed) return;
      startSync();
    });
  }

  /// Start the sync process
  ///
  /// This is the main entry point for syncing. It processes records
  /// in dependency order to avoid foreign key violations.
  Future<void> startSync() async {
    if (_disposed) return;

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

    var synced = 0;
    var failed = 0;
    try {
      // Sync in dependency order (parents before children — FK safety)
      for (final spec in _tableSyncSpecs) {
        final result = await _syncTable(spec);
        synced += result.synced;
        failed += result.failed;
      }

      // Sync soft deletes last
      await _propagateDeletes();

      if (failed == 0) _retryAttempt = 0;
      _updateState(
        SyncState(
          status: SyncStatusEnum.completed,
          lastSuccessfulSync: failed == 0,
          syncedCount: synced,
          failedCount: failed,
        ),
      );
      debugPrint('[SyncService] Sync completed: $synced synced, $failed failed');
    } catch (e) {
      debugPrint('[SyncService] Sync failed: $e');
      _updateState(
        SyncState(
          status: SyncStatusEnum.error,
          error: e.toString(),
          syncedCount: synced,
          failedCount: failed,
        ),
      );
    } finally {
      try {
        // Keep isSyncing true until this check finishes so callers waiting
        // on it do not dispose the DB under a still-running query.
        if (!_disposed && _connectivity.isOnline) {
          final counts = await _localDb.getPendingCounts();
          final totalPending = counts.values.fold<int>(0, (a, b) => a + b);
          if (totalPending > 0) {
            _scheduleRetry();
          }
        }
      } finally {
        _isSyncing = false;
      }
    }
  }

  /// Schedule a retry with exponential backoff (30s → 1m → 5m → 15m)
  void _scheduleRetry() {
    _retryTimer?.cancel();
    final delay = _retryDelays[_retryAttempt.clamp(0, _retryDelays.length - 1)];
    _retryAttempt++;
    _retryTimer = Timer(delay, () {
      if (_disposed) return;
      startSync();
    });
    debugPrint('[SyncService] Scheduled retry in ${delay.inSeconds}s');
  }

  /// Update sync state and notify listeners
  void _updateState(SyncState state) {
    _currentState = state;
    if (_disposed) return;
    _syncStateController.add(state);
  }

  // ─── Generic Table Sync ───────────────────────────────────────────────

  /// One spec per syncable table, in FK dependency order.
  late final List<_TableSyncSpec> _tableSyncSpecs = [
    _TableSyncSpec(LocalTables.children, _mapChildToSupabase),
    _TableSyncSpec(LocalTables.assessmentRuns, _mapAssessmentRunToSupabase),
    _TableSyncSpec(LocalTables.gameSessions, _mapGameSessionToSupabase),
    _TableSyncSpec(LocalTables.gameRounds, _mapGameRoundToSupabase),
    _TableSyncSpec(LocalTables.sessionEvents, _mapSessionEventToSupabase),
    _TableSyncSpec(
      LocalTables.caregiverQuestionnaires,
      _mapQuestionnaireToSupabase,
    ),
    _TableSyncSpec(
      LocalTables.assessmentResults,
      _mapAssessmentResultToSupabase,
    ),
    _TableSyncSpec(
      LocalTables.moduleRecommendations,
      _mapRecommendationToSupabase,
    ),
    _TableSyncSpec(LocalTables.assessmentComparisons, _mapComparisonToSupabase),
    _TableSyncSpec(LocalTables.sensoryConsent, _mapSensoryConsentToSupabase),
    _TableSyncSpec(
      LocalTables.sensoryRoundMetrics,
      _mapSensoryRoundMetricsToSupabase,
    ),
    _TableSyncSpec(
      LocalTables.sensoryPreferences,
      _mapSensoryPreferencesToSupabase,
    ),
  ];

  /// Upload all pending records for one table: chunked batch upserts with a
  /// per-record fallback so a single bad row can't poison the whole batch.
  Future<_TableSyncResult> _syncTable(_TableSyncSpec spec) async {
    // Children have extra eligibility rules (guest-owned rows stay local)
    final records = spec.localTable == LocalTables.children
        ? await _localDb.getPendingChildRecords()
        : await _localDb.getPendingRecords(spec.localTable);
    if (records.isEmpty) return const _TableSyncResult(0, 0);

    final remoteTable = SyncOrder.getRemoteTable(spec.localTable)!;
    debugPrint(
      '[SyncService] Syncing ${records.length} records: ${spec.localTable}',
    );

    var synced = 0;
    var failed = 0;

    for (var i = 0; i < records.length; i += _uploadChunkSize) {
      final chunk = records.sublist(
        i,
        i + _uploadChunkSize > records.length
            ? records.length
            : i + _uploadChunkSize,
      );
      final ids = [for (final r in chunk) r['id'] as String];
      final payload = [for (final r in chunk) spec.toSupabase(r)];

      await _localDb.markSyncingBatch(spec.localTable, ids);

      try {
        await _supabase.upsertBatch(remoteTable, payload);
        await _localDb.markSyncedBatch(spec.localTable, ids);
        synced += ids.length;
      } catch (batchError) {
        // Batch rejected — retry per record so only the bad rows fail
        debugPrint(
          '[SyncService] Batch failed for ${spec.localTable}, '
          'falling back to per-record: $batchError',
        );
        final succeeded = <String>[];
        for (var j = 0; j < ids.length; j++) {
          try {
            await _supabase.upsertBatch(remoteTable, [payload[j]]);
            succeeded.add(ids[j]);
          } catch (recordError) {
            failed++;
            await _localDb.markSyncFailed(
              spec.localTable,
              ids[j],
              error: recordError.toString(),
            );
          }
        }
        await _localDb.markSyncedBatch(spec.localTable, succeeded);
        synced += succeeded.length;
      }
    }

    return _TableSyncResult(synced, failed);
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
      'configuration_version': local['configuration_version'],
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

  /// Force a sync now (bypasses debounce and resets retry backoff)
  Future<void> syncNow() {
    _retryAttempt = 0;
    return startSync();
  }

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

  // ─── Cloud → Local Hydration ──────────────────────────────────────────

  /// Pull the signed-in user's data from Supabase into the local DB.
  ///
  /// Covers reinstall and second-device sign-in, where the cloud has data
  /// the local DB doesn't. Rows are inserted as already-synced; existing
  /// local rows always win (pending edits are never overwritten, deleted
  /// records are never resurrected). Runs once per user per install unless
  /// [force] is true. Returns the number of records pulled.
  Future<int> hydrateFromCloud({bool force = false}) async {
    if (!_connectivity.isOnline || !_supabase.isAuthenticated) return 0;
    final userId = _supabase.currentUserId;
    if (userId == null) return 0;

    final prefs = await SharedPreferences.getInstance();
    final flagKey = 'cloud_hydrated_v1_$userId';
    if (!force && (prefs.getBool(flagKey) ?? false)) return 0;

    debugPrint('[SyncService] Hydrating local DB from cloud for $userId');
    var pulled = 0;
    try {
      // 1. Children — reuse the bootstrap upsert path (not marked pending)
      final remoteChildren = await _supabase.getChildren(userId);
      // Children deleted locally still exist remotely until _propagateDeletes
      // runs; re-inserting them here would resurrect a deleted profile.
      final locallyDeletedChildren = await _localDb.getLocallyDeletedChildIds();
      for (final remote in remoteChildren) {
        if (remote['deleted_at'] != null) continue;
        if (locallyDeletedChildren.contains(remote['id'])) continue;
        await _localDb.upsertChild(
          ChildProfile.fromSupabase(remote),
          ownerId: userId,
          markPending: false,
        );
      }

      // 2. Child-scoped tables (remote + local child ids, deduped)
      final childIds = <String>{
        for (final r in remoteChildren)
          if (r['deleted_at'] == null) r['id'] as String,
        ...await _localDb.getChildIds(userId),
      }.where((id) => !locallyDeletedChildren.contains(id)).toList();

      if (childIds.isNotEmpty) {
        pulled += await _hydrateTable(
          LocalTables.assessmentRuns, 'child_id', childIds,
          _mapAssessmentRunToLocal,
        );

        // Game sessions feed the session-scoped tables below
        final remoteSessions = await _supabase.fetchRowsByColumn(
          RemoteTables.gameSessions, 'child_id', childIds,
        );
        pulled += await _hydrateRows(
          LocalTables.gameSessions, remoteSessions, _mapGameSessionToLocal,
        );

        final sessionIds = [
          for (final s in remoteSessions)
            if (s['deleted_at'] == null) s['id'] as String,
        ];
        if (sessionIds.isNotEmpty) {
          pulled += await _hydrateTable(
            LocalTables.gameRounds, 'session_id', sessionIds,
            _mapGameRoundToLocal,
          );
          pulled += await _hydrateTable(
            LocalTables.sessionEvents, 'session_id', sessionIds,
            _mapSessionEventToLocal,
          );
        }

        pulled += await _hydrateTable(
          LocalTables.caregiverQuestionnaires, 'child_id', childIds,
          _mapQuestionnaireToLocal,
        );
        pulled += await _hydrateTable(
          LocalTables.assessmentResults, 'child_id', childIds,
          _mapAssessmentResultToLocal,
        );
        pulled += await _hydrateTable(
          LocalTables.moduleRecommendations, 'child_id', childIds,
          _mapRecommendationToLocal,
        );
        pulled += await _hydrateTable(
          LocalTables.assessmentComparisons, 'child_id', childIds,
          _mapComparisonToLocal,
        );
        pulled += await _hydrateTable(
          LocalTables.sensoryConsent, 'child_id', childIds,
          _mapSensoryConsentToLocal,
        );
        pulled += await _hydrateTable(
          LocalTables.sensoryRoundMetrics, 'child_id', childIds,
          _mapSensoryRoundMetricsToLocal,
        );
        pulled += await _hydrateTable(
          LocalTables.sensoryPreferences, 'child_id', childIds,
          _mapSensoryPreferencesToLocal,
        );
      }

      await prefs.setBool(flagKey, true);
      debugPrint('[SyncService] Hydration complete: $pulled records pulled');
    } catch (e) {
      // Leave the flag unset so the next sign-in/app start retries
      debugPrint('[SyncService] Hydration failed: $e');
    }
    return pulled;
  }

  /// Fetch one remote table scoped by [fkColumn] and insert missing rows
  Future<int> _hydrateTable(
    String localTable,
    String fkColumn,
    List<String> ids,
    Map<String, dynamic> Function(Map<String, dynamic>) toLocal,
  ) async {
    final remoteTable = SyncOrder.getRemoteTable(localTable)!;
    final rows = await _supabase.fetchRowsByColumn(remoteTable, fkColumn, ids);
    return _hydrateRows(localTable, rows, toLocal);
  }

  Future<int> _hydrateRows(
    String localTable,
    List<Map<String, dynamic>> remoteRows,
    Map<String, dynamic> Function(Map<String, dynamic>) toLocal,
  ) async {
    final mapped = [
      for (final r in remoteRows)
        if (r['deleted_at'] == null) toLocal(r),
    ];
    return _localDb.hydrateRecords(localTable, mapped);
  }

  // ─── Cloud → Local Mapping Helpers ────────────────────────────────────

  static String _nowIso() => DateTime.now().toIso8601String();

  /// Remote bool (or int) → SQLite int
  static int _asInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is bool) return v ? 1 : 0;
    if (v is int) return v == 0 ? 0 : 1;
    return fallback;
  }

  /// Remote jsonb (Map/List) or text → SQLite TEXT
  static String? _asJsonText(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    return jsonEncode(v);
  }

  /// Sync metadata every hydrated local row needs (NOT NULL columns)
  static Map<String, dynamic> _localMeta(Map<String, dynamic> r) => {
        'updated_at': r['updated_at'] ?? r['created_at'] ?? _nowIso(),
        'local_created_at': r['created_at'] ?? _nowIso(),
      };

  Map<String, dynamic> _mapAssessmentRunToLocal(Map<String, dynamic> r) => {
        'id': r['id'],
        'child_id': r['child_id'],
        'type': r['type'] ?? 'pre',
        'started_at': r['started_at'] ?? _nowIso(),
        'completed_at': r['completed_at'],
        'status': r['status'] ?? 'in_progress',
        ..._localMeta(r),
      };

  Map<String, dynamic> _mapGameSessionToLocal(Map<String, dynamic> r) => {
        'id': r['id'],
        'child_id': r['child_id'],
        'game_id': r['game_id'],
        'context': r['context'] ?? r['session_type'] ?? 'practice',
        'assessment_run_id': r['assessment_run_id'],
        'score': r['score'] ?? 0,
        'total_items': r['total_items'] ?? 0,
        'error_count': r['error_count'] ?? 0,
        'total_response_time_ms': r['total_response_time_ms'] ?? 0,
        'retry_count': r['retry_count'] ?? 0,
        'hint_count': r['hint_count'] ?? 0,
        'prompt_count': r['prompt_count'] ?? 0,
        'idle_time_seconds': r['idle_time_seconds'] ?? 0.0,
        'random_touch_count': r['random_touch_count'] ?? 0,
        'avg_response_time': r['avg_response_time'] ?? 0.0,
        'avg_valid_response_time': r['avg_valid_response_time'] ?? 0.0,
        'off_task_action_count': r['off_task_action_count'] ?? 0,
        'improvement_score': r['improvement_score'] ?? 0.0,
        'consistency_score': r['consistency_score'] ?? 0.0,
        'bg_music_enabled': _asInt(r['bg_music_enabled'], fallback: 1),
        'haptic_feedback_enabled':
            _asInt(r['haptic_feedback_enabled'], fallback: 1),
        'task_completion_rate': r['task_completion_rate'],
        'prompt_dependency_score': r['prompt_dependency_score'],
        'turn_taking_success_rate': r['turn_taking_success_rate'],
        'interruption_count': r['interruption_count'],
        'waiting_tolerance_seconds': r['waiting_tolerance_seconds'],
        'time_to_first_touch': r['time_to_first_touch'],
        'time_to_first_valid_action': r['time_to_first_valid_action'],
        'time_to_completion': r['time_to_completion'],
        'sensory_condition': r['sensory_condition'],
        'started_at': r['started_at'] ?? _nowIso(),
        'ended_at': r['ended_at'] ?? r['started_at'] ?? _nowIso(),
        'settings_snapshot': _asJsonText(r['settings_snapshot']),
        ..._localMeta(r),
      };

  Map<String, dynamic> _mapGameRoundToLocal(Map<String, dynamic> r) => {
        'id': r['id'],
        'session_id': r['session_id'],
        'round_no': r['round_no'] ?? 0,
        'stimulus_type': r['stimulus_type'],
        'valid_action_type': r['valid_action_type'],
        'correct': r['correct'] == null ? null : _asInt(r['correct']),
        'response_time': r['response_time'],
        'valid_response_time': r['valid_response_time'],
        'time_to_first_hint': r['time_to_first_hint'],
        'retry_count': r['retry_count'] ?? 0,
        'hint_count': r['hint_count'] ?? 0,
        'prompt_count': r['prompt_count'] ?? 0,
        'random_touch_count': r['random_touch_count'] ?? 0,
        'strong_prompt_triggered': _asInt(r['strong_prompt_triggered']),
        'guided_assist_triggered': _asInt(r['guided_assist_triggered']),
        'completed': _asInt(r['completed']),
        'music_enabled': _asInt(r['music_enabled'], fallback: 1),
        'haptic_enabled': _asInt(r['haptic_enabled'], fallback: 1),
        'created_at': r['created_at'],
        ..._localMeta(r),
      };

  Map<String, dynamic> _mapSessionEventToLocal(Map<String, dynamic> r) => {
        'id': r['id'],
        'session_id': r['session_id'],
        'event_type': r['event_type'] ?? 'unknown',
        'event_data': _asJsonText(r['event_data']),
        'occurred_at': r['occurred_at'] ?? _nowIso(),
        ..._localMeta(r),
      };

  Map<String, dynamic> _mapQuestionnaireToLocal(Map<String, dynamic> r) => {
        'id': r['id'],
        'child_id': r['child_id'],
        'questionnaire_type': r['questionnaire_type'] ?? 'unknown',
        'responses': _asJsonText(r['responses']) ?? '{}',
        'completed_at': r['completed_at'],
        ..._localMeta(r),
      };

  Map<String, dynamic> _mapAssessmentResultToLocal(Map<String, dynamic> r) => {
        'id': r['id'],
        'child_id': r['child_id'],
        'assessment_run_id': r['assessment_run_id'],
        'game_id': r['game_id'] ?? 'unknown',
        'type': r['type'] ?? 'pre',
        'score': r['score'] ?? 0,
        'total_items': r['total_items'] ?? 0,
        'error_count': r['error_count'] ?? 0,
        'random_touch_count': r['random_touch_count'] ?? 0,
        'avg_response_time_ms': r['avg_response_time_ms'] ?? 0,
        'completed_at': r['completed_at'],
        'raw_metrics': _asJsonText(r['raw_metrics']),
        'play_skills_label': r['play_skills_label'],
        'communication_label': r['communication_label'],
        'social_interaction_label': r['social_interaction_label'],
        'behavior_attention_label': r['behavior_attention_label'],
        'sensory_preference_label': r['sensory_preference_label'],
        'recommended_module': r['recommended_module'],
        'overall_summary': r['overall_summary'],
        'model_source': r['model_source'] ?? 'rubric_based',
        'xgboost_ready': _asInt(r['xgboost_ready'], fallback: 1),
        ..._localMeta(r),
      };

  Map<String, dynamic> _mapRecommendationToLocal(Map<String, dynamic> r) => {
        'id': r['id'],
        'child_id': r['child_id'],
        'assessment_run_id': r['assessment_run_id'] ?? '',
        'module_id': r['module_id'] ?? 'unknown',
        'module_name': r['module_name'] ?? 'Unknown',
        'starting_level': r['starting_level'] ?? 1,
        'confidence': r['confidence'],
        'rationale': r['rationale'],
        ..._localMeta(r),
      };

  Map<String, dynamic> _mapComparisonToLocal(Map<String, dynamic> r) => {
        'id': r['id'],
        'child_id': r['child_id'],
        'pre_assessment_id': r['pre_assessment_id'] ?? '',
        'post_assessment_id': r['post_assessment_id'] ?? '',
        'accuracy_improvement': r['accuracy_improvement'],
        'response_time_improvement_ms': r['response_time_improvement_ms'],
        'overall_improvement_percent': r['overall_improvement_percent'],
        'summary': r['summary'],
        ..._localMeta(r),
      };

  Map<String, dynamic> _mapSensoryConsentToLocal(Map<String, dynamic> r) => {
        'id': r['id'],
        'child_id': r['child_id'],
        'assessment_run_id': r['assessment_run_id'],
        'consent_given': _asInt(r['consent_given']),
        'created_at': r['created_at'] ?? _nowIso(),
        ..._localMeta(r),
      };

  Map<String, dynamic> _mapSensoryRoundMetricsToLocal(
    Map<String, dynamic> r,
  ) => {
        'id': r['id'],
        'child_id': r['child_id'],
        'assessment_run_id': r['assessment_run_id'],
        'game_id': r['game_id'] ?? 'unknown',
        'round_number': r['round_number'] ?? 0,
        'music_enabled': _asInt(r['music_enabled']),
        'haptic_enabled': _asInt(r['haptic_enabled']),
        'sensory_purpose': r['sensory_purpose'] ?? 'unknown',
        'correct_count': r['correct_count'] ?? 0,
        'wrong_count': r['wrong_count'] ?? 0,
        'accuracy': r['accuracy'] ?? 0.0,
        'total_response_time_ms': r['total_response_time_ms'] ?? 0,
        'avg_response_time_ms': r['avg_response_time_ms'] ?? 0.0,
        'tap_count': r['tap_count'] ?? 0,
        'idle_time_seconds': r['idle_time_seconds'] ?? 0.0,
        'random_touch_count': r['random_touch_count'] ?? 0,
        'time_to_first_touch_ms': r['time_to_first_touch_ms'] ?? 0.0,
        'time_to_completion_ms': r['time_to_completion_ms'] ?? 0.0,
        'hint_count': r['hint_count'] ?? 0,
        'prompt_count': r['prompt_count'] ?? 0,
        'retry_count': r['retry_count'] ?? 0,
        'created_at': r['created_at'] ?? _nowIso(),
        ..._localMeta(r),
      };

  Map<String, dynamic> _mapSensoryPreferencesToLocal(
    Map<String, dynamic> r,
  ) => {
        'id': r['id'],
        'child_id': r['child_id'],
        'assessment_run_id': r['assessment_run_id'],
        'recommended_music_enabled': _asInt(r['recommended_music_enabled']),
        'recommended_haptic_enabled': _asInt(r['recommended_haptic_enabled']),
        'best_config': r['best_config'] ?? '',
        'confidence': _asJsonText(r['confidence']) ?? '',
        'config_scores': _asJsonText(r['config_scores']) ?? '{}',
        'attention_summary': r['attention_summary'],
        'analyzed_at': r['analyzed_at'] ?? _nowIso(),
        ..._localMeta(r),
      };

  /// Handle user authentication change (backfill guest data)
  Future<void> onUserAuthenticated(
    String userId, {
    String? previousGuestUserId,
  }) async {
    // Backfill records from the guest identity that existed before auth.
    await _localDb.backfillGuestData(previousGuestUserId ?? 'guest', userId);

    // Trigger sync to upload backfilled data
    if (_connectivity.isOnline) {
      _scheduleSync();
    }
  }

  /// Dispose and clean up resources
  void dispose() {
    _disposed = true;
    _connectivitySubscription?.cancel();
    _retryTimer?.cancel();
    _syncStateController.close();
  }
}

/// Configuration for syncing one local table to its remote counterpart
class _TableSyncSpec {
  final String localTable;
  final Map<String, dynamic> Function(Map<String, dynamic>) toSupabase;

  const _TableSyncSpec(this.localTable, this.toSupabase);
}

/// Outcome of one table's sync pass
class _TableSyncResult {
  final int synced;
  final int failed;

  const _TableSyncResult(this.synced, this.failed);
}

/// Sync state for UI feedback
class SyncState {
  final SyncStatusEnum status;
  final bool lastSuccessfulSync;
  final String? error;
  final DateTime? timestamp;

  /// Records uploaded in the last completed pass
  final int syncedCount;

  /// Records that failed in the last completed pass (0 = clean sync)
  final int failedCount;

  const SyncState({
    required this.status,
    this.lastSuccessfulSync = false,
    this.error,
    this.timestamp,
    this.syncedCount = 0,
    this.failedCount = 0,
  });

  factory SyncState.idle() =>
      SyncState(status: SyncStatusEnum.idle, timestamp: DateTime.now());

  SyncState copyWith({
    SyncStatusEnum? status,
    bool? lastSuccessfulSync,
    String? error,
    DateTime? timestamp,
    int? syncedCount,
    int? failedCount,
  }) {
    return SyncState(
      status: status ?? this.status,
      lastSuccessfulSync: lastSuccessfulSync ?? this.lastSuccessfulSync,
      error: error ?? this.error,
      timestamp: timestamp ?? this.timestamp,
      syncedCount: syncedCount ?? this.syncedCount,
      failedCount: failedCount ?? this.failedCount,
    );
  }

  bool get isIdle => status == SyncStatusEnum.idle;
  bool get isSyncing => status == SyncStatusEnum.syncing;
  bool get isOffline => status == SyncStatusEnum.offline;
  bool get hasError => status == SyncStatusEnum.error;

  /// Completed, but some records failed and will be retried
  bool get hasPartialFailure =>
      status == SyncStatusEnum.completed && failedCount > 0;
}

enum SyncStatusEnum { idle, syncing, completed, offline, error }

/// Global instance for app-wide access
final syncService = SyncService();
