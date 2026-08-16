import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:game_core/game_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/ai_assessment_response.dart';
import '../model/assessment_result.dart';
import '../model/assessment_run_snapshot.dart';
import '../model/gameplay_session.dart';
import '../model/support_profile.dart';
import '../features/pre_assessment/sensory/sensory_round_metrics.dart';
import '../model/area_level.dart';
import '../services/ai_assessment_service.dart';
import '../services/entitlement_service.dart';
import '../services/local_recommendation_rules.dart';
import '../services/on_device_ai_assessment_service.dart';
import '../services/research_consent_service.dart';
import '../services/support_profile_builder.dart';
import '../services/assessment_service.dart';
import '../core/services/connectivity_service.dart';
import '../core/services/local_db_service.dart' as core_db;
import '../services/rubric/rubric.dart';

/// Manages assessment state: collecting gameplay metrics, storing results,
/// and providing recommendation data.
///
/// Uses the offline-first [core_db.LocalDbService] so that all assessment
/// data is written with `sync_status = 'pending'` and automatically synced
/// to Supabase by the [SyncService].
class AssessmentProvider extends ChangeNotifier {
  // Lazily constructed so the provider can be created in widget tests
  // without a live Supabase instance (the defaults touch Supabase).
  AssessmentGateway? _assessmentServiceOverride;
  core_db.LocalDbService? _localDbOverride;

  AssessmentGateway get _assessmentService =>
      _assessmentServiceOverride ??= AssessmentService();
  core_db.LocalDbService get _localDb =>
      _localDbOverride ??= core_db.localDbService;

  List<AssessmentResult> _preResults = [];
  List<AssessmentResult> _postResults = [];
  Map<String, dynamic>? _recommendation;
  bool _isLoading = false;

  /// The child the dashboard data in this provider belongs to — set at the
  /// *start* of every [loadAssessments], cleared by [clear]. Every write that
  /// happens after an await re-checks it, so a slow load for a previous
  /// child can never overwrite the newly selected child's data (AUM-160).
  String? _loadedChildId;

  /// Bumped by every [loadAssessments] and [clear]; only the latest load may
  /// end the loading state.
  int _loadGeneration = 0;

  /// The sessions collected for the *current* assessment run only.
  ///
  /// Only sessions whose run id, child id and gameplay context all match the
  /// active run are kept here — see [recordGameSession]. Practice play and
  /// anything left over from an abandoned run can therefore never reach
  /// finalization or the model.
  final List<GameplaySession> _currentSessions = [];

  /// Per-round telemetry of the current run, keyed by game id.
  ///
  /// The sensory experiment needs the real rounds (not the game totals) to
  /// attribute performance to the sensory configuration that was actually
  /// active, so the analytics object travels alongside the session.
  final Map<String, GameSessionMetrics> _currentRunAnalytics = {};

  /// Dedupe keys for sessions already written during the current run, so a
  /// duplicate completion callback cannot produce a second record.
  final Set<String> _recordedSessionKeys = {};

  /// The ID of the current assessment run (created at the start of pre/post assessment).
  String? _currentAssessmentRunId;

  /// The child and type the active run belongs to — a session is only
  /// collected when it matches both.
  String? _currentRunChildId;
  String? _currentRunType;

  /// AI-based prediction result (null if API unavailable or not yet called).
  ///
  /// This is the *latest* prediction — after a post-assessment it describes
  /// the post run. Anything that needs the pre-assessment baseline must read
  /// [preSnapshot] instead.
  AiAssessmentResponse? _aiPrediction;

  /// Frozen records of the last completed pre and post runs.
  AssessmentRunSnapshot? _preSnapshot;
  AssessmentRunSnapshot? _postSnapshot;

  /// Why the last finalization failed, or null when it succeeded.
  String? _lastFinalizationError;

  /// Rubric-based scoring result (null if not yet computed).
  RubricResult? _rubricResult;

  /// Sensory round metrics collected during the pre-assessment sensory experiment.
  List<SensoryRoundMetrics>? _sensoryMetrics;

  /// The support profile finalized with the latest assessment run.
  ///
  /// Built once when the assessment completes and persisted, so the parent's
  /// later review shows the profile and recommendations *as finalized* rather
  /// than recomputing them from the child's current (mutable) settings.
  SupportProfile? _supportProfile;

  AssessmentProvider({
    AssessmentGateway? assessmentService,
    core_db.LocalDbService? localDb,
  }) : _assessmentServiceOverride = assessmentService,
       _localDbOverride = localDb;

  /// The gameplay context sessions of an assessment run carry.
  static String expectedContextFor(String type) =>
      type == 'post' ? 'post_assessment' : 'pre_assessment';

  /// The subset of [sessions] that genuinely belongs to one assessment run.
  ///
  /// Finalization and AI prediction go through here so a practice session, a
  /// session for a different child, or a leftover from a previous or
  /// abandoned run can never be scored as part of this one.
  static List<GameplaySession> sessionsForRun(
    Iterable<GameplaySession> sessions, {
    required String runId,
    required String childId,
    required String expectedContext,
  }) => [
    for (final session in sessions)
      if (session.assessmentRunId == runId &&
          session.childId == childId &&
          session.context == expectedContext)
        session,
  ];

  List<AssessmentResult> get preResults => _preResults;
  List<AssessmentResult> get postResults => _postResults;
  Map<String, dynamic>? get recommendation => _recommendation;
  bool get isLoading => _isLoading;

  /// The child the latest [loadAssessments] call was for, or null after
  /// [clear]. Lets callers verify whose data they are looking at.
  String? get loadedChildId => _loadedChildId;
  bool get hasPreAssessment => _preResults.isNotEmpty;
  bool get hasPostAssessment => _postResults.isNotEmpty;
  bool get hasRecommendation => _recommendation != null;

  /// Freemium cycle gate: the first assessment cycle (pre-assessment →
  /// recommended module → post-assessment) is free forever. Every learning
  /// path generated AFTER a post-assessment belongs to a later cycle and
  /// needs an active Premium period. Evaluated live off the entitlement,
  /// so an expired subscription re-locks it and a renewal re-opens it —
  /// no stored state to migrate.
  bool get nextCycleLocked =>
      hasPostAssessment && !EntitlementService.instance.isPremium;

  /// The latest AI prediction result, or null if unavailable.
  ///
  /// After a post-assessment this describes the *post* run. Use
  /// [preSnapshot] for the pre-assessment baseline.
  AiAssessmentResponse? get aiPrediction => _aiPrediction;

  /// The frozen pre-assessment run: its results, profile and its own
  /// prediction. Null when no pre-assessment has been finalized.
  AssessmentRunSnapshot? get preSnapshot => _preSnapshot;

  /// The frozen post-assessment run, or null when there is none.
  AssessmentRunSnapshot? get postSnapshot => _postSnapshot;

  /// Why the last finalization failed, or null when it succeeded.
  String? get lastFinalizationError => _lastFinalizationError;

  /// The latest rubric-based scoring result, or null if not yet computed.
  RubricResult? get rubricResult => _rubricResult;

  /// The support profile finalized with the latest assessment run, or null
  /// when no assessment has been finalized (or persisted) for this child.
  SupportProfile? get supportProfile => _supportProfile;

  /// The sessions collected during the current assessment round.
  List<GameplaySession> get currentSessions =>
      List.unmodifiable(_currentSessions);

  /// The current assessment run ID (available after [startAssessmentRun]).
  String? get currentAssessmentRunId => _currentAssessmentRunId;

  /// Whether an assessment run has been created and is accepting sessions.
  bool get hasActiveAssessmentRun => _currentAssessmentRunId != null;

  /// Per-round telemetry recorded for [gameId] during the current run.
  GameSessionMetrics? analyticsForGame(String gameId) =>
      _currentRunAnalytics[gameId];

  String? get recommendedModuleId => _recommendation?['module_id'] as String?;
  String? get recommendedModuleName =>
      _recommendation?['module_name'] as String?;
  int get recommendedLevel => (_recommendation?['starting_level'] as int?) ?? 1;

  /// Newest result per game — the local DB keeps every run's rows for
  /// history/sync, but the app should only ever score and display the
  /// latest run. A retake replaces results; it never stacks them.
  static List<AssessmentResult> latestPerGame(List<AssessmentResult> results) {
    final byGame = <String, AssessmentResult>{};
    for (final result in results) {
      final existing = byGame[result.gameId];
      if (existing == null ||
          result.completedAt.isAfter(existing.completedAt)) {
        byGame[result.gameId] = result;
      }
    }
    return byGame.values.toList();
  }

  /// Loads all assessment data for a child.
  ///
  /// Safe against child switches mid-load (AUM-160): the provider remembers
  /// which child the *latest* call was for, and every write below re-checks
  /// that after its awaits — a slower load for a previously selected child
  /// finishes without applying anything.
  Future<void> loadAssessments(String childId) async {
    final generation = ++_loadGeneration;
    if (_loadedChildId != null && _loadedChildId != childId) {
      // A different child without an explicit clear() in between — drop the
      // previous child's in-memory state now, so the "in-memory result wins"
      // restore guards below cannot carry it across children.
      _preResults = [];
      _postResults = [];
      _recommendation = null;
      _aiPrediction = null;
      _supportProfile = null;
      _preSnapshot = null;
      _postSnapshot = null;
      _pathCompleted = {};
    }
    _loadedChildId = childId;
    _isLoading = true;
    notifyListeners();

    try {
      // The locally persisted state (snapshots, profile, prediction) is
      // restored even when the results query fails, so an unreadable local
      // DB degrades to "no new rows" rather than to a blank summary.
      try {
        final pre = latestPerGame(
          await _localDb.getAssessmentResults(childId: childId, type: 'pre'),
        );
        final post = latestPerGame(
          await _localDb.getAssessmentResults(childId: childId, type: 'post'),
        );
        if (childId == _loadedChildId) {
          _preResults = pre;
          _postResults = post;
          _recommendation =
              _preResults.isEmpty
                  ? null
                  : _assessmentService.recommendModule(_preResults);
        }
      } catch (e) {
        debugPrint('[AssessmentProvider] result query failed: $e');
      }
      // A newer load (or clear()) took over while the queries ran — this
      // result belongs to a child no longer on screen.
      if (childId != _loadedChildId) return;

      // Restore the last AI prediction (area levels drive the learning path
      // and per-game difficulty; it only lives in memory otherwise).
      await _restoreAiPrediction(childId);
      await _restoreSupportProfile(childId);
      await _restoreSnapshots(childId);
      await _restorePathProgress(childId);

      // A rubric-synthesized prediction is provisional — try to replace it
      // with a real model prediction in the background now that we may be
      // back online. Fire-and-forget: the dashboard renders with the rubric
      // result and refreshes via notifyListeners() if the upgrade lands.
      unawaited(upgradeRubricPredictionIfOnline(childId));
    } catch (e) {
      debugPrint('[AssessmentProvider] loadAssessments error: $e');
    } finally {
      // Only the latest load may end the loading state — an older one
      // finishing here must not hide the spinner of the load in flight.
      if (generation == _loadGeneration) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  static String _aiPredictionKey(String childId) => 'ai_prediction_$childId';
  static String _aiPredictionSourceKey(String childId) =>
      'ai_prediction_source_$childId';
  static String _aiPredictionRunKey(String childId) =>
      'ai_prediction_run_$childId';
  static String _aiPredictionTypeKey(String childId) =>
      'ai_prediction_type_$childId';

  Future<void> _persistAiPrediction(
    String childId,
    AiAssessmentResponse prediction,
    String modelSource, {
    required String assessmentType,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _aiPredictionKey(childId),
        jsonEncode(prediction.toJson()),
      );
      // Remember which model produced it (from which run's sessions, and
      // whether that run was the pre or the post assessment) so a rubric
      // fallback can be upgraded to a real prediction later — and so the
      // upgrade relabels the right result set.
      await prefs.setString(_aiPredictionSourceKey(childId), modelSource);
      await prefs.setString(_aiPredictionTypeKey(childId), assessmentType);
      final runId = _currentAssessmentRunId;
      if (runId != null) {
        await prefs.setString(_aiPredictionRunKey(childId), runId);
      }
    } catch (e) {
      debugPrint('[AssessmentProvider] persistAiPrediction failed: $e');
    }
  }

  // ── Immutable per-run snapshots ───────────────────────────────────────

  static String _snapshotKey(String childId, String type) =>
      'assessment_snapshot_${type}_$childId';

  /// Freezes the just-finalized run: its results, the profile finalized with
  /// it, and the prediction made from its own sessions.
  ///
  /// Persisted per type, so the pre-assessment summary keeps showing the
  /// pre-assessment even after a post-assessment has replaced the "latest"
  /// prediction, and the post comparison always has a stable baseline.
  Future<AssessmentRunSnapshot> captureRunSnapshot(
    String childId, {
    required String assessmentType,
    AiAssessmentResponse? prediction,
    SupportProfile? profile,
  }) async {
    final results = assessmentType == 'post' ? _postResults : _preResults;
    final snapshot = AssessmentRunSnapshot(
      assessmentType: assessmentType,
      childId: childId,
      assessmentRunId: _currentAssessmentRunId,
      completedAt: DateTime.now(),
      results: List.unmodifiable(results),
      profile: profile ?? _supportProfile,
      prediction: prediction ?? _aiPrediction,
    );

    if (assessmentType == 'post') {
      _postSnapshot = snapshot;
    } else {
      _preSnapshot = snapshot;
      // A retake of the pre-assessment invalidates the old comparison.
      _postSnapshot = null;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _snapshotKey(childId, assessmentType),
        jsonEncode(snapshot.toJson()),
      );
      if (assessmentType == 'pre') {
        await prefs.remove(_snapshotKey(childId, 'post'));
      }
    } catch (e) {
      debugPrint('[AssessmentProvider] persistRunSnapshot failed: $e');
    }
    notifyListeners();
    return snapshot;
  }

  Future<void> _restoreSnapshots(String childId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      AssessmentRunSnapshot? read(String type) {
        final raw = prefs.getString(_snapshotKey(childId, type));
        if (raw == null) return null;
        return AssessmentRunSnapshot.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      }

      if (childId != _loadedChildId) return; // switched away mid-restore
      _preSnapshot ??= read('pre');
      _postSnapshot ??= read('post');
    } catch (e) {
      debugPrint('[AssessmentProvider] restoreSnapshots failed: $e');
    }
  }

  /// Upgrades a rubric-synthesized prediction to a real model prediction.
  ///
  /// When an assessment finishes offline, [predictWithAI] falls back to
  /// labels derived from the rubric (`modelSource == 'rubric_based'`) and
  /// that fallback would otherwise stick forever. Called on dashboard open
  /// ([loadAssessments]): when online, it re-runs the prediction over the
  /// original run's persisted sessions and replaces the stored fallback.
  /// No-op when the stored prediction already came from a real model, when
  /// still offline, or when the run's sessions can't be found. Path progress
  /// is kept — the upgrade refines levels, it isn't a new assessment.
  Future<void> upgradeRubricPredictionIfOnline(String childId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_aiPredictionSourceKey(childId)) != 'rubric_based') {
        return;
      }
      final runId = prefs.getString(_aiPredictionRunKey(childId));
      if (runId == null) return;
      if (!await connectivityService.checkConnectivity()) return;

      final sessions =
          (await _localDb.getGameSessions(
            childId: childId,
          )).where((s) => s.assessmentRunId == runId).toList();
      if (sessions.isEmpty) return;

      final onDevice = OnDeviceAiAssessmentService();
      final service = AiAssessmentService();
      try {
        var modelSource = 'xgboost_onnx';
        var prediction = await onDevice.predictFromSessions(
          childId: childId,
          sessions: sessions,
        );
        if (prediction == null) {
          modelSource = 'xgboost';
          prediction = await service.predictFromSessions(
            childId: childId,
            sessions: sessions,
          );
        }
        // Still unreachable — keep the rubric fallback and retry on the
        // next dashboard open.
        if (prediction == null) return;
        // The parent may have switched children while the model ran — the
        // upgraded prediction then belongs to a child no longer on screen,
        // and applying it would relabel the *new* child's results.
        if (childId != _loadedChildId) return;

        _aiPrediction = prediction;
        await prefs.setString(
          _aiPredictionKey(childId),
          jsonEncode(prediction.toJson()),
        );
        await prefs.setString(_aiPredictionSourceKey(childId), modelSource);
        // Relabel only the run the stored prediction actually came from —
        // upgrading a post-assessment prediction must not rewrite the
        // pre-assessment's model source.
        final storedType =
            prefs.getString(_aiPredictionTypeKey(childId)) ?? 'pre';
        if (storedType == 'post') {
          _postResults =
              _postResults
                  .map((r) => r.copyWithRubric(modelSource: modelSource))
                  .toList();
        } else {
          _preResults =
              _preResults
                  .map((r) => r.copyWithRubric(modelSource: modelSource))
                  .toList();
        }
        debugPrint(
          '[AssessmentProvider] ⬆️ Upgraded rubric_based prediction '
          'to $modelSource for child=$childId (run=$runId)',
        );
        notifyListeners();
      } finally {
        onDevice.dispose();
        service.dispose();
      }
    } catch (e) {
      debugPrint('[AssessmentProvider] upgradeRubricPrediction failed: $e');
    }
  }

  Future<void> _restoreAiPrediction(String childId) async {
    if (_aiPrediction != null) return; // in-memory result wins
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_aiPredictionKey(childId));
      if (raw == null) return;
      if (childId != _loadedChildId) return; // switched away mid-restore
      _aiPrediction = AiAssessmentResponse.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      debugPrint(
        '[AssessmentProvider] Restored persisted AI prediction '
        'for child=$childId',
      );
    } catch (e) {
      debugPrint('[AssessmentProvider] restoreAiPrediction failed: $e');
    }
  }

  static String _supportProfileKey(String childId) =>
      'support_profile_$childId';

  /// Builds and stores the support profile for the just-finalized run.
  ///
  /// Call once, after [finalizePreAssessment] and [predictWithAI], with the
  /// prediction that was actually used. The profile is persisted so the
  /// parent's later "Assessment Summary" renders the very same values — a
  /// retake overwrites it, matching how a retake replaces the results.
  Future<SupportProfile> finalizeSupportProfile(
    String childId, {
    AiAssessmentResponse? aiResponse,
  }) async {
    final profile = SupportProfileBuilder.build(
      rubric: _rubricResult,
      aiResponse: aiResponse ?? _aiPrediction,
    );
    _supportProfile = profile;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _supportProfileKey(childId),
        jsonEncode(profile.toMap()),
      );
    } catch (e) {
      debugPrint('[AssessmentProvider] persistSupportProfile failed: $e');
    }
    notifyListeners();
    return profile;
  }

  Future<void> _restoreSupportProfile(String childId) async {
    if (_supportProfile != null) return; // in-memory result wins
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_supportProfileKey(childId));
      if (raw == null) return;
      if (childId != _loadedChildId) return; // switched away mid-restore
      _supportProfile = SupportProfile.fromMap(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (e) {
      debugPrint('[AssessmentProvider] restoreSupportProfile failed: $e');
    }
  }

  /// Starts a new assessment run and stores the run ID.
  ///
  /// Run-scoped state is wiped *before* the run is created, so sessions,
  /// telemetry, rubric scores and sensory metrics left behind by a previous
  /// or abandoned run cannot contaminate this one. Callers must await this
  /// (and check it did not throw) before letting the child play: without a
  /// run id every session would be written unattached.
  ///
  /// Throws if the run could not be created; the provider is then left with
  /// no active run so the caller can offer a retry.
  Future<String> startAssessmentRun({
    required String childId,
    required String type,
  }) async {
    _resetRunState();
    notifyListeners();

    final runId = await _assessmentService.startAssessmentRun(
      childId: childId,
      type: type,
    );

    _currentAssessmentRunId = runId;
    _currentRunChildId = childId;
    _currentRunType = type;

    debugPrint(
      '[AssessmentProvider] Assessment run started: '
      '$runId (type: $type)',
    );
    notifyListeners();
    return runId;
  }

  /// Forgets everything scoped to a single assessment run.
  void _resetRunState() {
    _currentSessions.clear();
    _currentRunAnalytics.clear();
    _recordedSessionKeys.clear();
    _currentAssessmentRunId = null;
    _currentRunChildId = null;
    _currentRunType = null;
    _sensoryMetrics = null;
    _rubricResult = null;
    _lastFinalizationError = null;
  }

  /// Whether [context] is an assessment context (rather than free practice).
  static bool _isAssessmentContext(String context) =>
      context == 'pre_assessment' || context == 'post_assessment';

  /// Records a single mini-game session.
  ///
  /// Awaited by every game screen: the write must land before the flow treats
  /// the game as finished, otherwise a run can be finalized over sessions
  /// that were never persisted. Repeated calls for the same game *instance*
  /// (same start time) are ignored, so a duplicate completion callback cannot
  /// create a second record. Returns the recorded session, or the one already
  /// recorded for a duplicate call; rethrows on a failed write so the caller
  /// can offer a retry.
  Future<GameplaySession?> recordGameSession({
    required String childId,
    required String gameId,
    required String context,
    required int score,
    required int totalItems,
    required int errorCount,
    required int totalResponseTimeMs,
    required DateTime startedAt,
    GameSessionMetrics? analytics,
    bool bgMusicEnabled = true,
    bool hapticFeedbackEnabled = true,
    bool applySessionSensoryDefaults = true,
  }) async {
    // Practice play is never part of an assessment run — tagging it with the
    // active run id is what let practice sessions reach finalization.
    final isAssessment = _isAssessmentContext(context);
    final runId = isAssessment ? _currentAssessmentRunId : null;

    final key =
        '${runId ?? 'none'}|$childId|$gameId|$context'
        '|${startedAt.microsecondsSinceEpoch}';
    if (_recordedSessionKeys.contains(key)) {
      debugPrint(
        '[AssessmentProvider] Duplicate completion for $gameId '
        'ignored (session already recorded)',
      );
      for (final session in _currentSessions) {
        if (session.gameId == gameId && session.startedAt == startedAt) {
          return session;
        }
      }
      return null;
    }
    _recordedSessionKeys.add(key);

    final GameplaySession session;
    try {
      session = await _assessmentService.recordSession(
        childId: childId,
        gameId: gameId,
        context: context,
        score: score,
        totalItems: totalItems,
        errorCount: errorCount,
        totalResponseTimeMs: totalResponseTimeMs,
        startedAt: startedAt,
        assessmentRunId: runId,
        analytics: analytics,
        bgMusicEnabled: bgMusicEnabled,
        hapticFeedbackEnabled: hapticFeedbackEnabled,
        applySessionSensoryDefaults: applySessionSensoryDefaults,
      );
    } catch (e) {
      // Nothing was written — let the caller try again.
      _recordedSessionKeys.remove(key);
      debugPrint('[AssessmentProvider] recordGameSession failed: $e');
      rethrow;
    }

    // Collect only what belongs to the active run.
    final runType = _currentRunType;
    if (isAssessment &&
        runId != null &&
        runType != null &&
        childId == _currentRunChildId &&
        context == expectedContextFor(runType)) {
      _currentSessions.add(session);
      if (analytics != null) _currentRunAnalytics[gameId] = analytics;
    }

    // Practice completions advance the learning path (sequential unlock).
    if (context == 'practice') {
      await markPathGameCompleted(childId, gameId);
    }
    notifyListeners();
    return session;
  }

  // ── Learning-path progress (sequential unlock) ─────────────────────────

  /// Game ids the child has completed on the current learning path.
  Set<String> get pathCompletedGameIds => Set.unmodifiable(_pathCompleted);
  Set<String> _pathCompleted = {};

  static String _pathProgressKey(String childId) => 'path_progress_$childId';

  /// Marks a path game as completed and persists the progress.
  Future<void> markPathGameCompleted(String childId, String gameId) async {
    if (!_pathCompleted.add(gameId)) return; // already recorded
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _pathProgressKey(childId),
        _pathCompleted.toList(),
      );
    } catch (e) {
      debugPrint('[AssessmentProvider] persist path progress failed: $e');
    }
  }

  Future<void> _restorePathProgress(String childId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (childId != _loadedChildId) return; // switched away mid-restore
      _pathCompleted =
          (prefs.getStringList(_pathProgressKey(childId)) ?? const []).toSet();
    } catch (e) {
      debugPrint('[AssessmentProvider] restore path progress failed: $e');
    }
  }

  /// Clears path progress — called when a new assessment produces a new
  /// path, so the child starts the new sequence from step 1.
  Future<void> _resetPathProgress(String childId) async {
    _pathCompleted = {};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pathProgressKey(childId));
    } catch (e) {
      debugPrint('[AssessmentProvider] reset path progress failed: $e');
    }
  }

  /// Set sensory round metrics collected during the sensory experiment.
  ///
  /// Call this before [finalizePreAssessment] so rubric scoring can
  /// incorporate sensory preference analysis.
  void setSensoryMetrics(List<SensoryRoundMetrics> metrics) {
    _sensoryMetrics = metrics;
  }

  /// The sessions of the active run, filtered to those that really belong
  /// to it. Empty when there is no active run.
  List<GameplaySession> runSessions() {
    final runId = _currentAssessmentRunId;
    final childId = _currentRunChildId;
    final type = _currentRunType;
    if (runId == null || childId == null || type == null) return const [];
    return sessionsForRun(
      _currentSessions,
      runId: runId,
      childId: childId,
      expectedContext: expectedContextFor(type),
    );
  }

  /// Finalizes the pre-assessment after all 4 mini-games are played.
  ///
  /// Creates assessment results and generates a recommendation. Returns false
  /// — and leaves [lastFinalizationError] set — when there is no active run,
  /// when the run collected no usable sessions, or when a write failed. The
  /// caller must not present a successful result in that case.
  Future<bool> finalizePreAssessment(String childId) async {
    _isLoading = true;
    _lastFinalizationError = null;
    notifyListeners();

    try {
      final sessions = runSessions();
      if (_currentAssessmentRunId == null) {
        _lastFinalizationError = 'No assessment run was started.';
        return false;
      }
      if (sessions.isEmpty) {
        _lastFinalizationError =
            'No gameplay sessions were recorded for this assessment.';
        debugPrint(
          '[AssessmentProvider] finalizePreAssessment: no sessions '
          'for run $_currentAssessmentRunId',
        );
        return false;
      }

      // Group sessions by game and create assessment results
      final gameIds = sessions.map((s) => s.gameId).toSet();
      for (final gameId in gameIds) {
        final gameSessions = sessions.where((s) => s.gameId == gameId).toList();
        final result = await _assessmentService.createAssessmentResult(
          childId: childId,
          type: 'pre',
          gameId: gameId,
          sessions: gameSessions,
          assessmentRunId: _currentAssessmentRunId,
        );
        _preResults.add(result);
      }
      // Retake: the new run's results replace the previous run's.
      _preResults = latestPerGame(_preResults);

      _recommendation = _assessmentService.recommendModule(_preResults);

      // --- Rubric Scoring (new) ---
      try {
        const rubricScorer = RubricScoringService();
        const sensoryAnalyzer = SensoryLabelAnalyzer();
        const recommender = RecommendationService();

        // Get sensory label if metrics are available
        final sensoryLabel =
            _sensoryMetrics != null && _sensoryMetrics!.isNotEmpty
                ? sensoryAnalyzer.analyze(_sensoryMetrics!)
                : SensoryPreferenceLabel.noSensorySupportNeeded;

        // Score all areas — from this run's sessions only.
        final playSkills = rubricScorer.scorePlaySkills(sessions);
        final communication = rubricScorer.scoreCommunication(sessions);
        final socialInteraction = rubricScorer.scoreSocialInteraction(sessions);
        final behaviorAttention = rubricScorer.scoreBehaviorAttention(sessions);

        // Get recommendation
        final recommendation = recommender.recommend(
          playSkills: playSkills,
          communication: communication,
          socialInteraction: socialInteraction,
          behaviorAttention: behaviorAttention,
          sensoryPreference: sensoryLabel,
        );

        // Generate summary
        final summary = recommender.generateSummary(
          playSkills: playSkills,
          communication: communication,
          socialInteraction: socialInteraction,
          behaviorAttention: behaviorAttention,
          sensoryPreference: sensoryLabel,
          recommendedModule: recommendation.moduleName,
        );

        // Create rubric result
        _rubricResult = RubricResult(
          playSkillsLabel: playSkills,
          communicationLabel: communication,
          socialInteractionLabel: socialInteraction,
          behaviorAttentionLabel: behaviorAttention,
          sensoryPreferenceLabel: sensoryLabel,
          recommendedModule: recommendation.moduleName,
          overallSummary: summary,
        );

        // Update assessment results with rubric labels (immutable — replace list)
        _preResults =
            _preResults
                .map(
                  (result) => result.copyWithRubric(
                    playSkillsLabel: playSkills.displayName,
                    communicationLabel: communication.displayName,
                    socialInteractionLabel: socialInteraction.displayName,
                    behaviorAttentionLabel: behaviorAttention.displayName,
                    sensoryPreferenceLabel: sensoryLabel.displayName,
                    recommendedModule: recommendation.moduleName,
                    overallSummary: summary,
                    modelSource: 'rubric_based',
                    xgboostReady: true,
                  ),
                )
                .toList();

        debugPrint(
          '[AssessmentProvider] Rubric scoring complete: '
          'playSkills=${playSkills.displayName}, '
          'communication=${communication.displayName}, '
          'socialInteraction=${socialInteraction.displayName}, '
          'behaviorAttention=${behaviorAttention.displayName}, '
          'sensory=${sensoryLabel.displayName}, '
          'recommended=${recommendation.moduleName}',
        );
      } catch (e) {
        // Rubric scoring failure should not break the existing flow
        debugPrint('[AssessmentProvider] Rubric scoring failed: $e');
      }

      // Note: _currentSessions are NOT cleared here so they remain
      // available for the AI prediction call (predictWithAI).
      // They are cleared in clear() or after AI prediction.

      // Mark the assessment run as completed
      if (_currentAssessmentRunId != null) {
        await _assessmentService.completeAssessmentRun(
          _currentAssessmentRunId!,
        );
      }

      debugPrint(
        '[AssessmentProvider] Pre-assessment finalized. '
        'Recommended: ${_recommendation?['module_name']} '
        'Level ${_recommendation?['starting_level']}',
      );
      return true;
    } catch (e) {
      _lastFinalizationError = 'Could not save the assessment results.';
      debugPrint('[AssessmentProvider] finalizePreAssessment error: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Finalizes the post-assessment and computes improvement.
  ///
  /// Returns the comparison map. `has_data` is false — and
  /// [lastFinalizationError] is set — when there is no active run, when the
  /// run collected no usable sessions, when a write failed, or when there is
  /// no pre-assessment to compare against.
  Future<Map<String, dynamic>> finalizePostAssessment(String childId) async {
    _isLoading = true;
    _lastFinalizationError = null;
    notifyListeners();

    try {
      final sessions = runSessions();
      if (_currentAssessmentRunId == null) {
        _lastFinalizationError = 'No assessment run was started.';
        return {'has_data': false};
      }
      if (sessions.isEmpty) {
        _lastFinalizationError =
            'No gameplay sessions were recorded for this assessment.';
        debugPrint(
          '[AssessmentProvider] finalizePostAssessment: no sessions '
          'for run $_currentAssessmentRunId',
        );
        return {'has_data': false};
      }

      final gameIds = sessions.map((s) => s.gameId).toSet();
      for (final gameId in gameIds) {
        final gameSessions = sessions.where((s) => s.gameId == gameId).toList();
        final result = await _assessmentService.createAssessmentResult(
          childId: childId,
          type: 'post',
          gameId: gameId,
          sessions: gameSessions,
          assessmentRunId: _currentAssessmentRunId,
        );
        _postResults.add(result);
      }
      // Retake: the new run's results replace the previous run's.
      _postResults = latestPerGame(_postResults);

      // Mark the assessment run as completed
      await _assessmentService.completeAssessmentRun(_currentAssessmentRunId!);

      // Re-score the rubric from the post sessions so the AI fallback and
      // profile reflect the child's NEW performance, not the pre-assessment.
      try {
        const rubricScorer = RubricScoringService();
        _rubricResult = RubricResult(
          playSkillsLabel: rubricScorer.scorePlaySkills(sessions),
          communicationLabel: rubricScorer.scoreCommunication(sessions),
          socialInteractionLabel: rubricScorer.scoreSocialInteraction(sessions),
          behaviorAttentionLabel: rubricScorer.scoreBehaviorAttention(sessions),
          sensoryPreferenceLabel:
              _rubricResult?.sensoryPreferenceLabel ??
              SensoryPreferenceLabel.noSensorySupportNeeded,
          recommendedModule: _rubricResult?.recommendedModule ?? '',
          overallSummary: 'Post-assessment rubric scoring.',
        );
      } catch (e) {
        debugPrint('[AssessmentProvider] post rubric scoring failed: $e');
      }

      // NOTE: _currentSessions is intentionally NOT cleared here — the
      // subsequent predictWithAI call needs the post sessions for the new
      // AI prediction and clears them itself (same contract as the pre
      // flow's finalizePreAssessment → predictWithAI sequence).

      // The baseline is the frozen pre snapshot when there is one, so a
      // post-assessment always compares against the run the parent was
      // actually shown as "before".
      final baseline = _preSnapshot?.results ?? _preResults;
      final comparison = _assessmentService.compareAssessments(
        preResults: baseline,
        postResults: _postResults,
      );
      if (comparison['has_data'] != true) {
        _lastFinalizationError =
            'There is no pre-assessment to compare these results with.';
      }
      return comparison;
    } catch (e) {
      _lastFinalizationError = 'Could not save the assessment results.';
      debugPrint('[AssessmentProvider] finalizePostAssessment error: $e');
      return {'has_data': false};
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Predict developmental profile using the AI Assessment API.
  ///
  /// Predicts from the *current run's* sessions only — practice play and
  /// abandoned runs are filtered out — and attributes the result to that
  /// run's type: a post-assessment prediction labels the post results and
  /// never rewrites the pre-assessment ones. Returns null if the API is
  /// unreachable, allowing the caller to fall back to rule-based scoring.
  Future<AiAssessmentResponse?> predictWithAI(
    String childId, {
    String? assessmentType,
  }) async {
    final type = assessmentType ?? _currentRunType ?? 'pre';
    final runSessionList = runSessions();
    debugPrint(
      '[AssessmentProvider] 🔮 predictWithAI called for '
      'child=$childId with ${runSessionList.length} $type sessions',
    );
    if (runSessionList.isEmpty) {
      debugPrint(
        '[AssessmentProvider] ⚠️ No sessions for the active run — '
        'skipping prediction',
      );
      _currentSessions.clear();
      return null;
    }
    final onDevice = OnDeviceAiAssessmentService();
    final service = AiAssessmentService();
    try {
      // Prefer on-device ONNX inference (works offline); fall back to the
      // cloud API only if the on-device model isn't available.
      var modelSource = 'xgboost_onnx';
      var prediction = await onDevice.predictFromSessions(
        childId: childId,
        sessions: runSessionList,
      );
      if (prediction != null) {
        debugPrint('[AssessmentProvider] ✅ Used on-device ONNX model');
      } else {
        modelSource = 'xgboost';
        prediction = await service.predictFromSessions(
          childId: childId,
          sessions: runSessionList,
        );
      }

      // Last resort: synthesize the prediction from the rubric labels so a
      // completed assessment ALWAYS yields area levels and a learning path,
      // even when the ONNX assets fail and no cloud server exists.
      if (prediction == null && _rubricResult != null) {
        modelSource = 'rubric_based';
        prediction = _predictionFromRubric(_rubricResult!);
        debugPrint(
          '[AssessmentProvider] ⚠️ AI unavailable — synthesized '
          'prediction from rubric labels',
        );
      }
      _aiPrediction = prediction;
      if (prediction != null) {
        // Persist so the learning path and per-game difficulty survive app
        // restarts (the prediction otherwise only lives in memory).
        await _persistAiPrediction(
          childId,
          prediction,
          modelSource,
          assessmentType: type,
        );
        // New assessment → new path → the sequence restarts at step 1.
        await _resetPathProgress(childId);

        // Mark this run's results as AI-assessed so they can be
        // distinguished from rubric-only results. Only the results of the
        // run the prediction came from are touched.
        if (type == 'post') {
          _postResults =
              _postResults
                  .map((r) => r.copyWithRubric(modelSource: modelSource))
                  .toList();
        } else {
          _preResults =
              _preResults
                  .map((r) => r.copyWithRubric(modelSource: modelSource))
                  .toList();
        }

        debugPrint(
          '[AssessmentProvider] ✅ AI prediction SUCCESS: '
          '${prediction.profileDisplayName} '
          '(${prediction.confidencePercent}), '
          'support_level=${prediction.supportLevel}, '
          'modules=${prediction.recommendedModules}, '
          'moduleDetails=${prediction.moduleDetails}, '
          'skillAreas=${prediction.skillAreas}',
        );
      } else {
        debugPrint(
          '[AssessmentProvider] ⚠️ AI prediction returned null, '
          'will use rule-based fallback',
        );
      }
      notifyListeners();
      return prediction;
    } catch (e) {
      debugPrint('[AssessmentProvider] ❌ predictWithAI error: $e');
      return null;
    } finally {
      onDevice.dispose();
      service.dispose();
      // Clear sessions now that both finalization and AI prediction are done
      _currentSessions.clear();
    }
  }

  /// Builds an [AiAssessmentResponse] from rubric labels (Strength=2,
  /// Emerging=1, Needs Support=0) with locally derived module details —
  /// the offline fallback when neither the ONNX model nor a cloud API is
  /// available.
  AiAssessmentResponse _predictionFromRubric(RubricResult rubric) {
    int perf(PerformanceLabel label) => switch (label) {
      PerformanceLabel.strength => 2,
      PerformanceLabel.emerging => 1,
      PerformanceLabel.needsSupport => 0,
    };
    final attentionInt = switch (rubric.behaviorAttentionLabel) {
      AttentionLabel.sustainedAttention => 2,
      AttentionLabel.variableAttention => 1,
      AttentionLabel.needsAttentionSupport => 0,
    };

    AreaLevel area(int levelInt) => AreaLevel(
      level: const ['needs_support', 'emerging', 'strength'][levelInt],
      levelInt: levelInt,
      levelName: const ['Needs Support', 'Emerging', 'Strength'][levelInt],
      confidence: 0.5, // rubric-derived — moderate confidence
    );

    final areaLevels = <String, AreaLevel>{
      'communication': area(perf(rubric.communicationLabel)),
      'social': area(perf(rubric.socialInteractionLabel)),
      'play': area(perf(rubric.playSkillsLabel)),
      'attention': area(attentionInt),
    };

    final minLevel = areaLevels.values.map((a) => a.levelInt).reduce(math.min);
    final needsSupportCount =
        areaLevels.values.where((a) => a.levelInt == 0).length;
    final moduleDetails = LocalRecommendationRules.deriveModuleDetails(
      areaLevels,
    );

    return AiAssessmentResponse(
      predictedProfile: minLevel >= 2 ? 'balanced_profile' : 'mixed_support',
      confidence: 0.5,
      summary: LocalRecommendationRules.buildSummaryText(areaLevels),
      supportLevel:
          needsSupportCount >= 2
              ? 'high'
              : (needsSupportCount == 1 || minLevel <= 1 ? 'moderate' : 'low'),
      recommendedModules: moduleDetails.map((m) => m.name).toList(),
      moduleDetails: moduleDetails,
      skillAreas: areaLevels.keys.toList(),
      areaLevels: areaLevels,
      onDevice: true,
    );
  }

  /// Export a single XGBoost-ready data row for the current assessment.
  ///
  /// Returns `null` if rubric scoring has not been performed, no sessions
  /// are available, or — the ethics gate — the parent has not opted this
  /// child in to AI-training data use (deny by default).
  Map<String, dynamic>? exportXGBoostRow(String childId) {
    if (!ResearchConsentService.instance.aiTrainingOptInSync(childId)) {
      debugPrint(
        '[AssessmentProvider] XGBoost export blocked: no '
        'AI-training consent for child $childId',
      );
      return null;
    }
    final sessions = runSessions();
    if (_rubricResult == null || sessions.isEmpty) return null;
    const exporter = XGBoostExportService();
    return exporter.generateRow(
      childId: childId,
      sessions: sessions,
      rubricResult: _rubricResult!,
    );
  }

  void clear() {
    _preResults.clear();
    _postResults.clear();
    _recommendation = null;
    _resetRunState();
    _aiPrediction = null;
    _supportProfile = null;
    _preSnapshot = null;
    _postSnapshot = null;
    // Path progress is per child and restored on load; dropping it here stops
    // one child's completed steps showing under another after a switch.
    _pathCompleted = {};
    // Invalidate any load still in flight: its child is no longer loaded,
    // so its late writes are discarded rather than resurrected (AUM-160).
    _loadedChildId = null;
    _loadGeneration++;
    _isLoading = false;
    notifyListeners();
  }
}
