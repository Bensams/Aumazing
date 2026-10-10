import 'package:aumazing/features/pre_assessment/learn_first_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';

/// "Let's learn first" — the unscored familiarisation step before the
/// pre- and post-assessment (SPED teachers + panel).
///
/// What must hold: every colour and shape word the assessment games use can
/// be heard, nothing is scored or gated, the grown-up can always skip, and
/// the outcome is recorded either way.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Opens the step from a host button and returns the narrator and a slot
  /// for the outcome the host receives.
  Future<(_RecordingVoiceOver, List<LearnFirstOutcome>)> open(
    WidgetTester tester, {
    String type = 'pre',
  }) async {
    await tester.binding.setSurfaceSize(const Size(1000, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final narrator = _RecordingVoiceOver();
    final outcomes = <LearnFirstOutcome>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder:
              (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async {
                      outcomes.add(
                        await LearnFirstScreen.show(
                          context,
                          assessmentType: type,
                          voiceOverFactory: (_) => narrator,
                        ),
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return (narrator, outcomes);
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('learnFirst.next')));
    await tester.pumpAndSettle();
  }

  testWidgets('every colour and shape the assessment uses can be heard', (
    tester,
  ) async {
    final (narrator, _) = await open(tester);
    // The page opens by inviting a touch.
    expect(narrator.played, [VoiceOverCue.touchThePicture]);

    for (final id in ['red', 'blue', 'green', 'yellow', 'purple', 'orange']) {
      await tester.tap(find.byKey(Key('learnFirst.word.$id')));
      await tester.pump();
    }
    expect(
      narrator.played,
      containsAll([
        VoiceOverCue.colorRed,
        VoiceOverCue.colorBlue,
        VoiceOverCue.colorGreen,
        VoiceOverCue.colorYellow,
        VoiceOverCue.colorPurple,
        VoiceOverCue.colorOrange,
      ]),
      reason: 'the six colour words Do What I Say speaks',
    );

    await next(tester);
    for (final id in ['circle', 'star', 'triangle', 'diamond', 'heart']) {
      await tester.tap(find.byKey(Key('learnFirst.word.$id')));
      await tester.pump();
    }
    expect(
      narrator.played,
      containsAll([
        VoiceOverCue.shapeCircle,
        VoiceOverCue.shapeStar,
        VoiceOverCue.shapeTriangle,
        VoiceOverCue.shapeDiamond,
        VoiceOverCue.shapeHeart,
      ]),
    );

    await next(tester);
    await tester.tap(find.byKey(const Key('learnFirst.word.red_star')));
    await tester.pump();
    expect(narrator.played.last, VoiceOverCue.phraseRedStar);
  });

  testWidgets('walking every page completes the step', (tester) async {
    final (_, outcomes) = await open(tester);

    await tester.tap(find.byKey(const Key('learnFirst.word.red')));
    await tester.pump();
    await next(tester); // shapes
    await next(tester); // together
    await next(tester); // how to play
    expect(find.text('Let\'s play!'), findsOneWidget);
    await next(tester);

    expect(find.byType(LearnFirstScreen), findsNothing);
    expect(outcomes, hasLength(1));
    expect(outcomes.single.completed, isTrue);
    expect(outcomes.single.pagesSeen, 4);
    expect(outcomes.single.wordsHeard, 1);
  });

  testWidgets(
    'nothing gates the Next arrow — a quiet child still gets through',
    (tester) async {
      final (_, outcomes) = await open(tester);
      for (var i = 0; i < 4; i++) {
        await next(tester);
      }
      expect(outcomes.single.completed, isTrue);
      expect(outcomes.single.wordsHeard, 0);
    },
  );

  testWidgets('the grown-up can skip at any point', (tester) async {
    final (narrator, outcomes) = await open(tester);
    await next(tester);

    await tester.tap(find.byKey(const Key('learnFirst.skip')));
    await tester.pumpAndSettle();

    expect(find.byType(LearnFirstScreen), findsNothing);
    expect(outcomes.single.completed, isFalse);
    expect(outcomes.single.pagesSeen, 2);
    expect(narrator.stops, greaterThan(0), reason: 'no voice left talking');
  });

  testWidgets('how to play practises a tap and a drag', (tester) async {
    final (narrator, _) = await open(tester);
    for (var i = 0; i < 3; i++) {
      await next(tester);
    }
    expect(narrator.played.last, VoiceOverCue.tapHere);

    await tester.tap(find.byKey(const Key('learnFirst.practiceTap')));
    await tester.pump();
    expect(narrator.praises, 1);

    // The invitation to drag follows the praise.
    await tester.pump(const Duration(milliseconds: 1500));
    expect(narrator.played.last, VoiceOverCue.dragIt);

    await tester.drag(
      find.byKey(const Key('learnFirst.practiceDrag')),
      tester.getCenter(find.byKey(const Key('learnFirst.practiceBox'))) -
          tester.getCenter(find.byKey(const Key('learnFirst.practiceDrag'))),
    );
    await tester.pumpAndSettle();
    expect(narrator.praises, 2);
    expect(
      find.byKey(const Key('learnFirst.practiceDrag')),
      findsNothing,
      reason: 'the card now sits in the box',
    );
  });

  test('the log keeps each step per child and type', () async {
    const outcome = LearnFirstOutcome(
      completed: false,
      duration: Duration(seconds: 42),
      pagesSeen: 2,
      wordsHeard: 3,
    );
    await LearnFirstLog.instance.record(
      childId: 'child-1',
      assessmentRunId: 'run-1',
      assessmentType: 'pre',
      outcome: outcome,
    );
    await LearnFirstLog.instance.record(
      childId: 'child-2',
      assessmentRunId: 'run-2',
      assessmentType: 'post',
      outcome: outcome,
    );

    final entries = await LearnFirstLog.instance.entriesFor('child-1');
    expect(entries, hasLength(1));
    expect(entries.single['assessment_type'], 'pre');
    expect(entries.single['assessment_run_id'], 'run-1');
    expect(entries.single['completed'], isFalse);
    expect(entries.single['duration_ms'], 42000);
    expect(entries.single['words_heard'], 3);
  });
}

/// Records what the step asked the narrator to say.
class _RecordingVoiceOver extends VoiceOverService {
  _RecordingVoiceOver() : super(languageCode: 'en_adult_woman');

  final List<VoiceOverCue> played = [];
  int praises = 0;
  int stops = 0;

  @override
  Future<void> play(
    VoiceOverCue cue, {
    bool awaitCompletion = false,
    bool skipDebounce = false,
  }) async {
    played.add(cue);
  }

  @override
  Future<void> playCorrectPraise() async {
    praises++;
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}
