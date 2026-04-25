import 'package:flutter/foundation.dart';
import 'package:game_core/game_core.dart';
import 'package:uuid/uuid.dart';

import '../model/assessment_result.dart';
import '../model/gameplay_session.dart';
import '../core/services/local_db_service.dart' as core_db;
import '../core/services/auth_service.dart';
import '../core/services/sync_service.dart' as core_sync;

/// Scoring, recommendation, and assessment logic.
///
/// Uses the offline-first [core_db.LocalDbService] which writes records
/// with `sync_status = 'pending'` so the [core_sync.SyncService] can
/// push them to Supabase in the background.
class AssessmentService {
  final core_db.LocalDbService _localDb;
  final AuthService _authService;
  final core_sync.SyncService _syncService;
  static const _uuid = Uuid();

  AssessmentService({
    core_db.LocalDbService? localDb,
    AuthService? authService,
    core_sync.SyncService? syncService,
  })  : _localDb = localDb ?? core_db.localDbService,
        _authService = authService ?? AuthService(),
        _syncService = syncService ?? core_sync.syncService;

  String get _effectiveUserId {
    return _authService.currentUser?.id ??
        _authService.currentGuestId ??
        'guest';
  }


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

  // ── Start an assessment run ───────────────────────────────────────────

  /// Creates a new assessment run record in the local DB.
  ///
  /// Returns the generated run ID which should be passed to all subsequent
  /// [recordSession] and [createAssessmentResult] calls for this assessment.
  Future<String> startAssessmentRun({
    required String childId,
    required String type, // 'pre' or 'post'
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    final db = await _localDb.database;

    await db.insert(
      'assessment_runs_local',
      {
        'id': id,
        'child_id': childId,
        'type': type,
        'started_at': now.toIso8601String(),
        'status': 'in_progress',
        'sync_status': 'pending',
        'updated_at': now.toIso8601String(),
        'local_created_at': now.toIso8601String(),
        'owner_id': _effectiveUserId,
      },
    );

    debugPrint('[Assessment] Assessment run started: $id (type: $type)');

    // Trigger background sync
    _syncService.syncNow();

    return id;
  }

  /// Marks an assessment run as completed.
  Future<void> completeAssessmentRun(String runId) async {
    final db = await _localDb.database;
    final now = DateTime.now();

    await db.update(
      'assessment_runs_local',
      {
        'completed_at': now.toIso8601String(),
        'status': 'completed',
        'sync_status': 'pending',
        'updated_at': now.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [runId],
    );

    debugPrint('[Assessment] Assessment run completed: $runId');

    // Trigger background sync
    _syncService.syncNow();
  }

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
    String? assessmentRunId,
    GameSessionMetrics? analytics,
    bool bgMusicEnabled = true,
    bool hapticFeedbackEnabled = true,
  }) async {
    final session = GameplaySession(
      id: _uuid.v4(),
      childId: childId,
      assessmentRunId: assessmentRunId,
      gameId: gameId,
      context: context,
      score: score,
      totalItems: totalItems,
      errorCount: errorCount,
      totalResponseTimeMs: totalResponseTimeMs,
      retryCount: analytics?.retryCount ?? 0,
      hintCount: analytics?.hintCount ?? 0,
      promptCount: analytics?.promptCount ?? 0,
      idleTimeSeconds: analytics?.idleTimeSeconds.toDouble() ?? 0.0,
      randomTouchCount: analytics?.randomTouchCount ?? 0,
      avgResponseTime: analytics?.avgResponseTime ?? 0.0,
      avgValidResponseTime: analytics?.avgValidResponseTime ?? 0.0,
      offTaskActionCount: analytics?.offTaskActionCount ?? 0,
      improvementScore: analytics?.improvementScore ?? 0.0,
      consistencyScore: analytics?.consistencyScore ?? 0.0,
      bgMusicEnabled: bgMusicEnabled,
      hapticFeedbackEnabled: hapticFeedbackEnabled,
      startedAt: startedAt,
      endedAt: DateTime.now(),
    );

    // Write to the offline-first local DB with sync_status = 'pending'
    await _localDb.insertGameSession(
      session,
      ownerId: _effectiveUserId,
      markPending: true,
    );

    // Insert per-round metrics if analytics data is available
    if (analytics != null) {
      for (final round in analytics.rounds) {
        round.musicEnabled = session.bgMusicEnabled;
        round.hapticEnabled = session.hapticFeedbackEnabled;
        await _localDb.insertGameRound(
          sessionId: session.id,
          round: round,
          ownerId: _effectiveUserId,
        );
      }
    }

    debugPrint('[Assessment] Session recorded: ${session.gameId} '
        '→ score ${session.score}/${session.totalItems} '
        '(sync_status=pending)');

    // Trigger background sync (anonymous users are authenticated in Supabase)
    _syncService.syncNow();

    return session;
  }

  // ── Create an assessment result from gameplay sessions ────────────────

  Future<AssessmentResult> createAssessmentResult({
    required String childId,
    required String type,
    required String gameId,
    required List<GameplaySession> sessions,
    String? assessmentRunId,
  }) async {
    if (sessions.isEmpty) {
      throw ArgumentError('No sessions to create assessment from');
    }

    final totalScore = sessions.fold<int>(0, (sum, s) => sum + s.score);
    final totalItems = sessions.fold<int>(0, (sum, s) => sum + s.totalItems);
    final totalErrors = sessions.fold<int>(0, (sum, s) => sum + s.errorCount);
    final totalRandomTouches =
        sessions.fold<int>(0, (sum, s) => sum + s.randomTouchCount);
    final totalTime =
        sessions.fold<int>(0, (sum, s) => sum + s.totalResponseTimeMs);
    final avgTime = totalItems > 0 ? (totalTime / totalItems).round() : 0;

    final result = AssessmentResult(
      id: _uuid.v4(),
      childId: childId,
      assessmentRunId: assessmentRunId,
      type: type,
      gameId: gameId,
      score: totalScore,
      totalItems: totalItems,
      errorCount: totalErrors,
      randomTouchCount: totalRandomTouches,
      avgResponseTimeMs: avgTime,
      completedAt: DateTime.now(),
      rawMetrics: {
        'session_count': sessions.length,
        'total_duration_ms':
            sessions.fold<int>(0, (s, g) => s + g.duration.inMilliseconds),
      },
    );

    // Write to the offline-first local DB with sync_status = 'pending'
    await _localDb.insertAssessmentResult(
      result,
      ownerId: _effectiveUserId,
      markPending: true,
    );

    debugPrint('[Assessment] Assessment result created: ${result.gameId} '
        '(sync_status=pending)');

    // Trigger background sync (anonymous users are authenticated in Supabase)
    _syncService.syncNow();

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
        preResults.map((r) => r.adjustedAccuracy).reduce((a, b) => a + b) /
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
        preResults.map((r) => r.adjustedAccuracy).reduce((a, b) => a + b) /
            preResults.length;
    final postAvgAccuracy =
        postResults.map((r) => r.adjustedAccuracy).reduce((a, b) => a + b) /
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
