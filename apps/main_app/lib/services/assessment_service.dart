import 'package:flutter/foundation.dart';
import 'package:game_core/game_core.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:uuid/uuid.dart';

import '../model/assessment_result.dart';
import '../model/gameplay_session.dart';
import '../core/services/local_db_service.dart' as core_db;
import '../core/services/auth_service.dart';
import '../core/services/sync_service.dart' as core_sync;

/// A run a child left open, with the play it already contains (AUM-154).
///
/// Carries the sessions read back from the database rather than a run id
/// alone: a resume after the app was closed has nothing in memory, so the
/// only place the earlier games still exist is storage.
class OpenAssessmentRun {
  const OpenAssessmentRun({
    required this.id,
    required this.childId,
    required this.type,
    required this.startedAt,
    required this.sessions,
  });

  final String id;
  final String childId;

  /// 'pre' or 'post' — a run is only resumable into the same kind of
  /// assessment it was started as.
  final String type;
  final DateTime startedAt;

  /// Every session stored against this run, unfiltered. The provider decides
  /// which of them really belong to it.
  final List<GameplaySession> sessions;
}

/// The assessment operations [AssessmentProvider] depends on.
///
/// Declared as an interface so the provider's run lifecycle can be exercised
/// against an in-memory double — the real [AssessmentService] talks to SQLite,
/// Supabase auth and the sync service, none of which exist in a unit test.
abstract interface class AssessmentGateway {
  Future<String> startAssessmentRun({
    required String childId,
    required String type,
  });

  Future<void> completeAssessmentRun(String runId);

  /// Marks every still-open run for [childId] as incomplete, returning how
  /// many were closed (AUM-154).
  Future<int> abandonOpenRuns(String childId);

  /// The run [childId] still has open, with its stored sessions, or null
  /// when there is none (AUM-154).
  ///
  /// Read *before* a new run is started: [startAssessmentRun] closes open
  /// runs and the caller would be asking about a run it had just ended.
  Future<OpenAssessmentRun?> openAssessmentRun(String childId);

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
    bool bgMusicEnabled,
    bool hapticFeedbackEnabled,
    bool applySessionSensoryDefaults,
  });

  Future<AssessmentResult> createAssessmentResult({
    required String childId,
    required String type,
    required String gameId,
    required List<GameplaySession> sessions,
    String? assessmentRunId,
  });

  Map<String, dynamic> recommendModule(List<AssessmentResult> preResults);

  Map<String, dynamic> compareAssessments({
    required List<AssessmentResult> preResults,
    required List<AssessmentResult> postResults,
  });
}

/// Scoring, recommendation, and assessment logic.
///
/// Uses the offline-first [core_db.LocalDbService] which writes records
/// with `sync_status = 'pending'` so the [core_sync.SyncService] can
/// push them to Supabase in the background.
class AssessmentService implements AssessmentGateway {
  final core_db.LocalDbService _localDb;
  final AuthService _authService;
  final core_sync.SyncService _syncService;
  static const _uuid = Uuid();

  AssessmentService({
    core_db.LocalDbService? localDb,
    AuthService? authService,
    core_sync.SyncService? syncService,
  }) : _localDb = localDb ?? core_db.localDbService,
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
  @override
  Future<String> startAssessmentRun({
    required String childId,
    required String type, // 'pre' or 'post'
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    final db = await _localDb.database;

    await db.insert('assessment_runs_local', {
      'id': id,
      'child_id': childId,
      'type': type,
      'started_at': now.toIso8601String(),
      'status': 'in_progress',
      'sync_status': 'pending',
      'updated_at': now.toIso8601String(),
      'local_created_at': now.toIso8601String(),
      'owner_id': _effectiveUserId,
    });

    debugPrint('[Assessment] Assessment run started: $id (type: $type)');

    // Trigger background sync
    _syncService.syncNow();

    return id;
  }

  /// Marks an assessment run as completed.
  @override
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

  /// Closes any run this child left open, marking it `incomplete`.
  ///
  /// A run that was walked away from used to sit at `in_progress` forever,
  /// so the stored history could not distinguish "still going" from
  /// "abandoned three weeks ago" — and every later query had to guess
  /// (AUM-154). Closing them when the next run starts keeps at most one
  /// genuinely open run per child, which is the invariant the resume path
  /// depends on.
  ///
  /// The sessions of an abandoned run are deliberately left in place: they
  /// are real play, and the run is kept as evidence of what happened rather
  /// than erased.
  @override
  Future<int> abandonOpenRuns(String childId) async {
    final db = await _localDb.database;
    final now = DateTime.now();

    final closed = await db.update(
      'assessment_runs_local',
      {
        'status': 'incomplete',
        'sync_status': 'pending',
        'updated_at': now.toIso8601String(),
      },
      where: 'child_id = ? AND status = ?',
      whereArgs: [childId, 'in_progress'],
    );

    if (closed > 0) {
      debugPrint(
        '[Assessment] Marked $closed abandoned run(s) incomplete for $childId',
      );
      _syncService.syncNow();
    }
    return closed;
  }

  /// The child's still-open run and the play already recorded against it.
  ///
  /// [abandonOpenRuns] keeps at most one run open per child, so the newest
  /// in-progress row is the only candidate; it is read with its sessions
  /// because a child resuming after the app was closed has nothing left in
  /// memory to resume from.
  @override
  Future<OpenAssessmentRun?> openAssessmentRun(String childId) async {
    final db = await _localDb.database;
    final rows = await db.query(
      'assessment_runs_local',
      where: 'child_id = ? AND status = ?',
      whereArgs: [childId, 'in_progress'],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final row = rows.first;
    final runId = row['id'] as String;
    final startedAt = DateTime.tryParse((row['started_at'] as String?) ?? '');
    // A run with no readable start date cannot be aged, and the staleness
    // rule is what stops an ancient run being offered — treat it as
    // unresumable rather than guessing at its age.
    if (startedAt == null) return null;

    final sessions =
        (await _localDb.getGameSessions(
          childId: childId,
        )).where((s) => s.assessmentRunId == runId).toList();

    return OpenAssessmentRun(
      id: runId,
      childId: childId,
      type: (row['type'] as String?) ?? 'pre',
      startedAt: startedAt,
      sessions: sessions,
    );
  }

  // ── Record a gameplay session ─────────────────────────────────────────

  @override
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
    // The sensory experiment toggles music and haptics *per round*, and
    // stamps each round with the configuration that was active for it.
    // Overwriting those with the session-level flags would erase exactly the
    // signal the experiment exists to measure, so that flow passes false.
    bool applySessionSensoryDefaults = true,
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
      improvementScore: analytics?.improvementScore ?? 0.0,
      consistencyScore: analytics?.consistencyScore ?? 0.0,
      configurationVersion: GameRoundPolicy.configurationVersionForContext(context),
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
        if (applySessionSensoryDefaults) {
          round.musicEnabled = session.bgMusicEnabled;
          round.hapticEnabled = session.hapticFeedbackEnabled;
        }
        await _localDb.insertGameRound(
          sessionId: session.id,
          round: round,
          ownerId: _effectiveUserId,
        );
      }
    }

    debugPrint(
      '[Assessment] Session recorded: ${session.gameId} '
      '→ score ${session.score}/${session.totalItems} '
      '(sync_status=pending)',
    );

    // Trigger background sync (anonymous users are authenticated in Supabase)
    _syncService.syncNow();

    return session;
  }

  // ── Create an assessment result from gameplay sessions ────────────────

  @override
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
    final totalRandomTouches = sessions.fold<int>(
      0,
      (sum, s) => sum + s.randomTouchCount,
    );
    final totalTime = sessions.fold<int>(
      0,
      (sum, s) => sum + s.totalResponseTimeMs,
    );
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
        'total_duration_ms': sessions.fold<int>(
          0,
          (s, g) => s + g.duration.inMilliseconds,
        ),
      },
    );

    // Write to the offline-first local DB with sync_status = 'pending'
    await _localDb.insertAssessmentResult(
      result,
      ownerId: _effectiveUserId,
      markPending: true,
    );

    debugPrint(
      '[Assessment] Assessment result created: ${result.gameId} '
      '(sync_status=pending)',
    );

    // Trigger background sync (anonymous users are authenticated in Supabase)
    _syncService.syncNow();

    return result;
  }

  // ── Canonical scoring ─────────────────────────────────────────────────

  /// Projects assessment results onto the shared [ResultGameScore] shape so
  /// every surface scores a run through the one policy in
  /// [AssessmentScoring] — see its doc comment for why per-game accuracy is
  /// the *adjusted* accuracy and why the overall figure is item-weighted.
  static List<ResultGameScore> gameScores(List<AssessmentResult> results) => [
    for (final result in results)
      ResultGameScore(
        gameId: result.gameId,
        name: result.gameId,
        emoji: '',
        accuracy: result.adjustedAccuracy,
        correctCount: result.score,
        errorCount: result.errorCount,
        totalItems: result.totalItems,
      ),
  ];

  /// Item-weighted overall adjusted accuracy for a set of results.
  ///
  /// Games are *not* weighted equally: a 20-item game counts twice as much
  /// as a 10-item one, exactly as the result screens display it.
  static double overallAccuracy(List<AssessmentResult> results) =>
      AssessmentScoring.overallAdjustedAccuracy(gameScores(results));

  /// Item-weighted mean response time in ms, matching [overallAccuracy]'s
  /// weighting so accuracy and speed describe the same population of items.
  ///
  /// Returns 0 when no result reports any items.
  static double weightedAvgResponseTimeMs(List<AssessmentResult> results) {
    var weighted = 0.0;
    var items = 0;
    for (final result in results) {
      if (result.totalItems <= 0) continue;
      weighted += result.avgResponseTimeMs * result.totalItems;
      items += result.totalItems;
    }
    if (items <= 0) return 0.0;
    return weighted / items;
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
  @override
  Map<String, dynamic> recommendModule(List<AssessmentResult> preResults) {
    if (preResults.isEmpty) {
      return {
        'module_id': 'module_basic',
        'module_name': 'Basic Skills',
        'starting_level': 1,
        'confidence': 0.5,
      };
    }

    // Composite score across all pre-assessment games, item-weighted so a
    // long game is not worth the same as a short one.
    final avgAccuracy = overallAccuracy(preResults);
    final avgErrors =
        preResults.map((r) => r.errorCount).reduce((a, b) => a + b) /
        preResults.length;
    final avgResponseTime = weightedAvgResponseTimeMs(preResults);

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
  ///
  /// Both sides are scored with the canonical item-weighted adjusted-accuracy
  /// policy ([AssessmentScoring.overallAdjustedAccuracy]) so the improvement
  /// figure is expressed in the same units the parent sees on either result
  /// screen. Response time is weighted the same way.
  @override
  Map<String, dynamic> compareAssessments({
    required List<AssessmentResult> preResults,
    required List<AssessmentResult> postResults,
  }) {
    if (preResults.isEmpty || postResults.isEmpty) {
      return {'has_data': false};
    }

    final preAvgAccuracy = overallAccuracy(preResults);
    final postAvgAccuracy = overallAccuracy(postResults);

    final preAvgTime = weightedAvgResponseTimeMs(preResults);
    final postAvgTime = weightedAvgResponseTimeMs(postResults);

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
