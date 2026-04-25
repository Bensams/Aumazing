import 'package:flutter/foundation.dart';
import 'package:game_core/game_core.dart';
import 'package:uuid/uuid.dart';

import '../../model/assessment_result.dart';
import '../../model/gameplay_session.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_service.dart';

/// Offline-first repository for assessment and gameplay operations.
///
/// Handles:
/// - Pre/post assessment runs
/// - Gameplay sessions and rounds
/// - Assessment results and scoring
/// - Module recommendations
///
/// All writes are local-first with background sync to Supabase.
class AssessmentRepository {
  final LocalDbService _localDb;
  final AuthService _authService;
  final SyncService _syncService;
  final Uuid _uuid = const Uuid();

  AssessmentRepository({
    LocalDbService? localDb,
    AuthService? authService,
    SyncService? overrideSyncService,
  })  : _localDb = localDb ?? localDbService,
        _authService = authService ?? AuthService(),
        _syncService = overrideSyncService ?? syncService;

  String get _effectiveUserId {
    return _authService.currentUser?.id ??
           _authService.currentGuestId ??
           'guest';
  }


  // ─── Assessment Run Operations ──────────────────────────────────────

  /// Start a new assessment run (pre or post).
  ///
  /// Creates a proper record in `assessment_runs_local` so that
  /// child sessions and results can reference it via foreign key.
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

    debugPrint('[AssessmentRepository] Assessment run started: $id (type: $type)');

    // Trigger background sync
    _syncService.syncNow();

    return id;
  }

  // ─── Gameplay Session Operations ──────────────────────────────────────

  /// Record a complete gameplay session
  ///
  /// This is the primary method for capturing game analytics.
  /// Works offline - syncs later when connectivity returns.
  Future<GameplaySession> recordGameSession({
    required String childId,
    required String gameId,
    required String context, // 'pre_assessment', 'post_assessment', 'practice'
    String? assessmentRunId,
    required int score,
    required int totalItems,
    required int errorCount,
    required int totalResponseTimeMs,
    required DateTime startedAt,
    Map<String, dynamic>? settingsSnapshot,
    GameSessionMetrics? analytics,
  }) async {
    final now = DateTime.now();

    final session = GameplaySession(
      id: _uuid.v4(),
      childId: childId,
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
      startedAt: startedAt,
      endedAt: now,
    );

    await _localDb.insertGameSession(
      session,
      ownerId: _effectiveUserId,
      markPending: true,
    );

    // Insert per-round metrics if analytics data is available
    if (analytics != null) {
      for (final round in analytics.rounds) {
        // Propagate session-level sensory state to each round
        round.musicEnabled = session.bgMusicEnabled;
        round.hapticEnabled = session.hapticFeedbackEnabled;
        await _localDb.insertGameRound(
          sessionId: session.id,
          round: round,
          ownerId: _effectiveUserId,
        );
      }
    }

    final accuracy = session.totalItems > 0
        ? ((session.score / session.totalItems) * 100).round()
        : 0;
    debugPrint('[AssessmentRepository] Game session recorded: ${session.id} '
        '($accuracy% accuracy)');

    // Trigger background sync (anonymous users are authenticated in Supabase)
    _syncService.syncNow();

    return session;
  }

  /// Get gameplay sessions for a child
  Future<List<GameplaySession>> getGameSessions({
    required String childId,
    String? context,
  }) async {
    return _localDb.getGameSessions(
      childId: childId,
      context: context,
    );
  }

  /// Get sessions for a specific assessment run
  Future<List<GameplaySession>> getAssessmentRunSessions(String assessmentRunId) async {
    // Query by assessment_run_id field
    final db = await _localDb.database;
    final rows = await db.query(
      'game_sessions_local',
      where: 'assessment_run_id = ? AND deleted_at IS NULL',
      whereArgs: [assessmentRunId],
      orderBy: 'started_at ASC',
    );
    return rows.map((r) => GameplaySession.fromMap(r)).toList();
  }

  // ─── Assessment Result Operations ─────────────────────────────────────

  /// Save a computed assessment result
  Future<AssessmentResult> saveAssessmentResult({
    required String childId,
    required String assessmentRunId,
    required String gameId,
    required String type,
    required int score,
    required int totalItems,
    required int errorCount,
    int randomTouchCount = 0,
    required int avgResponseTimeMs,
    Map<String, dynamic>? rawMetrics,
  }) async {
    final result = AssessmentResult(
      id: _uuid.v4(),
      childId: childId,
      type: type,
      gameId: gameId,
      score: score,
      totalItems: totalItems,
      errorCount: errorCount,
      randomTouchCount: randomTouchCount,
      avgResponseTimeMs: avgResponseTimeMs,
      completedAt: DateTime.now(),
      rawMetrics: rawMetrics ?? {},
    );

    await _localDb.insertAssessmentResult(
      result,
      ownerId: _effectiveUserId,
      markPending: true,
    );

    debugPrint('[AssessmentRepository] Assessment result saved: ${result.id}');

    // Trigger background sync (anonymous users are authenticated in Supabase)
    _syncService.syncNow();

    return result;
  }

  /// Get assessment results for a child
  Future<List<AssessmentResult>> getAssessmentResults({
    required String childId,
    String? type,
  }) async {
    return _localDb.getAssessmentResults(
      childId: childId,
      type: type,
    );
  }

  /// Get pre-assessment results for a child
  Future<List<AssessmentResult>> getPreAssessmentResults(String childId) async {
    return getAssessmentResults(childId: childId, type: 'pre');
  }

  /// Get post-assessment results for a child
  Future<List<AssessmentResult>> getPostAssessmentResults(String childId) async {
    return getAssessmentResults(childId: childId, type: 'post');
  }

  // ─── Scoring & Recommendations ────────────────────────────────────────

  /// Calculate accuracy percentage
  double calculateAccuracy(int score, int totalItems) {
    if (totalItems == 0) return 0.0;
    return (score / totalItems).clamp(0.0, 1.0);
  }

  /// Generate module recommendation based on pre-assessment results
  Map<String, dynamic> generateRecommendation(
    List<AssessmentResult> preResults,
  ) {
    if (preResults.isEmpty) {
      return {
        'module_id': 'module_basic',
        'module_name': 'Basic Skills',
        'starting_level': 1,
        'confidence': 0.5,
        'rationale': 'No assessment data available - starting from basics',
      };
    }

    // Calculate composite scores
    final avgAccuracy = preResults
            .map((r) => r.adjustedAccuracy)
            .reduce((a, b) => a + b) /
        preResults.length;
    final totalErrors = preResults.fold<int>(0, (sum, r) => sum + r.errorCount);
    final avgResponseTime = preResults
            .map((r) => r.avgResponseTimeMs)
            .reduce((a, b) => a + b) /
        preResults.length;

    // Rule-based recommendation
    if (avgAccuracy >= 0.85 && totalErrors <= 4 && avgResponseTime < 3000) {
      return {
        'module_id': 'module_advanced',
        'module_name': 'Advanced Skills',
        'starting_level': 4,
        'confidence': avgAccuracy,
        'rationale': 'High accuracy, low errors, fast response time',
      };
    } else if (avgAccuracy >= 0.7 && totalErrors <= 12) {
      return {
        'module_id': 'module_intermediate',
        'module_name': 'Intermediate Skills',
        'starting_level': 3,
        'confidence': avgAccuracy,
        'rationale': 'Good accuracy with moderate error rate',
      };
    } else if (avgAccuracy >= 0.5) {
      return {
        'module_id': 'module_foundation',
        'module_name': 'Foundation Skills',
        'starting_level': 2,
        'confidence': avgAccuracy,
        'rationale': 'Moderate accuracy - building foundational skills',
      };
    } else {
      return {
        'module_id': 'module_basic',
        'module_name': 'Basic Skills',
        'starting_level': 1,
        'confidence': avgAccuracy,
        'rationale': 'Starting with fundamental skills development',
      };
    }
  }

  /// Compare pre and post assessment results
  Map<String, dynamic> compareAssessments({
    required List<AssessmentResult> preResults,
    required List<AssessmentResult> postResults,
  }) {
    if (preResults.isEmpty || postResults.isEmpty) {
      return {
        'has_data': false,
        'message': 'Insufficient data for comparison',
      };
    }

    final preAvgAccuracy = preResults
            .map((r) => r.adjustedAccuracy)
            .reduce((a, b) => a + b) /
        preResults.length;
    final postAvgAccuracy = postResults
            .map((r) => r.adjustedAccuracy)
            .reduce((a, b) => a + b) /
        postResults.length;

    final preAvgTime = preResults
            .map((r) => r.avgResponseTimeMs)
            .reduce((a, b) => a + b) /
        preResults.length;
    final postAvgTime = postResults
            .map((r) => r.avgResponseTimeMs)
            .reduce((a, b) => a + b) /
        postResults.length;

    final accuracyImprovement = postAvgAccuracy - preAvgAccuracy;
    final responseTimeImprovement = preAvgTime - postAvgTime;

    return {
      'has_data': true,
      'accuracy_improvement': accuracyImprovement,
      'accuracy_improvement_percent': (accuracyImprovement * 100).round(),
      'response_time_improvement_ms': responseTimeImprovement.round(),
      'pre_accuracy': preAvgAccuracy,
      'post_accuracy': postAvgAccuracy,
      'pre_avg_time_ms': preAvgTime.round(),
      'post_avg_time_ms': postAvgTime.round(),
      'improved': accuracyImprovement > 0 || responseTimeImprovement > 0,
    };
  }

  // ─── Sync Operations ──────────────────────────────────────────────────

  /// Force sync of pending assessment records
  Future<void> syncPending() async {
    await _syncService.syncNow();
  }

  /// Get count of pending records across all assessment tables
  Future<Map<String, int>> getPendingCounts() async {
    return _localDb.getPendingCounts();
  }
}

/// Extension for accuracy calculation
extension AssessmentResultX on AssessmentResult {
  double get accuracyPercent => accuracy * 100;
}

/// Global instance for app-wide access
final assessmentRepository = AssessmentRepository();
