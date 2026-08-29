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
    _TableSyncSpec.aggregated(
      LocalTables.assessmentResults,
      _groupAssessmentResultsForSupabase,
    ),
    _TableSyncSpec(
      LocalTables.moduleRecommendations,
      _mapRecommendationToSupabase,
    ),
    _TableSyncSpec(LocalTables.assessmentComparisons, _mapComparisonToSupabase),
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

    final groups = spec.group(records);

    // An aggregating spec may legitimately leave rows out (e.g. an
    // assessment result with no run has nowhere to go remotely). Settle them
    // here: left pending they would be retried on every pass forever, which
    // is exactly the failure this sync path used to exhibit.
    final grouped = {for (final g in groups) ...g.localIds};
    final skipped = [
      for (final r in records)
        if (!grouped.contains(r['id'] as String)) r['id'] as String,
    ];
    if (skipped.isNotEmpty) {
      debugPrint(
        '[SyncService] ${spec.localTable}: ${skipped.length} row(s) have no '
        'remote counterpart, settling them locally',
      );
      await _localDb.markSyncedBatch(spec.localTable, skipped);
    }

    for (var i = 0; i < groups.length; i += _uploadChunkSize) {
      final chunk = groups.sublist(
        i,
        i + _uploadChunkSize > groups.length
            ? groups.length
            : i + _uploadChunkSize,
      );
      final ids = [for (final g in chunk) ...g.localIds];
      final payload = [for (final g in chunk) g.payload];

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
        for (var j = 0; j < chunk.length; j++) {
          try {
            await _supabase.upsertBatch(remoteTable, [payload[j]]);
            succeeded.addAll(chunk[j].localIds);
          } catch (recordError) {
            failed++;
            for (final localId in chunk[j].localIds) {
              await _localDb.markSyncFailed(
                spec.localTable,
                localId,
                error: recordError.toString(),
              );
            }
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

  /// The child row as the cloud should hold it.
  ///
  /// Goes through the model rather than hand-picking columns (AUM-328). The
  /// hand-written version sent six fields and dropped the rest — character,
  /// costume, avatar, reward preference and every comfort setting were written
  /// locally, marked synced, and never left the device. Any field the model
  /// gains from here on is carried automatically; there is no second list to
  /// forget to update.
  ///
  /// `local` is a raw row, so `ChildProfile.fromMap` does the int→bool
  /// conversion SQLite needs and `toSupabase` does the bool→JSON one Postgres
  /// needs. The rows reaching here are already filtered by
  /// `_syncableChildWhere`, which guarantees the non-null `user_id` and
  /// `display_name` that `fromMap` requires.
  Map<String, dynamic> _mapChildToSupabase(Map<String, dynamic> local) {
    return ChildProfile.fromMap(local).toSupabase();
  }

  /// Local runs say `type: 'pre'`; the cloud CHECK constraint wants
  /// `assessment_type: 'pre_assessment'`. The two schemas were designed
  /// separately and every field below differs in name, value, or both —
  /// which is why every run upload was rejected with a 400, and with it
  /// every game_session and game_round that referenced the missing run.
  static const _remoteAssessmentType = {
    'pre': 'pre_assessment',
    'post': 'post_assessment',
    'follow_up': 'follow_up',
    'progress_check': 'progress_check',
  };

  Map<String, dynamic> _mapAssessmentRunToSupabase(Map<String, dynamic> local) {
    final localType = local['type'] as String?;
    return {
      'id': local['id'],
      'child_id': local['child_id'],
      // Fall back to the raw value rather than guessing: an unmapped type is
      // better rejected loudly by the CHECK than silently filed as a pre.
      'assessment_type': _remoteAssessmentType[localType] ?? localType,
      'started_at': local['started_at'],
      'ended_at': local['completed_at'],
      // Local tracks in_progress / completed / incomplete; the cloud keeps a
      // boolean. The open-vs-abandoned distinction only matters to the local
      // resume path (AUM-154), so it is not carried remotely.
      'completed': local['status'] == 'completed',
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

  /// Rubric label → ordinal level, per `20260512_per_area_levels.sql`:
  /// 0 = Needs Support, 1 = Emerging, 2 = Strength.
  static const _performanceLevel = {
    'Needs Support': 0,
    'Emerging': 1,
    'Strength': 2,
  };

  static const _attentionLevel = {
    'Needs Attention Support': 0,
    'Variable Attention': 1,
    'Sustained Attention': 2,
  };

  /// The inverses, for hydration. Built from the forward maps so the two
  /// directions can never drift apart.
  static final _performanceLabel = {
    for (final e in _performanceLevel.entries) e.value: e.key,
  };

  static final _attentionLabel = {
    for (final e in _attentionLevel.entries) e.value: e.key,
  };

  /// Collapse the per-game local results of each assessment run into the one
  /// cloud row that run is entitled to.
  ///
  /// Local `assessment_results_local` holds a row per mini-game (it carries
  /// `game_id`, `score`, `error_count`). Cloud `assessment_results` holds a
  /// row per run, keyed on `assessment_run_id NOT NULL`, carrying the four
  /// per-area ordinal levels for the battery as a whole. Uploading the local
  /// shape directly is what produced the 400s: of the columns being sent,
  /// only id / child_id / assessment_run_id existed remotely.
  ///
  /// The per-game numbers are not lost — `game_sessions` already carries
  /// them, and it is the table `get_child_report` reads for gameplay.
  ///
  /// The remote row reuses the run's uuid as its own id. That keeps the
  /// upsert idempotent as later games in the same run finish and re-sync,
  /// and it means `module_recommendations.source_assessment_id` — a FK to
  /// assessment_results, not to assessment_runs — can be satisfied with the
  /// run id the app already holds.
  List<_SyncGroup> _groupAssessmentResultsForSupabase(
    List<Map<String, dynamic>> records,
  ) {
    final byRun = <String, List<Map<String, dynamic>>>{};
    for (final r in records) {
      final runId = r['assessment_run_id'] as String?;
      // A result with no run is standalone practice scoring. There is no
      // remote row it could belong to, so it stays local.
      if (runId == null || runId.isEmpty) continue;
      byRun.putIfAbsent(runId, () => []).add(r);
    }

    final groups = <_SyncGroup>[];
    byRun.forEach((runId, rows) {
      // Latest scored row wins: the rubric labels describe the battery, and
      // every row of a run carries the same set, so the freshest is the one
      // written after the most games were seen.
      rows.sort((a, b) => (a['completed_at'] as String? ?? '')
          .compareTo(b['completed_at'] as String? ?? ''));
      final latest = rows.last;

      final completedAt = latest['completed_at'] as String?;
      final assessmentDate =
          (completedAt ?? latest['local_created_at'] as String? ?? '')
              .split('T')
              .first;

      groups.add(
        _SyncGroup(
          {
            'id': runId,
            'assessment_run_id': runId,
            'child_id': latest['child_id'],
            'assessment_date': assessmentDate,
            'communication_level':
                _performanceLevel[latest['communication_label']],
            'social_level':
                _performanceLevel[latest['social_interaction_label']],
            'play_level': _performanceLevel[latest['play_skills_label']],
            'attention_level':
                _attentionLevel[latest['behavior_attention_label']],
            // The four *_confidence columns stay null on purpose: rubric
            // scoring is rule-based and has no probability behind it. A
            // fabricated 1.0 would read to a SPED validator as model
            // certainty. They are for XGBoost, when it lands.
            if (latest['overall_summary'] != null)
              'notes': latest['overall_summary'],
            // overall_band is left unset — its vocabulary
            // (emerging/developing/progressing) is not something the rubric
            // computes, and inventing one would be a clinical claim the
            // assessment never made.
            // Passed as a Dart Map, NOT jsonEncode'd. PostgREST serializes
            // the whole payload, so a pre-encoded string lands in a jsonb
            // column as a jsonb *string* holding JSON — jsonb_typeof said
            // 'string' for every row uploaded so far, and nothing reading
            // the column could index into it.
            'summary_json': {
              'model_source': latest['model_source'],
              'xgboost_ready': (latest['xgboost_ready'] as int?) == 1,
              'sensory_preference_label': latest['sensory_preference_label'],
              'recommended_module': latest['recommended_module'],
              'per_game': [
                for (final r in rows)
                  {
                    'game_id': r['game_id'],
                    'score': r['score'],
                    'total_items': r['total_items'],
                    'error_count': r['error_count'],
                    'random_touch_count': r['random_touch_count'],
                    'avg_response_time_ms': r['avg_response_time_ms'],
                  },
              ],
            },
          },
          [for (final r in rows) r['id'] as String],
        ),
      );
    });

    return groups;
  }

  Map<String, dynamic> _mapRecommendationToSupabase(
    Map<String, dynamic> local,
  ) {
    return {
      'id': local['id'],
      'child_id': local['child_id'],
      // FK to assessment_results, NOT assessment_runs — the run id works
      // here only because the aggregated result row above is keyed on it.
      // Sending the run id to a column named *_assessment_id would otherwise
      // have traded the old 400 for a fresh FK violation.
      'source_assessment_id': local['assessment_run_id'],
      'top_module': local['module_id'],
      'recommended_by': 'rules',
      // `name` and `level` are the keys the beta portal reads off a path
      // step; `module_id` and `starting_level` are what the app stores. Both
      // spellings are sent so neither side has to guess.
      'recommended_path_json': [
        {
          'module_id': local['module_id'],
          'module_name': local['module_name'],
          'name': local['module_name'] ?? local['module_id'],
          'starting_level': local['starting_level'],
          'level': local['starting_level'],
        },
      ],
      'confidence': local['confidence'],
      if (local['rationale'] != null)
        'explanation_json': {'rationale': local['rationale']},
    };
  }

  /// Pre/post comparison — the payload AUM-330's beta report renders.
  ///
  /// Every column here was misnamed too; it had simply never failed because
  /// nothing writes `assessment_comparisons_local` yet, so no row ever
  /// reached the upload path. Fixed now so it does not become the next 400
  /// the moment comparisons start being produced.
  ///
  /// The two id columns are FKs to assessment_results. Local stores run ids
  /// in them, which resolve correctly because the aggregated result row is
  /// keyed on the run id.
  Map<String, dynamic> _mapComparisonToSupabase(Map<String, dynamic> local) {
    return {
      'id': local['id'],
      'child_id': local['child_id'],
      'baseline_assessment_result_id': local['pre_assessment_id'],
      'comparison_assessment_result_id': local['post_assessment_id'],
      'compared_at': local['local_created_at'],
      'accuracy_change': local['accuracy_improvement'],
      'response_time_change': local['response_time_improvement_ms'],
      'comparison_summary_json': {
        'summary': local['summary'],
        'overall_improvement_percent': local['overall_improvement_percent'],
      },
      // overall_progress_status is left unset: its vocabulary
      // (improved / maintained / needs_more_support / regression_observed)
      // is a clinical judgement, and the local row carries only a raw
      // improvement percentage. Deriving one here would invent a threshold
      // nobody has agreed.
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
        await _localDb.hydrateChild(
          ChildProfile.fromSupabase(remote),
          ownerId: userId,
        );
      }

      // 2. Child-scoped tables (remote + local child ids, deduped)
      final childIds = <String>{
        for (final r in remoteChildren)
          if (r['deleted_at'] == null) r['id'] as String,
        ...await _localDb.getChildIds(userId),
      }.where((id) => !locallyDeletedChildren.contains(id)).toList();

      if (childIds.isNotEmpty) {
        // Fetched rather than hydrated blind: the assessment_results
        // expansion below needs each run's type, which the cloud keeps on
        // the run and not on the result.
        final remoteRuns = await _supabase.fetchRowsByColumn(
          RemoteTables.assessmentRuns, 'child_id', childIds,
        );
        pulled += await _hydrateRows(
          LocalTables.assessmentRuns, remoteRuns, _mapAssessmentRunToLocal,
        );
        final runTypeById = <String, String>{
          for (final r in remoteRuns)
            if (r['deleted_at'] == null && r['id'] != null)
              r['id'] as String:
                  _localAssessmentType[r['assessment_type']] ??
                      (r['assessment_type'] as String? ?? 'pre'),
        };

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
        pulled += await _hydrateExpandedTable(
          LocalTables.assessmentResults, 'child_id', childIds,
          (r) => _expandAssessmentResultToLocal(r, runTypeById),
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

  /// [_hydrateTable] for a table whose local shape is finer-grained than the
  /// cloud's, so one remote row becomes zero, one, or many local rows.
  ///
  /// Only `assessment_results` needs this: the cloud keeps one row per run
  /// and the app keeps one per mini-game. An expander returning an empty
  /// list is how a remote row with nothing recoverable in it is dropped,
  /// rather than turned into a placeholder.
  Future<int> _hydrateExpandedTable(
    String localTable,
    String fkColumn,
    List<String> ids,
    List<Map<String, dynamic>> Function(Map<String, dynamic>) toLocalRows,
  ) async {
    final remoteTable = SyncOrder.getRemoteTable(localTable)!;
    final rows = await _supabase.fetchRowsByColumn(remoteTable, fkColumn, ids);
    final mapped = [
      for (final r in rows)
        if (r['deleted_at'] == null) ...toLocalRows(r),
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

  /// Cloud assessment type → the local run's `type`; the inverse of
  /// [_remoteAssessmentType].
  static const _localAssessmentType = {
    'pre_assessment': 'pre',
    'post_assessment': 'post',
    'follow_up': 'follow_up',
    'progress_check': 'progress_check',
  };

  /// The download mappers below carried the same schema mismatch the upload
  /// mappers did (AUM-330) — they read local column names off a cloud row, so
  /// every hydrated run came back as an in-progress 'pre' whatever it really
  /// was. Nothing had caught it because hydration only runs once, on a fresh
  /// install signing into an existing account.
  Map<String, dynamic> _mapAssessmentRunToLocal(Map<String, dynamic> r) => {
        'id': r['id'],
        'child_id': r['child_id'],
        'type': _localAssessmentType[r['assessment_type']] ??
            r['assessment_type'] ??
            'pre',
        'started_at': r['started_at'] ?? _nowIso(),
        'completed_at': r['ended_at'],
        'status': r['completed'] == true ? 'completed' : 'in_progress',
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
        'configuration_version': r['configuration_version'],
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

  /// One cloud `assessment_results` row -> one local row per mini-game.
  ///
  /// The faithful inverse of [_groupAssessmentResultsForSupabase]. The two
  /// tables differ in granularity, not just in naming: the cloud keeps ONE
  /// row per run carrying the four per-area ordinal levels for the battery,
  /// while the app keeps one row per mini-game carrying that game's numbers.
  /// The per-game detail survives the round trip in `summary_json.per_game`,
  /// which is exactly why the upload puts it there.
  ///
  /// This used to be a one-to-one mapper reading LOCAL column names off a
  /// cloud row -- `game_id`, `type`, `score`, the `*_label` columns, none of
  /// which the cloud has. Every hydrated result was therefore a placeholder
  /// (`game_id: 'unknown'`, type 'pre', score 0, no labels) that then showed
  /// up in the parent's history screen as an assessment the child never sat.
  ///
  /// Returns an empty list -- dropping the row rather than inventing one --
  /// when the run is unknown (its local FK could not be satisfied anyway) or
  /// when `per_game` is missing, which is the case for a row written by a
  /// pipeline that never recorded which games it summarised. The run itself
  /// and its `game_sessions` still hydrate, so the play is not lost; only
  /// the derived per-game result rows are.
  List<Map<String, dynamic>> _expandAssessmentResultToLocal(
    Map<String, dynamic> r,
    Map<String, String> runTypeById,
  ) {
    final runId = r['assessment_run_id'] as String?;
    final type = runId == null ? null : runTypeById[runId];
    if (runId == null || type == null) {
      debugPrint(
        '[SyncService] assessment_result ${r['id']}: no hydrated run, skipped',
      );
      return const [];
    }

    final summary = _asJsonMap(r['summary_json']);
    final perGame = summary['per_game'];
    if (perGame is! List || perGame.isEmpty) {
      debugPrint(
        '[SyncService] assessment_result ${r['id']}: no per_game detail, '
        'skipped rather than hydrated as a placeholder',
      );
      return const [];
    }

    // The cloud has no per-game completion time -- the aggregated row carries
    // one timestamp for the whole run -- so every game of a run hydrates with
    // the run row's own creation time. Ordering within a run is lost; the
    // run's game_sessions keep the real per-game timings.
    final completedAt =
        (r['created_at'] ?? r['updated_at'] ?? _nowIso()).toString();
    final labels = {
      'communication_label':
          _performanceLabel[_asLevel(r['communication_level'])],
      'social_interaction_label':
          _performanceLabel[_asLevel(r['social_level'])],
      'play_skills_label': _performanceLabel[_asLevel(r['play_level'])],
      'behavior_attention_label':
          _attentionLabel[_asLevel(r['attention_level'])],
      'sensory_preference_label': summary['sensory_preference_label'],
      'recommended_module': summary['recommended_module'],
      'overall_summary': r['notes'],
      'model_source': summary['model_source'] ?? 'rubric_based',
      'xgboost_ready': _asInt(summary['xgboost_ready'], fallback: 1),
    };

    final rows = <Map<String, dynamic>>[];
    for (final entry in perGame) {
      if (entry is! Map) continue;
      final gameId = entry['game_id'] as String?;
      if (gameId == null || gameId.isEmpty) continue;
      rows.add({
        // The local ids the upload aggregated away are not recoverable, so
        // one is synthesized from the pair that identifies the row. Stable,
        // so re-hydrating updates rather than duplicates, and it can never
        // collide with the uuids the app generates.
        'id': '$runId:$gameId',
        'child_id': r['child_id'],
        'assessment_run_id': runId,
        'game_id': gameId,
        'type': type,
        'score': entry['score'] ?? 0,
        'total_items': entry['total_items'] ?? 0,
        'error_count': entry['error_count'] ?? 0,
        'random_touch_count': entry['random_touch_count'] ?? 0,
        'avg_response_time_ms': entry['avg_response_time_ms'] ?? 0,
        'completed_at': completedAt,
        'raw_metrics': null,
        ...labels,
        ..._localMeta(r),
      });
    }
    return rows;
  }

  /// Remote jsonb -> Map. Tolerates the pre-fix rows already in the live
  /// database, which were uploaded pre-encoded and so are stored as a jsonb
  /// *string* holding JSON rather than as an object.
  static Map<String, dynamic> _asJsonMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is String && v.isNotEmpty) {
      try {
        final decoded = jsonDecode(v);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        // Not JSON after all -- treat as absent rather than failing the pull.
      }
    }
    return const {};
  }

  /// The ordinal area level, or null when the column was never scored.
  static int? _asLevel(dynamic v) => (v as num?)?.toInt();

  /// The cloud keeps the recommendation as one `recommended_path_json` step
  /// rather than as the app's flat columns, and `source_assessment_id` is the
  /// run id the aggregated result row is keyed on.
  Map<String, dynamic> _mapRecommendationToLocal(Map<String, dynamic> r) {
    final path = r['recommended_path_json'];
    final step = path is List && path.isNotEmpty && path.first is Map
        ? Map<String, dynamic>.from(path.first as Map)
        : const <String, dynamic>{};
    final explanation = r['explanation_json'];
    return {
      'id': r['id'],
      'child_id': r['child_id'],
      'assessment_run_id': r['source_assessment_id'] ?? '',
      'module_id': step['module_id'] ?? r['top_module'] ?? 'unknown',
      'module_name':
          step['module_name'] ?? step['name'] ?? r['top_module'] ?? 'Unknown',
      'starting_level': step['starting_level'] ?? step['level'] ?? 1,
      'confidence': r['confidence'],
      'rationale':
          explanation is Map ? explanation['rationale'] as String? : null,
      ..._localMeta(r),
    };
  }

  Map<String, dynamic> _mapComparisonToLocal(Map<String, dynamic> r) {
    final summary = r['comparison_summary_json'];
    final asMap = summary is Map
        ? Map<String, dynamic>.from(summary)
        : const <String, dynamic>{};
    return {
      'id': r['id'],
      'child_id': r['child_id'],
      'pre_assessment_id': r['baseline_assessment_result_id'] ?? '',
      'post_assessment_id': r['comparison_assessment_result_id'] ?? '',
      'accuracy_improvement': r['accuracy_change'],
      'response_time_improvement_ms':
          (r['response_time_change'] as num?)?.round(),
      'overall_improvement_percent': asMap['overall_improvement_percent'],
      'summary': asMap['summary'],
      ..._localMeta(r),
    };
  }

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
/// One remote row plus the local rows it stands for.
///
/// Usually one-to-one, but [_TableSyncSpec.toGroups] lets a table collapse
/// several local rows into a single remote row (see the assessment_results
/// aggregation), so marking sync state has to work on a set of local ids.
class _SyncGroup {
  final Map<String, dynamic> payload;
  final List<String> localIds;

  const _SyncGroup(this.payload, this.localIds);
}

class _TableSyncSpec {
  final String localTable;

  /// Per-row mapping. Null when the table aggregates instead.
  final Map<String, dynamic> Function(Map<String, dynamic>)? toSupabase;

  /// Whole-table mapping, for schemas where the local and remote row
  /// granularity differ. Receives every pending row for the table.
  final List<_SyncGroup> Function(List<Map<String, dynamic>>)? toGroups;

  const _TableSyncSpec(this.localTable, this.toSupabase) : toGroups = null;

  const _TableSyncSpec.aggregated(this.localTable, this.toGroups)
      : toSupabase = null;

  /// Group pending rows into the remote rows they map onto. Rows an
  /// aggregating spec deliberately omits are absent from the result; the
  /// caller settles those so they cannot sit pending forever.
  List<_SyncGroup> group(List<Map<String, dynamic>> records) {
    final mapper = toGroups;
    if (mapper != null) return mapper(records);
    final rowMapper = toSupabase!;
    return [
      for (final r in records) _SyncGroup(rowMapper(r), [r['id'] as String]),
    ];
  }
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
