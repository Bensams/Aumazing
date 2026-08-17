import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aumazing/features/games/session_recording.dart';
import 'package:aumazing/model/assessment_result.dart';
import 'package:aumazing/model/gameplay_session.dart';
import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/providers/progress_provider.dart';
import 'package:aumazing/services/assessment_service.dart';

/// Records what reached the storage layer, so a test can tell "nothing was
/// written" apart from "something was written under a made-up id".
class _RecordingGateway implements AssessmentGateway {
  final List<String> writtenChildIds = [];

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
    bool applySessionSensoryDefaults = true,
  }) async {
    writtenChildIds.add(childId);
    return GameplaySession(
      id: 'session-${writtenChildIds.length}',
      childId: childId,
      assessmentRunId: assessmentRunId,
      gameId: gameId,
      context: context,
      score: score,
      totalItems: totalItems,
      errorCount: errorCount,
      totalResponseTimeMs: totalResponseTimeMs,
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(minutes: 2)),
    );
  }

  @override
  Future<String> startAssessmentRun({
    required String childId,
    required String type,
  }) async => 'run-1';

  @override
  Future<void> completeAssessmentRun(String runId) async {}

  @override
  Future<int> abandonOpenRuns(String childId) async => 0;

  @override
  Future<OpenAssessmentRun?> openAssessmentRun(String childId) async => null;

  @override
  Future<AssessmentResult> createAssessmentResult({
    required String childId,
    required String type,
    required String gameId,
    required List<GameplaySession> sessions,
    String? assessmentRunId,
  }) async => throw UnimplementedError();

  @override
  Map<String, dynamic> recommendModule(List<AssessmentResult> preResults) =>
      throw UnimplementedError();

  @override
  Map<String, dynamic> compareAssessments({
    required List<AssessmentResult> preResults,
    required List<AssessmentResult> postResults,
  }) => throw UnimplementedError();
}

/// Pumps a screen that finishes a game as soon as it is tapped, and hands
/// back the pending [GameSessionRecording.record] call.
///
/// The future is returned rather than awaited: a dialog can be waiting for
/// the parent, and awaiting here would deadlock the test that has to dismiss
/// it.
Future<Future<bool>> _finishGame(
  WidgetTester tester, {
  required String? childId,
  required _RecordingGateway gateway,
}) async {
  late Future<bool> recorded;
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AssessmentProvider(assessmentService: gateway),
        ),
        ChangeNotifierProvider(create: (_) => ProgressProvider()),
      ],
      child: MaterialApp(
        home: Builder(
          builder:
              (context) => TextButton(
                onPressed: () {
                  recorded = GameSessionRecording.record(
                    context,
                    childId: childId,
                    gameId: 'match_it',
                    assessmentContext: 'practice',
                    score: 8,
                    totalItems: 10,
                    errorCount: 2,
                    totalResponseTimeMs: 12000,
                    startedAt: DateTime(2026, 8, 1, 9),
                  );
                },
                child: const Text('finish'),
              ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('finish'));
  await tester.pumpAndSettle();
  return recorded;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a completion with no loaded profile writes no session', (
    tester,
  ) async {
    final gateway = _RecordingGateway();

    final recorded = await _finishGame(
      tester,
      childId: null,
      gateway: gateway,
    );

    // Nothing at all — in particular no row under a fabricated id, which
    // would be invisible to the dashboard and unscorable (AUM-245).
    expect(gateway.writtenChildIds, isEmpty);

    // And the loss is surfaced rather than celebrated over.
    expect(find.text('Could not save this game'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(await recorded, isFalse);
  });

  testWidgets('a completion with a loaded profile is recorded as before', (
    tester,
  ) async {
    final gateway = _RecordingGateway();

    final recorded = await _finishGame(
      tester,
      childId: 'child-1',
      gateway: gateway,
    );

    expect(gateway.writtenChildIds, ['child-1']);
    expect(await recorded, isTrue);
    expect(find.text('Could not save this game'), findsNothing);
  });
}
