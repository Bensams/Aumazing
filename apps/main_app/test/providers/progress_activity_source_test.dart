import 'package:flutter_test/flutter_test.dart';

import 'package:aumazing/core/services/local_db_service.dart';
import 'package:aumazing/model/gameplay_session.dart';
import 'package:aumazing/model/module_progress.dart';
import 'package:aumazing/providers/progress_provider.dart';

/// The dashboard's "Recent activity" must read the database that sessions
/// are actually written into.
///
/// The app carries two `LocalDbService` classes backed by two different
/// SQLite files: the core one (`aumazing_offline.db`), which every
/// `insertGameSession` write goes to, and an older one under `services/`
/// (`aumazing.db`). ProgressProvider used to read from the second, so the
/// dashboard queried a database no session was ever written into and
/// "Recent activity" stayed empty however much the child played.
///
/// These pin the provider to the writing side. Consolidating the two
/// services is AUM-31; until then this is the guard.
void main() {
  GameplaySession session(String childId, {required String id}) =>
      GameplaySession(
        id: id,
        childId: childId,
        gameId: 'copy_me',
        context: 'practice',
        startedAt: DateTime(2026, 6, 1, 10),
        endedAt: DateTime(2026, 6, 1, 10, 5),
        score: 8,
        totalItems: 10,
        errorCount: 2,
        totalResponseTimeMs: 12000,
      );

  test(
    'recent activity comes from the database sessions are written to',
    () async {
      final db = _RecordingDb({
        'child-a': [session('child-a', id: 'played-1')],
      });
      final provider = ProgressProvider(localDb: db);

      await provider.loadProgress('child-a');

      // The provider asked the *writing* database for this child's sessions.
      expect(db.sessionQueries, ['child-a']);
      expect(provider.recentSessions, hasLength(1));
      expect(provider.recentSessions.single.id, 'played-1');
      expect(provider.totalSessions, 1);
    },
  );

  test('a child who has played nothing still reports an empty list', () async {
    final db = _RecordingDb({'child-a': []});
    final provider = ProgressProvider(localDb: db);

    await provider.loadProgress('child-a');

    expect(db.sessionQueries, ['child-a']);
    expect(provider.recentSessions, isEmpty);
    expect(provider.lastSession, isNull);
  });

  test('the newest session is the one surfaced as last', () async {
    final db = _RecordingDb({
      // The database returns newest-first (started_at DESC).
      'child-a': [
        session('child-a', id: 'newest'),
        session('child-a', id: 'older'),
      ],
    });
    final provider = ProgressProvider(localDb: db);

    await provider.loadProgress('child-a');

    expect(provider.lastSession?.id, 'newest');
  });

  test('sessions are re-read for the newly selected child', () async {
    final db = _RecordingDb({
      'child-a': [session('child-a', id: 'a-1')],
      'child-b': [session('child-b', id: 'b-1')],
    });
    final provider = ProgressProvider(localDb: db);

    await provider.loadProgress('child-a');
    await provider.loadProgress('child-b');

    expect(db.sessionQueries, ['child-a', 'child-b']);
    expect(provider.recentSessions.single.id, 'b-1');
  });
  test('resolves a session only within the loaded child scope', () async {
    final matching = session('child-a', id: 'session-a');
    final db = _RecordingDb({
      'child-a': [matching],
      'child-b': [session('child-b', id: 'session-b')],
    });
    final provider = ProgressProvider(localDb: db);

    await provider.loadProgress('child-a');

    expect(
      provider.sessionFor(childId: 'child-a', sessionId: 'session-a'),
      same(matching),
    );
    expect(
      provider.sessionFor(childId: 'child-b', sessionId: 'session-a'),
      isNull,
    );
    expect(
      provider.sessionFor(childId: 'child-a', sessionId: 'missing'),
      isNull,
    );
  });

  // ── Live hand-off from play (no reload, no network) ──────────────────
  //
  // A finished game is handed to the provider as it is recorded, so the
  // dashboard underneath child mode is already current when the parent
  // returns. Nothing here queries anything: the row is in the local
  // database before this point, and the push to Supabase is fire-and-forget.

  test('a session recorded during play shows without another query', () async {
    final db = _RecordingDb({'child-a': []});
    final provider = ProgressProvider(localDb: db);
    await provider.loadProgress('child-a');

    provider.addSession(session('child-a', id: 'just-played'));

    expect(provider.recentSessions.single.id, 'just-played');
    // Still the one load — the dashboard did not have to go back to storage,
    // let alone to the network, to show the play.
    expect(db.sessionQueries, ['child-a']);
  });

  test('a re-read after play does not list the same session twice', () async {
    final played = session('child-a', id: 'played-1');
    final db = _RecordingDb({
      'child-a': [played],
    });
    final provider = ProgressProvider(localDb: db);

    // The dashboard re-queries on the way back from child mode and the
    // recorder hands the same session over — in either order, one entry.
    await provider.loadProgress('child-a');
    provider.addSession(played);

    expect(provider.recentSessions, hasLength(1));
  });

  test('a duplicate completion callback adds nothing', () async {
    final db = _RecordingDb({'child-a': []});
    final provider = ProgressProvider(localDb: db);
    await provider.loadProgress('child-a');

    final played = session('child-a', id: 'played-1');
    provider.addSession(played);
    provider.addSession(played);

    expect(provider.recentSessions, hasLength(1));
  });
  test('session lookup requires the loaded child and exact session id', () async {
    final matching = session('child-a', id: 'session-a');
    final provider = ProgressProvider(
      localDb: _RecordingDb({'child-a': [matching]}),
    );

    await provider.loadProgress('child-a');

    expect(
      provider.sessionFor(childId: 'child-a', sessionId: 'session-a'),
      same(matching),
    );
    expect(
      provider.sessionFor(childId: 'child-b', sessionId: 'session-a'),
      isNull,
    );
    expect(
      provider.sessionFor(childId: 'child-a', sessionId: 'deleted'),
      isNull,
    );
  });
}

/// Core-service stand-in that records which child's sessions were asked for.
///
/// Extending [LocalDbService] (the core one) is the point: if the provider
/// is ever pointed back at the legacy service, this file stops compiling.
class _RecordingDb extends LocalDbService {
  _RecordingDb(this._sessionsByChild);

  final Map<String, List<GameplaySession>> _sessionsByChild;
  final List<String> sessionQueries = [];

  @override
  Future<List<GameplaySession>> getGameSessions({
    String? childId,
    String? context,
    bool includeDeleted = false,
  }) async {
    sessionQueries.add(childId ?? '<all>');
    return _sessionsByChild[childId] ?? const [];
  }

  @override
  Future<List<ModuleProgress>> getModuleProgress(String childId) async => [];
}
