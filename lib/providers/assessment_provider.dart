import 'package:flutter/foundation.dart';

import '../model/assessment_result.dart';
import '../model/gameplay_session.dart';
import '../services/assessment_service.dart';
import '../services/local_db_service.dart';

/// Manages assessment state: collecting gameplay metrics, storing results,
/// and providing recommendation data.
class AssessmentProvider extends ChangeNotifier {
  final AssessmentService _assessmentService;
  final LocalDbService _localDb;

  List<AssessmentResult> _preResults = [];
  List<AssessmentResult> _postResults = [];
  Map<String, dynamic>? _recommendation;
  bool _isLoading = false;

  /// The currently active pre-assessment sessions being collected.
  final List<GameplaySession> _currentSessions = [];

  AssessmentProvider({
    AssessmentService? assessmentService,
    LocalDbService? localDb,
  })  : _assessmentService = assessmentService ?? AssessmentService(),
        _localDb = localDb ?? LocalDbService();

  List<AssessmentResult> get preResults => _preResults;
  List<AssessmentResult> get postResults => _postResults;
  Map<String, dynamic>? get recommendation => _recommendation;
  bool get isLoading => _isLoading;
  bool get hasPreAssessment => _preResults.isNotEmpty;
  bool get hasPostAssessment => _postResults.isNotEmpty;
  bool get hasRecommendation => _recommendation != null;

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
          await _localDb.getAssessmentResults(childId, type: 'pre');
      _postResults =
          await _localDb.getAssessmentResults(childId, type: 'post');

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
    );

    _currentSessions.add(session);
    notifyListeners();
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
        );
        _preResults.add(result);
      }

      _recommendation = _assessmentService.recommendModule(_preResults);
      _currentSessions.clear();

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
        );
        _postResults.add(result);
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

  void clear() {
    _preResults.clear();
    _postResults.clear();
    _recommendation = null;
    _currentSessions.clear();
    notifyListeners();
  }
}
