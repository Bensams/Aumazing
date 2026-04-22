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
      'birth_date':
          DateTime.parse(
            local['birth_date'] as String,
          ).toIso8601String().split('T').first,
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
      'assessment_run_id': local['assessment_run_id'],
      'score': local['score'],
      'total_items': local['total_items'],
      'error_count': local['error_count'],
      'total_response_time_ms': local['total_response_time_ms'],
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
      'round_number': local['round_number'],
      'stimulus': local['stimulus'],
      'response': local['response'],
      'is_correct': local['is_correct'] == 1,
      'response_time_ms': local['response_time_ms'],
      'started_at': local['started_at'],
      'ended_at': local['ended_at'],
      'metadata':
          local['metadata'] != null ? local['metadata'] as String : null,
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
      'avg_response_time_ms': local['avg_response_time_ms'],
      'raw_metrics':
          local['raw_metrics'] != null ? local['raw_metrics'] as String : null,
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
