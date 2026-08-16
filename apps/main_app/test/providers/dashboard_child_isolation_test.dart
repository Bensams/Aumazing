import 'dart:async';

import 'package:aumazing/core/services/local_db_service.dart' as core_db;
import 'package:aumazing/model/assessment_result.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/model/gameplay_session.dart';
import 'package:aumazing/model/module_progress.dart';
import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/providers/progress_provider.dart';
import 'package:aumazing/services/assessment_service.dart';
import 'package:aumazing/services/child_switch_service.dart';
import 'package:aumazing/services/entitlement_service.dart';
import 'package:aumazing/services/local_db_service.dart' as legacy_db;
import 'package:aumazing/services/screen_time_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_auth.dart';

/// AUM-160 — the dashboard shows only the active child's data, and a slow
/// asynchronous result for a previously selected child can never overwrite
/// the newly selected child's dashboard.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AssessmentProvider stale-load rejection', () {
    test(
      'a slow load for the previous child cannot overwrite the new child',
      () async {
        final db = _GatedAssessmentDb();
        final provider = AssessmentProvider(
          localDb: db,
          assessmentService: _FakeAssessmentGateway(),
        );

        // Child A's load hangs on the database…
        final loadA = provider.loadAssessments('a');

        // …while the parent switches to child B, whose load completes first.
        provider.clear();
        final loadB = provider.loadAssessments('b');
        db.release('b');
        await loadB;
        expect(provider.loadedChildId, 'b');
        expect(provider.preResults.single.childId, 'b');
        expect(provider.recommendation!['child_id'], 'b');

        // Child A's rows finally arrive — and must be thrown away.
        db.release('a');
        await loadA;
        expect(provider.loadedChildId, 'b');
        expect(provider.preResults.single.childId, 'b');
        expect(provider.recommendation!['child_id'], 'b');
        expect(provider.isLoading, isFalse);
      },
    );

    test(
      'a re-load for another child drops the old rows before querying',
      () async {
        final db = _GatedAssessmentDb();
        final provider = AssessmentProvider(
          localDb: db,
          assessmentService: _FakeAssessmentGateway(),
        );

        db.release('a');
        await provider.loadAssessments('a');
        expect(provider.preResults.single.childId, 'a');

        // Without an intervening clear(): the old child's rows must be gone
        // the moment the new load starts, not when it finishes.
        final loadB = provider.loadAssessments('b');
        expect(provider.preResults, isEmpty);
        expect(provider.recommendation, isNull);
        expect(provider.isLoading, isTrue);

        db.release('b');
        await loadB;
        expect(provider.preResults.single.childId, 'b');
      },
    );

    test('clear() invalidates a load still in flight', () async {
      final db = _GatedAssessmentDb();
      final provider = AssessmentProvider(
        localDb: db,
        assessmentService: _FakeAssessmentGateway(),
      );

      final loadA = provider.loadAssessments('a');
      provider.clear();
      expect(provider.isLoading, isFalse);

      db.release('a');
      await loadA;
      expect(provider.loadedChildId, isNull);
      expect(provider.preResults, isEmpty);
      expect(provider.recommendation, isNull);
      expect(provider.isLoading, isFalse);
    });

    test('only the latest of two rapid loads ends the loading state', () async {
      final db = _GatedAssessmentDb();
      final provider = AssessmentProvider(
        localDb: db,
        assessmentService: _FakeAssessmentGateway(),
      );

      final loadA = provider.loadAssessments('a');
      final loadB = provider.loadAssessments('b');

      // The older load finishing must not hide the newer load's spinner.
      db.release('a');
      await loadA;
      expect(provider.isLoading, isTrue);

      db.release('b');
      await loadB;
      expect(provider.isLoading, isFalse);
      expect(provider.preResults.single.childId, 'b');
    });

    test('a child without records gets an empty dashboard, not the '
        "previous child's", () async {
      final db = _GatedAssessmentDb(childrenWithData: {'a'});
      final provider = AssessmentProvider(
        localDb: db,
        assessmentService: _FakeAssessmentGateway(),
      );

      db.release('a');
      await provider.loadAssessments('a');
      expect(provider.hasPreAssessment, isTrue);
      expect(provider.recommendation, isNotNull);

      db.release('empty');
      await provider.loadAssessments('empty');
      expect(provider.hasPreAssessment, isFalse);
      expect(provider.preResults, isEmpty);
      expect(provider.recommendation, isNull);
    });
  });

  group('ProgressProvider stale-load rejection', () {
    test(
      'a slow load for the previous child cannot overwrite the new child',
      () async {
        final db = _GatedProgressDb();
        final provider = ProgressProvider(localDb: db);

        final loadA = provider.loadProgress('a');
        provider.clear();
        final loadB = provider.loadProgress('b');
        db.release('b');
        await loadB;
        expect(provider.modules.single.childId, 'b');
        expect(provider.recentSessions.single.childId, 'b');

        db.release('a');
        await loadA;
        expect(provider.loadedChildId, 'b');
        expect(provider.modules.single.childId, 'b');
        expect(provider.recentSessions.single.childId, 'b');
        expect(provider.isLoading, isFalse);
      },
    );

    test(
      'a re-load for another child drops the old rows before querying',
      () async {
        final db = _GatedProgressDb();
        final provider = ProgressProvider(localDb: db);

        db.release('a');
        await provider.loadProgress('a');
        expect(provider.recentSessions.single.childId, 'a');

        final loadB = provider.loadProgress('b');
        expect(provider.modules, isEmpty);
        expect(provider.recentSessions, isEmpty);
        expect(provider.isLoading, isTrue);

        db.release('b');
        await loadB;
        expect(provider.recentSessions.single.childId, 'b');
      },
    );

    test("a late session for the previous child never reaches the new "
        "child's recent activity", () async {
      final db = _GatedProgressDb();
      final provider = ProgressProvider(localDb: db);

      db.release('b');
      await provider.loadProgress('b');

      // A completion callback for child A lands after the switch to B.
      provider.addSession(_session('a', id: 'late-a'));
      expect(provider.recentSessions.map((s) => s.childId), everyElement('b'));

      provider.addSession(_session('b', id: 'fresh-b'));
      expect(provider.recentSessions.first.id, 'fresh-b');
    });
  });

  group('ScreenTimeService switch isolation', () {
    test(
      "switching clears the previous child's numbers synchronously",
      () async {
        SharedPreferences.setMockInitialValues({});
        final service = ScreenTimeService.instance;
        await service.load('screen-a');
        await service.setLimitMinutes(30);
        // Usage only counts inside an owned child-mode session.
        await service.startSession();
        await service.addUsage(300);
        expect(service.usedTodaySeconds, 300);

        // Before the new child's stored values are even read, the old
        // child's usage and limit must already be off the dashboard.
        final loadB = service.load('screen-b');
        expect(service.loadedChildId, 'screen-b');
        expect(service.usedTodaySeconds, 0);
        expect(service.limitMinutes, isNull);

        await loadB;
        expect(service.usedTodaySeconds, 0);
        expect(service.limitEnabled, isFalse);
      },
    );

    test('two rapid switches settle on the last child', () async {
      SharedPreferences.setMockInitialValues({
        'screen_time_limit_screen-c': 20,
        'screen_time_limit_screen-d': 45,
      });
      final service = ScreenTimeService.instance;
      final loadC = service.load('screen-c');
      final loadD = service.load('screen-d');
      await Future.wait([loadC, loadD]);

      expect(service.loadedChildId, 'screen-d');
      expect(service.limitMinutes, 45);
    });
  });

  group('account-wide state', () {
    test('Premium entitlement is untouched by a child switch', () async {
      SharedPreferences.setMockInitialValues({});
      EntitlementService.instance.debugSetRealPremium(true);
      addTearDown(() => EntitlementService.instance.debugSetRealPremium(false));

      final childProvider = ChildProvider(
        localDb: _FakeChildrenDb([
          _child('a', createdAt: DateTime(2026, 1, 1)),
          _child('b', createdAt: DateTime(2026, 2, 1)),
        ]),
        authService: FakeAuthService.boundAccount(),
      );
      final assessmentProvider = AssessmentProvider(
        localDb:
            _GatedAssessmentDb()
              ..release('a')
              ..release('b'),
        assessmentService: _FakeAssessmentGateway(),
      );
      final progressProvider = ProgressProvider(
        localDb:
            _GatedProgressDb()
              ..release('a')
              ..release('b'),
      );

      await childProvider.loadProfile();
      expect(childProvider.activeChildId, 'a');

      final switched = await switchActiveChild(
        childId: 'b',
        childProvider: childProvider,
        assessmentProvider: assessmentProvider,
        progressProvider: progressProvider,
      );

      expect(switched, isTrue);
      expect(childProvider.activeChildId, 'b');
      expect(EntitlementService.instance.isPremium, isTrue);
    });
  });
}

// ── Fixtures ────────────────────────────────────────────────────────────

ChildProfile _child(String id, {required DateTime createdAt}) => ChildProfile(
  id: id,
  userId: 'user-1',
  displayName: 'Child $id',
  birthDate: DateTime(2020, 1, 1),
  avatar: '🐻',
  createdAt: createdAt,
  updatedAt: createdAt,
);

GameplaySession _session(String childId, {required String id}) =>
    GameplaySession(
      id: id,
      childId: childId,
      gameId: 'match_it',
      context: 'practice',
      score: 5,
      totalItems: 10,
      errorCount: 1,
      totalResponseTimeMs: 12000,
      startedAt: DateTime(2026, 6, 1),
      endedAt: DateTime(2026, 6, 1, 0, 5),
    );

/// Offline-first DB stand-in whose per-child queries block until [release]
/// is called for that child — the tool for interleaving two loads.
class _GatedAssessmentDb extends core_db.LocalDbService {
  _GatedAssessmentDb({this.childrenWithData});

  /// When set, only these children have any assessment rows.
  final Set<String>? childrenWithData;

  final Map<String, Completer<void>> _gates = {};

  Completer<void> _gate(String childId) =>
      _gates.putIfAbsent(childId, Completer<void>.new);

  void release(String childId) {
    final gate = _gate(childId);
    if (!gate.isCompleted) gate.complete();
  }

  @override
  Future<List<AssessmentResult>> getAssessmentResults({
    required String childId,
    String? type,
    bool includeDeleted = false,
  }) async {
    await _gate(childId).future;
    final hasData = childrenWithData?.contains(childId) ?? true;
    return type == 'pre' && hasData
        ? [
          AssessmentResult(
            id: 'result-$childId',
            childId: childId,
            type: 'pre',
            gameId: 'match_it',
            score: 5,
            totalItems: 10,
            errorCount: 1,
            avgResponseTimeMs: 1200,
            completedAt: DateTime(2026, 6, 1),
          ),
        ]
        : const [];
  }
}

/// Legacy cache stand-in behind [ProgressProvider], gated the same way.
class _GatedProgressDb extends legacy_db.LocalDbService {
  final Map<String, Completer<void>> _gates = {};

  Completer<void> _gate(String childId) =>
      _gates.putIfAbsent(childId, Completer<void>.new);

  void release(String childId) {
    final gate = _gate(childId);
    if (!gate.isCompleted) gate.complete();
  }

  @override
  Future<List<ModuleProgress>> getModuleProgress(String childId) async {
    await _gate(childId).future;
    return [
      ModuleProgress(
        id: 'module-$childId',
        childId: childId,
        moduleId: 'communication',
        moduleName: 'Communication',
        status: 'in_progress',
        currentLevel: 1,
        updatedAt: DateTime(2026, 6, 1),
      ),
    ];
  }

  @override
  Future<List<GameplaySession>> getSessionsForChild(String childId) async {
    await _gate(childId).future;
    return [_session(childId, id: 'session-$childId')];
  }
}

/// Children-only DB stand-in for [ChildProvider].
class _FakeChildrenDb extends core_db.LocalDbService {
  _FakeChildrenDb(this._children);

  final List<ChildProfile> _children;

  @override
  Future<List<ChildProfile>> getChildren({
    String? userId,
    bool includeDeleted = false,
  }) async => _children;
}

/// Recommendation engine stand-in — it only has to say which child's
/// results it was handed.
class _FakeAssessmentGateway implements AssessmentGateway {
  @override
  Map<String, dynamic> recommendModule(List<AssessmentResult> preResults) => {
    'module_id': 'communication',
    'child_id': preResults.first.childId,
  };

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
