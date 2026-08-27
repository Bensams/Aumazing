import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/core/services/local_db_service.dart' as core_db;
import 'package:aumazing/core/services/sync_service.dart' as core_sync;
import 'package:aumazing/model/gameplay_session.dart';
import 'package:aumazing/services/assessment_service.dart';

/// Captures the session [AssessmentService.recordSession] would persist.
class _RecordingDb extends core_db.LocalDbService {
  GameplaySession? inserted;

  @override
  Future<void> insertGameSession(
    GameplaySession session, {
    String? ownerId,
    bool markPending = true,
  }) async {
    inserted = session;
  }
}

class _NoopSyncService extends core_sync.SyncService {
  @override
  Future<void> syncNow() async {}
}

class _FakeSupabaseAuthClient implements SupabaseAuthClient {
  @override
  User? get currentUser => null;

  @override
  Session? get currentSession => null;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late AssessmentService service;
  late _RecordingDb db;

  setUp(() {
    db = _RecordingDb();
    service = AssessmentService(
      localDb: db,
      authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()),
      syncService: _NoopSyncService(),
    );
  });

  Future<GameplaySession> record({
    GameSessionMetrics? analytics,
    String? configurationVersionOverride,
  }) => service.recordSession(
        childId: 'child-1',
        gameId: 'copy_me',
        context: 'pre_assessment',
        score: 10,
        totalItems: 12,
        errorCount: 2,
        totalResponseTimeMs: 1200,
        startedAt: DateTime(2026, 8, 1, 9),
        analytics: analytics,
        configurationVersionOverride: configurationVersionOverride,
      );

  test('session-level off-task count is persisted from the analytics (AUM-305 '
      'regression guard)', () async {
    final metrics = GameSessionMetrics(
      gameId: 'copy_me',
      sessionId: 'session-1',
      childId: 'child-1',
      totalRounds: 3,
    )
      ..offTaskActionCount = 7
      ..randomTouchCount = 2;

    final session = await record(analytics: metrics);

    expect(session.offTaskActionCount, 7);
    expect(db.inserted?.offTaskActionCount, 7);
  });

  test('configurationVersionOverride stamps the persisted session', () async {
    final session = await record(
      configurationVersionOverride: 'sensory-three-round-v1',
    );

    expect(session.configurationVersion, 'sensory-three-round-v1');
    expect(db.inserted?.configurationVersion, 'sensory-three-round-v1');
  });

  test('without an override the policy default for the context is stamped',
      () async {
    final session = await record();

    expect(
      session.configurationVersion,
      GameRoundPolicy.configurationVersionForContext('pre_assessment'),
    );
  });
}
