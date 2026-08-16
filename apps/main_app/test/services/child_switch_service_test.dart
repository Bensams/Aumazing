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
import 'package:aumazing/services/screen_time_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';

import '../support/fake_auth.dart';

/// AUM-150 — switching the active child has to rebuild *all* child-specific
/// state, and must never leave the previous child's data on screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ChildProfile child(String id, {required DateTime createdAt}) => ChildProfile(
    id: id,
    userId: 'user-1',
    displayName: 'Child $id',
    birthDate: DateTime(2020, 1, 1),
    avatar: '🐻',
    createdAt: createdAt,
    updatedAt: createdAt,
  );

  final childA = child('a', createdAt: DateTime(2026, 1, 1));
  final childB = child('b', createdAt: DateTime(2026, 2, 1));

  late ChildProvider childProvider;
  late AssessmentProvider assessmentProvider;
  late ProgressProvider progressProvider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'language_a': 'ceb',
      'difficulty_override_a': 3,
      'path_progress_a': <String>['match_it'],
      'screen_time_limit_a': 15,
      'language_b': 'en',
      'screen_time_limit_b': 45,
    });

    childProvider = ChildProvider(
      localDb: _FakeCoreDb([childA, childB]),
      authService: FakeAuthService.boundAccount(),
    );
    assessmentProvider = AssessmentProvider(
      localDb: _FakeCoreDb([childA, childB]),
      assessmentService: _FakeAssessmentGateway(),
    );
    progressProvider = ProgressProvider(localDb: _FakeLegacyDb());

    await childProvider.loadProfile();
    await reloadChildScopedState(
      childId: 'a',
      childProvider: childProvider,
      assessmentProvider: assessmentProvider,
      progressProvider: progressProvider,
    );
  });

  test('the starting state belongs to the first child', () async {
    expect(childProvider.activeChildId, 'a');
    expect(assessmentProvider.preResults.single.childId, 'a');
    expect(assessmentProvider.recommendation!['child_id'], 'a');
    expect(progressProvider.modules.single.childId, 'a');
    expect(progressProvider.recentSessions.single.childId, 'a');
    expect(assessmentProvider.pathCompletedGameIds, {'match_it'});
    expect(ScreenTimeService.instance.limitMinutes, 15);
    expect(childProvider.language, GameLanguage.cebuano);
    expect(childProvider.difficultyOverride, 3);
  });

  test('switching reloads every piece of child-specific state', () async {
    final switched = await switchActiveChild(
      childId: 'b',
      childProvider: childProvider,
      assessmentProvider: assessmentProvider,
      progressProvider: progressProvider,
    );

    expect(switched, isTrue);
    expect(childProvider.activeChildId, 'b');

    // Dashboard / assessment results and recommendations
    expect(assessmentProvider.preResults.single.childId, 'b');
    expect(assessmentProvider.recommendation!['child_id'], 'b');
    // Learning-path progress
    expect(assessmentProvider.pathCompletedGameIds, isEmpty);
    // Gameplay records and module progress
    expect(progressProvider.modules.single.childId, 'b');
    expect(progressProvider.recentSessions.single.childId, 'b');
    // Screen time
    expect(ScreenTimeService.instance.loadedChildId, 'b');
    expect(ScreenTimeService.instance.limitMinutes, 45);
    // Language, voice and the appearance preferences
    expect(childProvider.language, GameLanguage.english);
    expect(childProvider.voicePack.languageSlug, 'en');
    expect(childProvider.difficultyOverride, isNull);
    expect(childProvider.isThemeOverridden, isFalse);
    expect(childProvider.isWorldOverridden, isFalse);
    expect(childProvider.hasCustomBackground, isFalse);
  });

  test('no record of the previous child survives the switch', () async {
    await switchActiveChild(
      childId: 'b',
      childProvider: childProvider,
      assessmentProvider: assessmentProvider,
      progressProvider: progressProvider,
    );

    expect([
      ...assessmentProvider.preResults.map((r) => r.childId),
      ...assessmentProvider.postResults.map((r) => r.childId),
      ...progressProvider.modules.map((m) => m.childId),
      ...progressProvider.recentSessions.map((s) => s.childId),
    ], everyElement('b'));
  });

  test('an unknown child id is refused', () async {
    final switched = await switchActiveChild(
      childId: 'ghost',
      childProvider: childProvider,
      assessmentProvider: assessmentProvider,
      progressProvider: progressProvider,
    );

    expect(switched, isFalse);
    expect(childProvider.activeChildId, 'a');
  });
}

/// Offline-first DB stand-in: children plus one assessment result per child.
class _FakeCoreDb extends core_db.LocalDbService {
  _FakeCoreDb(this._children);

  final List<ChildProfile> _children;

  @override
  Future<List<ChildProfile>> getChildren({
    String? userId,
    bool includeDeleted = false,
  }) async => _children;

  @override
  Future<List<AssessmentResult>> getAssessmentResults({
    required String childId,
    String? type,
    bool includeDeleted = false,
  }) async =>
      type == 'pre'
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

/// Recommendation engine stand-in — it only has to say which child's results
/// it was handed.
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

/// Cache stand-in behind [ProgressProvider].
///
/// Extends the *core* service: that is the database sessions are written
/// to, and the one the provider reads.
class _FakeLegacyDb extends core_db.LocalDbService {
  @override
  Future<List<ModuleProgress>> getModuleProgress(String childId) async => [
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

  @override
  Future<List<GameplaySession>> getGameSessions({
    String? childId,
    String? context,
    bool includeDeleted = false,
  }) async => [
    GameplaySession(
      id: 'session-$childId',
      childId: childId!,
      gameId: 'match_it',
      context: 'practice',
      score: 5,
      totalItems: 10,
      errorCount: 1,
      totalResponseTimeMs: 12000,
      startedAt: DateTime(2026, 6, 1),
      endedAt: DateTime(2026, 6, 1, 0, 5),
    ),
  ];
}
