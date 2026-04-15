import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../model/assessment_result.dart';
import '../model/gameplay_session.dart';
import 'local_db_service.dart';

/// Scoring, recommendation, and assessment logic.
///
/// Currently rule-based; will later call FastAPI + XGBoost endpoint.
class AssessmentService {
  final LocalDbService _localDb;
  static const _uuid = Uuid();

  AssessmentService({LocalDbService? localDb})
      : _localDb = localDb ?? LocalDbService();

  // ── Mini-game IDs ─────────────────────────────────────────────────────

  static const gameMatchIt = 'match_it';
  static const gameCopyMe = 'copy_me';
  static const gameDoWhatISay = 'do_what_i_say';
  static const gameMyTurnYourTurn = 'my_turn_your_turn';

  static const preAssessmentGames = [
    gameMatchIt,
    gameCopyMe,
    gameDoWhatISay,
    gameMyTurnYourTurn,
  ];

  // ── Record a gameplay session ─────────────────────────────────────────

  Future<GameplaySession> recordSession({
    required String childId,
    required String gameId,
    required String context,
    required int score,
    required int totalItems,
    required int errorCount,
    required int totalResponseTimeMs,
    required DateTime startedAt,
  }) async {
    final session = GameplaySession(
      id: _uuid.v4(),
      childId: childId,
      gameId: gameId,
      context: context,
      score: score,
      totalItems: totalItems,
      errorCount: errorCount,
      totalResponseTimeMs: totalResponseTimeMs,
      startedAt: startedAt,
      endedAt: DateTime.now(),
    );

    await _localDb.insertSession(session);
    debugPrint('[Assessment] Session recorded: ${session.gameId} '
        '→ score ${session.score}/${session.totalItems}');
    return session;
  }

  // ── Create an assessment result from gameplay sessions ────────────────

  Future<AssessmentResult> createAssessmentResult({
    required String childId,
    required String type,
    required String gameId,
    required List<GameplaySession> sessions,
  }) async {
    if (sessions.isEmpty) {
      throw ArgumentError('No sessions to create assessment from');
    }

    final totalScore = sessions.fold<int>(0, (sum, s) => sum + s.score);
    final totalItems = sessions.fold<int>(0, (sum, s) => sum + s.totalItems);
    final totalErrors = sessions.fold<int>(0, (sum, s) => sum + s.errorCount);
    final totalTime =
        sessions.fold<int>(0, (sum, s) => sum + s.totalResponseTimeMs);
    final avgTime = totalItems > 0 ? (totalTime / totalItems).round() : 0;

    final result = AssessmentResult(
      id: _uuid.v4(),
      childId: childId,
      type: type,
      gameId: gameId,
      score: totalScore,
      totalItems: totalItems,
      errorCount: totalErrors,
      avgResponseTimeMs: avgTime,
      completedAt: DateTime.now(),
      rawMetrics: {
        'session_count': sessions.length,
        'total_duration_ms':
            sessions.fold<int>(0, (s, g) => s + g.duration.inMilliseconds),
      },
    );

    await _localDb.insertAssessmentResult(result);
    return result;
  }

  // ── Recommendation Engine (rule-based) ────────────────────────────────

  /// Determines the recommended starting module and level based on
  /// pre-assessment results across all 4 mini-games.
  ///
  /// Returns a map with:
  /// - 'module_id': String
  /// - 'module_name': String
  /// - 'starting_level': int (1-5)
  /// - 'confidence': double (0.0-1.0)
  Map<String, dynamic> recommendModule(List<AssessmentResult> preResults) {
    if (preResults.isEmpty) {
      return {
        'module_id': 'module_basic',
        'module_name': 'Basic Skills',
        'starting_level': 1,
        'confidence': 0.5,
      };
    }

    // Calculate composite score across all pre-assessment games.
    final avgAccuracy =
        preResults.map((r) => r.accuracy).reduce((a, b) => a + b) /
            preResults.length;
    final avgErrors =
        preResults.map((r) => r.errorCount).reduce((a, b) => a + b) /
            preResults.length;
    final avgResponseTime =
        preResults.map((r) => r.avgResponseTimeMs).reduce((a, b) => a + b) /
            preResults.length;

    // Simple rule-based classification:
    // High accuracy + low errors + fast response → higher level
    int startingLevel;
    String moduleId;
    String moduleName;

    if (avgAccuracy >= 0.85 && avgErrors <= 1 && avgResponseTime < 3000) {
      startingLevel = 4;
      moduleId = 'module_advanced';
      moduleName = 'Advanced Skills';
    } else if (avgAccuracy >= 0.7 && avgErrors <= 3) {
      startingLevel = 3;
      moduleId = 'module_intermediate';
      moduleName = 'Intermediate Skills';
    } else if (avgAccuracy >= 0.5) {
      startingLevel = 2;
      moduleId = 'module_foundation';
      moduleName = 'Foundation Skills';
    } else {
      startingLevel = 1;
      moduleId = 'module_basic';
      moduleName = 'Basic Skills';
    }

    return {
      'module_id': moduleId,
      'module_name': moduleName,
      'starting_level': startingLevel,
      'confidence': avgAccuracy,
    };
  }

  // ── Pre vs Post Comparison ────────────────────────────────────────────

  /// Compares pre- and post-assessment results for a child.
  /// Returns improvement metrics.
  Map<String, dynamic> compareAssessments({
    required List<AssessmentResult> preResults,
    required List<AssessmentResult> postResults,
  }) {
    if (preResults.isEmpty || postResults.isEmpty) {
      return {'has_data': false};
    }

    final preAvgAccuracy =
        preResults.map((r) => r.accuracy).reduce((a, b) => a + b) /
            preResults.length;
    final postAvgAccuracy =
        postResults.map((r) => r.accuracy).reduce((a, b) => a + b) /
            postResults.length;

    final preAvgTime =
        preResults.map((r) => r.avgResponseTimeMs).reduce((a, b) => a + b) /
            preResults.length;
    final postAvgTime =
        postResults.map((r) => r.avgResponseTimeMs).reduce((a, b) => a + b) /
            postResults.length;

    return {
      'has_data': true,
      'accuracy_improvement': postAvgAccuracy - preAvgAccuracy,
      'response_time_improvement': preAvgTime - postAvgTime,
      'pre_accuracy': preAvgAccuracy,
      'post_accuracy': postAvgAccuracy,
      'pre_avg_time_ms': preAvgTime.round(),
      'post_avg_time_ms': postAvgTime.round(),
    };
  }
}
