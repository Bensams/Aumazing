import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:game_core/game_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/ai_assessment_response.dart';
import '../model/assessment_result.dart';
import '../model/gameplay_session.dart';
import '../features/pre_assessment/sensory/sensory_round_metrics.dart';
import '../model/area_level.dart';
import '../services/ai_assessment_service.dart';
import '../services/local_recommendation_rules.dart';
import '../services/on_device_ai_assessment_service.dart';
import '../services/research_consent_service.dart';
import '../services/assessment_service.dart';
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
  AssessmentService? _assessmentServiceOverride;
  core_db.LocalDbService? _localDbOverride;

  AssessmentService get _assessmentService =>
      _assessmentServiceOverride ??= AssessmentService();
  core_db.LocalDbService get _localDb =>
      _localDbOverride ??= core_db.localDbService;

  List<AssessmentResult> _preResults = [];
  List<AssessmentResult> _postResults = [];
  Map<String, dynamic>? _recommendation;
  bool _isLoading = false;

  /// The currently active pre-assessment sessions being collected.
  final List<GameplaySession> _currentSessions = [];

  /// The ID of the current assessment run (created at the start of pre/post assessment).
  String? _currentAssessmentRunId;

  /// AI-based prediction result (null if API unavailable or not yet called).
  AiAssessmentResponse? _aiPrediction;

  /// Rubric-based scoring result (null if not yet computed).
  RubricResult? _rubricResult;

  /// Sensory round metrics collected during the pre-assessment sensory experiment.
  List<SensoryRoundMetrics>? _sensoryMetrics;

  AssessmentProvider({
    AssessmentService? assessmentService,
    core_db.LocalDbService? localDb,
  })  : _assessmentServiceOverride = assessmentService,
        _localDbOverride = localDb;

  List<AssessmentResult> get preResults => _preResults;
  List<AssessmentResult> get postResults => _postResults;
  Map<String, dynamic>? get recommendation => _recommendation;
  bool get isLoading => _isLoading;
  bool get hasPreAssessment => _preResults.isNotEmpty;
  bool get hasPostAssessment => _postResults.isNotEmpty;
  bool get hasRecommendation => _recommendation != null;

  /// The latest AI prediction result, or null if unavailable.
  AiAssessmentResponse? get aiPrediction => _aiPrediction;

  /// The latest rubric-based scoring result, or null if not yet computed.
  RubricResult? get rubricResult => _rubricResult;

  /// The sessions collected during the current assessment round.
  List<GameplaySession> get currentSessions =>
      List.unmodifiable(_currentSessions);

  /// The current assessment run ID (available after [startAssessmentRun]).
  String? get currentAssessmentRunId => _currentAssessmentRunId;

  String? get recommendedModuleId =>
      _recommendation?['module_id'] as String?;
  String? get recommendedModuleName =>
      _recommendation?['module_name'] as String?;
  int get recommendedLevel =>
      (_recommendation?['starting_level'] as int?) ?? 1;

  /// Newest result per game — the local DB keeps every run's rows for
  /// history/sync, but the app should only ever score and display the
  /// latest run. A retake replaces results; it never stacks them.
  static List<AssessmentResult> latestPerGame(
      List<AssessmentResult> results) {
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
  Future<void> loadAssessments(String childId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _preResults = latestPerGame(
          await _localDb.getAssessmentResults(childId: childId, type: 'pre'));
      _postResults = latestPerGame(await _localDb.getAssessmentResults(
          childId: childId, type: 'post'));

      if (_preResults.isNotEmpty) {
        _recommendation = _assessmentService.recommendModule(_preResults);
      }

      // Restore the last AI prediction (area levels drive the learning path
      // and per-game difficulty; it only lives in memory otherwise).
      await _restoreAiPrediction(childId);
      await _restorePathProgress(childId);
    } catch (e) {
      debugPrint('[AssessmentProvider] loadAssessments error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  static String _aiPredictionKey(String childId) => 'ai_prediction_$childId';

  Future<void> _persistAiPrediction(
      String childId, AiAssessmentResponse prediction) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _aiPredictionKey(childId), jsonEncode(prediction.toJson()));
    } catch (e) {
      debugPrint('[AssessmentProvider] persistAiPrediction failed: $e');
    }
  }

  Future<void> _restoreAiPrediction(String childId) async {
    if (_aiPrediction != null) return; // in-memory result wins
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_aiPredictionKey(childId));
      if (raw == null) return;
      _aiPrediction = AiAssessmentResponse.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
      debugPrint('[AssessmentProvider] Restored persisted AI prediction '
          'for child=$childId');
    } catch (e) {
      debugPrint('[AssessmentProvider] restoreAiPrediction failed: $e');
    }
  }

  /// Starts a new assessment run and stores the run ID.
  ///
  /// Must be called before [recordGameSession] during pre/post assessment
  /// so that all sessions and results are linked to this run.
  Future<String> startAssessmentRun({
    required String childId,
    required String type,
  }) async {
    _currentAssessmentRunId = await _assessmentService.startAssessmentRun(
      childId: childId,
      type: type,
    );
    debugPrint('[AssessmentProvider] Assessment run started: '
        '$_currentAssessmentRunId (type: $type)');
    notifyListeners();
    return _currentAssessmentRunId!;
  }

  /// Records a single mini-game session during pre/post assessment.
  Future<void> recordGameSession({
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
  }) async {
    final session = await _assessmentService.recordSession(
      childId: childId,
      gameId: gameId,
      context: context,
      score: score,
      totalItems: totalItems,
      errorCount: errorCount,
      totalResponseTimeMs: totalResponseTimeMs,
      startedAt: startedAt,
      assessmentRunId: _currentAssessmentRunId,
      analytics: analytics,
      bgMusicEnabled: bgMusicEnabled,
      hapticFeedbackEnabled: hapticFeedbackEnabled,
    );

    _currentSessions.add(session);

    // Practice completions advance the learning path (sequential unlock).
    if (context == 'practice') {
      await markPathGameCompleted(childId, gameId);
    }
    notifyListeners();
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
          _pathProgressKey(childId), _pathCompleted.toList());
    } catch (e) {
      debugPrint('[AssessmentProvider] persist path progress failed: $e');
    }
  }

  Future<void> _restorePathProgress(String childId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _pathCompleted =
          (prefs.getStringList(_pathProgressKey(childId)) ?? const [])
              .toSet();
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

  /// Finalizes the pre-assessment after all 4 mini-games are played.
  /// Creates assessment results and generates a recommendation.
  Future<void> finalizePreAssessment(String childId) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Group sessions by game and create assessment results
      final gameIds = _currentSessions.map((s) => s.gameId).toSet();
      for (final gameId in gameIds) {
        final gameSessions =
            _currentSessions.where((s) => s.gameId == gameId).toList();
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

        // Score all areas
        final playSkills = rubricScorer.scorePlaySkills(_currentSessions);
        final communication =
            rubricScorer.scoreCommunication(_currentSessions);
        final socialInteraction =
            rubricScorer.scoreSocialInteraction(_currentSessions);
        final behaviorAttention =
            rubricScorer.scoreBehaviorAttention(_currentSessions);

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
        _preResults = _preResults
            .map((result) => result.copyWithRubric(
                  playSkillsLabel: playSkills.displayName,
                  communicationLabel: communication.displayName,
                  socialInteractionLabel: socialInteraction.displayName,
                  behaviorAttentionLabel: behaviorAttention.displayName,
                  sensoryPreferenceLabel: sensoryLabel.displayName,
                  recommendedModule: recommendation.moduleName,
                  overallSummary: summary,
                  modelSource: 'rubric_based',
                  xgboostReady: true,
                ))
            .toList();

        debugPrint('[AssessmentProvider] Rubric scoring complete: '
            'playSkills=${playSkills.displayName}, '
            'communication=${communication.displayName}, '
            'socialInteraction=${socialInteraction.displayName}, '
            'behaviorAttention=${behaviorAttention.displayName}, '
            'sensory=${sensoryLabel.displayName}, '
            'recommended=${recommendation.moduleName}');
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

      debugPrint('[AssessmentProvider] Pre-assessment finalized. '
          'Recommended: ${_recommendation?['module_name']} '
          'Level ${_recommendation?['starting_level']}');
    } catch (e) {
      debugPrint('[AssessmentProvider] finalizePreAssessment error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Finalizes the post-assessment and computes improvement.
  Future<Map<String, dynamic>> finalizePostAssessment(
      String childId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final gameIds = _currentSessions.map((s) => s.gameId).toSet();
      for (final gameId in gameIds) {
        final gameSessions =
            _currentSessions.where((s) => s.gameId == gameId).toList();
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
      if (_currentAssessmentRunId != null) {
        await _assessmentService.completeAssessmentRun(
          _currentAssessmentRunId!,
        );
      }

      // Re-score the rubric from the post sessions so the AI fallback and
      // profile reflect the child's NEW performance, not the pre-assessment.
      try {
        const rubricScorer = RubricScoringService();
        _rubricResult = RubricResult(
          playSkillsLabel: rubricScorer.scorePlaySkills(_currentSessions),
          communicationLabel:
              rubricScorer.scoreCommunication(_currentSessions),
          socialInteractionLabel:
              rubricScorer.scoreSocialInteraction(_currentSessions),
          behaviorAttentionLabel:
              rubricScorer.scoreBehaviorAttention(_currentSessions),
          sensoryPreferenceLabel: _rubricResult?.sensoryPreferenceLabel ??
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

      return _assessmentService.compareAssessments(
        preResults: _preResults,
        postResults: _postResults,
      );
    } catch (e) {
      debugPrint('[AssessmentProvider] finalizePostAssessment error: $e');
      return {'has_data': false};
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Predict developmental profile using the AI Assessment API.
  ///
  /// Sends the collected [_currentSessions] to the XGBoost model and
  /// stores the result in [_aiPrediction]. Returns null if the API is
  /// unreachable, allowing the caller to fall back to rule-based scoring.
  Future<AiAssessmentResponse?> predictWithAI(String childId) async {
    debugPrint('[AssessmentProvider] 🔮 predictWithAI called for '
        'child=$childId with ${_currentSessions.length} sessions');
    final onDevice = OnDeviceAiAssessmentService();
    final service = AiAssessmentService();
    try {
      // Prefer on-device ONNX inference (works offline); fall back to the
      // cloud API only if the on-device model isn't available.
      var modelSource = 'xgboost_onnx';
      var prediction = await onDevice.predictFromSessions(
        childId: childId,
        sessions: _currentSessions,
      );
      if (prediction != null) {
        debugPrint('[AssessmentProvider] ✅ Used on-device ONNX model');
      } else {
        modelSource = 'xgboost';
        prediction = await service.predictFromSessions(
          childId: childId,
          sessions: _currentSessions,
        );
      }

      // Last resort: synthesize the prediction from the rubric labels so a
      // completed assessment ALWAYS yields area levels and a learning path,
      // even when the ONNX assets fail and no cloud server exists.
      if (prediction == null && _rubricResult != null) {
        modelSource = 'rubric_based';
        prediction = _predictionFromRubric(_rubricResult!);
        debugPrint('[AssessmentProvider] ⚠️ AI unavailable — synthesized '
            'prediction from rubric labels');
      }
      _aiPrediction = prediction;
      if (prediction != null) {
        // Persist so the learning path and per-game difficulty survive app
        // restarts (the prediction otherwise only lives in memory).
        await _persistAiPrediction(childId, prediction);
        // New assessment → new path → the sequence restarts at step 1.
        await _resetPathProgress(childId);

        // Mark all pre-assessment results as AI-assessed so they can be
        // distinguished from rubric-only results.
        _preResults = _preResults
            .map((r) => r.copyWithRubric(modelSource: modelSource))
            .toList();

        debugPrint('[AssessmentProvider] ✅ AI prediction SUCCESS: '
            '${prediction.profileDisplayName} '
            '(${prediction.confidencePercent}), '
            'support_level=${prediction.supportLevel}, '
            'modules=${prediction.recommendedModules}, '
            'moduleDetails=${prediction.moduleDetails}, '
            'skillAreas=${prediction.skillAreas}');
      } else {
        debugPrint('[AssessmentProvider] ⚠️ AI prediction returned null, '
            'will use rule-based fallback');
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

    final minLevel =
        areaLevels.values.map((a) => a.levelInt).reduce(math.min);
    final needsSupportCount =
        areaLevels.values.where((a) => a.levelInt == 0).length;
    final moduleDetails =
        LocalRecommendationRules.deriveModuleDetails(areaLevels);

    return AiAssessmentResponse(
      predictedProfile: minLevel >= 2 ? 'balanced_profile' : 'mixed_support',
      confidence: 0.5,
      summary: LocalRecommendationRules.buildSummaryText(areaLevels),
      supportLevel: needsSupportCount >= 2
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
      debugPrint('[AssessmentProvider] XGBoost export blocked: no '
          'AI-training consent for child $childId');
      return null;
    }
    if (_rubricResult == null || _currentSessions.isEmpty) return null;
    const exporter = XGBoostExportService();
    return exporter.generateRow(
      childId: childId,
      sessions: _currentSessions,
      rubricResult: _rubricResult!,
    );
  }

  void clear() {
    _preResults.clear();
    _postResults.clear();
    _recommendation = null;
    _currentSessions.clear();
    _currentAssessmentRunId = null;
    _aiPrediction = null;
    _rubricResult = null;
    _sensoryMetrics = null;
    notifyListeners();
  }
}
