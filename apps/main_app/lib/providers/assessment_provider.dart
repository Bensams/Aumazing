import 'package:flutter/foundation.dart';
import 'package:game_core/game_core.dart';

import '../model/ai_assessment_response.dart';
import '../model/assessment_result.dart';
import '../model/gameplay_session.dart';
import '../features/pre_assessment/sensory/sensory_round_metrics.dart';
import '../services/ai_assessment_service.dart';
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
  final AssessmentService _assessmentService;
  final core_db.LocalDbService _localDb;

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
  })  : _assessmentService = assessmentService ?? AssessmentService(),
        _localDb = localDb ?? core_db.localDbService;

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

  /// Loads all assessment data for a child.
  Future<void> loadAssessments(String childId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _preResults =
          await _localDb.getAssessmentResults(childId: childId, type: 'pre');
      _postResults =
          await _localDb.getAssessmentResults(childId: childId, type: 'post');

      if (_preResults.isNotEmpty) {
        _recommendation = _assessmentService.recommendModule(_preResults);
      }
    } catch (e) {
      debugPrint('[AssessmentProvider] loadAssessments error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
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
    notifyListeners();
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

      // Mark the assessment run as completed
      if (_currentAssessmentRunId != null) {
        await _assessmentService.completeAssessmentRun(
          _currentAssessmentRunId!,
        );
      }

      _currentSessions.clear();

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
    final service = AiAssessmentService();
    try {
      final prediction = await service.predictFromSessions(
        childId: childId,
        sessions: _currentSessions,
      );
      _aiPrediction = prediction;
      if (prediction != null) {
        // Mark all pre-assessment results as AI-assessed so they can be
        // distinguished from rubric-only results.
        _preResults = _preResults
            .map((r) => r.copyWithRubric(modelSource: 'xgboost'))
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
      service.dispose();
      // Clear sessions now that both finalization and AI prediction are done
      _currentSessions.clear();
    }
  }

  /// Export a single XGBoost-ready data row for the current assessment.
  ///
  /// Returns `null` if rubric scoring has not been performed or no sessions
  /// are available.
  Map<String, dynamic>? exportXGBoostRow(String childId) {
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
