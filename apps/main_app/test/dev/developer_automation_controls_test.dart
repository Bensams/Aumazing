import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';

import 'package:aumazing/dev/developer_automation_bar.dart';
import 'package:aumazing/dev/developer_automation_registry.dart';
import 'package:aumazing/dev/developer_autoplay_controller.dart';
import 'package:aumazing/dev/developer_tools_config.dart';

/// The automation controls are the most visible part of the toolbox and the
/// one most likely to be caught in a screenshot, so "absent unless developer
/// tools are on" has to hold at every layer: the game-side hooks, the
/// registry, and the on-screen bar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final registry = DeveloperAutomationRegistry.instance;
  final controller = DeveloperAutoPlayController.instance;

  setUp(() {
    controller.resetForTest();
    registry.reset();
  });

  tearDown(() {
    controller.resetForTest();
    registry.reset();
    DeveloperToolsConfig.debugAvailableOverride = null;
    DeveloperAutomation.disable();
  });

  DeveloperGameSession session({bool complete = false}) {
    final s = DeveloperGameSession.forTest(
      gameId: 'copy_me',
      assessmentContext: 'pre_assessment',
      awaitingInput: () => true,
      performAction: () {},
    );
    if (complete) s.markComplete();
    return s;
  }

  Widget app() => MaterialApp(
        home: Scaffold(
          body: DeveloperAutomationBar(onSkipRemaining: () async {}),
        ),
      );

  group('which games automation can drive', () {
    test('only the games that actually expose a hook', () {
      // Every id here must have a screen that calls registerGame and a Flame
      // class mixing in DeveloperAutomationHooks. Adding an id without both
      // would make auto-play wait for input that never arrives.
      expect(DeveloperAutomationRegistry.automatableGameIds, {
        'copy_me',
        'do_what_i_say',
        'my_turn_your_turn',
        'match_it',
      });

      expect(DeveloperAutomationRegistry.canAutomate('copy_me'), isTrue);
      // The remaining practice games are not hooked yet, and the toolbox has
      // to say so rather than start a run that can only time out.
      for (final gameId in const [
        'sari_sari_sort',
        'trace_it',
        'hintay',
        'anong_susunod',
        'sabay_tayo',
        'kumusta',
        'anong_nararamdaman',
        'tulong_kaibigan',
      ]) {
        expect(DeveloperAutomationRegistry.canAutomate(gameId), isFalse,
            reason: '$gameId has no automation hook yet');
      }
    });
  });

  group('game-side hooks', () {
    test('are shut unless a run opens them', () {
      DeveloperAutomation.disable();
      expect(DeveloperAutomation.isEnabled, isFalse);

      DeveloperAutomation.enable();
      expect(DeveloperAutomation.isEnabled, isTrue,
          reason: 'tests run in debug, where enable() is allowed to work');

      DeveloperAutomation.disable();
      expect(DeveloperAutomation.isEnabled, isFalse);
    });
  });

  group('when developer tools are unavailable', () {
    setUp(() => DeveloperToolsConfig.debugAvailableOverride = false);

    testWidgets('the automation bar renders nothing', (tester) async {
      await tester.pumpWidget(app());

      expect(find.byKey(const Key('developerAutoPlayStatus')), findsNothing);
      expect(find.byKey(const Key('developerSkipControls')), findsNothing);
      expect(find.text('Skip Game'), findsNothing);
      expect(find.text('Skip Rest'), findsNothing);
      expect(find.text('Auto-play'), findsNothing);
    });

    testWidgets('a registered game cannot make controls appear',
        (tester) async {
      // Registration is refused outright, so there is nothing to show.
      expect(registry.adoptGame(session()), isNull);

      await tester.pumpWidget(app());

      expect(find.byKey(const Key('developerSkipControls')), findsNothing);
    });
  });

  group('when developer tools are available', () {
    setUp(() => DeveloperToolsConfig.debugAvailableOverride = true);

    testWidgets('no game and no run means no bar', (tester) async {
      await tester.pumpWidget(app());

      expect(find.byKey(const Key('developerSkipControls')), findsNothing);
      expect(find.byKey(const Key('developerAutoPlayStatus')), findsNothing);
    });

    testWidgets('an open game shows the three skip controls', (tester) async {
      registry.adoptGame(session());

      await tester.pumpWidget(app());

      expect(find.byKey(const Key('developerSkipControls')), findsOneWidget);
      expect(find.byKey(const Key('developerSkipCurrentGame')), findsOneWidget);
      expect(
          find.byKey(const Key('developerSkipRemainingGames')), findsOneWidget);
      expect(
          find.byKey(const Key('developerAutoPlayCurrentGame')), findsOneWidget);
    });

    testWidgets('a finished game withdraws them again', (tester) async {
      registry.adoptGame(session(complete: true));

      await tester.pumpWidget(app());

      expect(find.byKey(const Key('developerSkipControls')), findsNothing,
          reason: 'there is nothing left to skip');
    });

    testWidgets('Skip Rest asks before completing the rest of the flow',
        (tester) async {
      var asked = false;
      registry.adoptGame(session());

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DeveloperAutomationBar(
            onSkipRemaining: () async => asked = true,
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('developerSkipRemainingGames')));
      await tester.pump();

      expect(asked, isTrue,
          reason: 'it routes through the overlay\'s confirmation, never '
              'straight into the run');
    });

    testWidgets('a running run shows the status line and its controls',
        (tester) async {
      registry.registerFlow(
        flowLabel: 'Pre-Assessment',
        gameIndex: 1,
        gameCount: 4,
        launchNow: () {},
      );
      // Not awaited: the run loop waits on real Duration delays, which only
      // advance here when the test pumps. Pumping is what drives it.
      unawaited(controller.start(
        mode: AutoPlayMode.preAssessment,
        expectedGameCount: 4,
        speed: AutoPlaySpeed.veryFast,
      ));

      await tester.pumpWidget(app());
      await tester.pump();

      expect(find.text('DEV AUTO: Pre-Assessment — Game 2 of 4'),
          findsOneWidget);
      expect(find.byKey(const Key('developerAutoPlayPauseResume')),
          findsOneWidget);
      expect(find.byKey(const Key('developerAutoPlayStop')), findsOneWidget);

      // Pausing is reflected in the same line the developer is reading.
      await tester.tap(find.byKey(const Key('developerAutoPlayPauseResume')));
      await tester.pump();
      expect(find.text('DEV AUTO: Pre-Assessment — Game 2 of 4 (paused)'),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('developerAutoPlayStop')));
      // Let the loop wake, see the stop, and unwind — no pending timers left.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();

      expect(controller.isActive, isFalse);
      expect(find.byKey(const Key('developerAutoPlayStatus')), findsNothing);
    });
  });
}
