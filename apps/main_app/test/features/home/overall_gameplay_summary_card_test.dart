import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

import 'package:aumazing/features/home/widgets/overall_gameplay_summary_card.dart';
import 'package:aumazing/services/overall_gameplay_summary_service.dart';
import 'package:aumazing/services/rubric/rubric.dart';

/// Serves a fixed input and summary without a database or network.
class _FakeService extends OverallGameplaySummaryService {
  _FakeService(this.result);

  final OverallGameplaySummary? result;
  int forcedRefreshes = 0;

  static const input = GameplaySummaryInput(
    assessments: [],
    pathGames: [
      SummaryPathGame(
        gameId: 'trace_it',
        name: 'Trace It',
        plays: 3,
        avgAccuracyPct: 70,
        reachedStrength: true,
        tries: 3,
      ),
      SummaryPathGame(
        gameId: 'hintay',
        name: 'Hintay!',
        plays: 2,
        avgAccuracyPct: 50,
        reachedStrength: false,
        tries: 2,
      ),
    ],
    recommendedPlays: 5,
    fingerprint: 'f',
  );

  @override
  Future<GameplaySummaryInput> buildInput({
    required String childId,
    List<String> pathGameIds = const [],
    Map<String, PathAttemptRecord> pathAttempts = const {},
  }) async => input;

  @override
  Future<OverallGameplaySummary?> summarize({
    required String childId,
    required GameplaySummaryInput input,
    String languageCode = 'en',
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) forcedRefreshes++;
    return result;
  }
}

Widget _host(OverallGameplaySummaryService service) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: SingleChildScrollView(
      child: OverallGameplaySummaryCard(
        childId: 'child-1',
        pathGameIds: const ['trace_it', 'hintay'],
        pathAttempts: const {},
        refreshToken: 0,
        service: service,
      ),
    ),
  ),
);

void main() {
  testWidgets('a Gemini summary is labelled as AI and lists the questions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _FakeService(
          OverallGameplaySummary(
            summary: 'Your child is growing.',
            questions: const ['What should we practise at home?'],
            source: GameplaySummarySource.gemini,
            generatedAt: DateTime(2026, 9, 20),
            fromCache: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('overallSummarySourceAi')),
      findsOneWidget,
    );
    expect(find.text('AI · Gemini'), findsOneWidget);
    expect(find.text('Your child is growing.'), findsOneWidget);
    expect(find.text('What should we practise at home?'), findsOneWidget);
    expect(find.byKey(const ValueKey('overallSummaryCached')), findsOneWidget);
    expect(find.text('Strength after 3 tries (2 retries)'), findsOneWidget);
    expect(find.text('Practising · 2 tries so far'), findsOneWidget);
    expect(find.byKey(const ValueKey('overallSummaryRetryAi')), findsNothing);
  });

  testWidgets('a Groq summary is labelled as the Gemini fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _FakeService(
          OverallGameplaySummary(
            summary: 'From the fallback model.',
            questions: const ['What next?'],
            source: GameplaySummarySource.groq,
            generatedAt: DateTime(2026, 9, 20),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('overallSummarySourceGroq')),
      findsOneWidget,
    );
    expect(find.text('AI · Groq'), findsOneWidget);
    expect(find.textContaining('Gemini AI was at its limit'), findsOneWidget);
    expect(find.byKey(const ValueKey('overallSummaryRetryAi')), findsNothing);
  });

  testWidgets('an on-device summary says so and offers to try AI again', (
    tester,
  ) async {
    final service = _FakeService(
      OverallGameplaySummary(
        summary: 'Written here.',
        questions: const ['Which goals first?'],
        source: GameplaySummarySource.onDevice,
        generatedAt: DateTime(2026, 9, 20),
      ),
    );
    await tester.pumpWidget(_host(service));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('overallSummarySourceDevice')),
      findsOneWidget,
    );
    expect(find.text('On-device summary'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('overallSummaryRetryAi')));
    await tester.pumpAndSettle();
    expect(service.forcedRefreshes, 1);
  });

  testWidgets('with nothing to summarize the card explains what comes next', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_FakeService(null)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('overallSummaryEmpty')), findsOneWidget);
  });
}
