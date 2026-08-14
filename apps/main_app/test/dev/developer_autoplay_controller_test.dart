import 'package:flutter_test/flutter_test.dart';

import 'package:aumazing/dev/developer_automation_registry.dart';
import 'package:aumazing/dev/developer_autoplay_controller.dart';
import 'package:aumazing/dev/developer_tools_config.dart';

/// A stand-in for a real game screen: it becomes ready after a few polls
/// (a demo phase), takes [actionsToFinish] valid actions to finish, and then
/// reports completion the way a screen's game-complete handler does.
///
/// Nothing here writes a session — that is the point. Automation's only lever
/// is [DeveloperGameSession.performCorrectAction], so if the controller ever
/// "completed" a game another way, these counters would not add up.
class _ScriptedGame {
  _ScriptedGame({
    required this.gameId,
    this.actionsToFinish = 3,
    this.pollsBeforeReady = 2,
  });

  final String gameId;
  final String assessmentContext = 'pre_assessment';
  final int actionsToFinish;
  final int pollsBeforeReady;

  int actions = 0;
  int readyChecks = 0;
  late final DeveloperGameSession session = DeveloperGameSession.forTest(
    gameId: gameId,
    assessmentContext: assessmentContext,
    awaitingInput: () {
      readyChecks++;
      return readyChecks > pollsBeforeReady && actions < actionsToFinish;
    },
    performAction: () {
      actions++;
      // The game's own completion callback fires on the last action, which is
      // what marks the session complete in production too.
      if (actions >= actionsToFinish) session.markComplete();
    },
  );

  DeveloperGameSession register() =>
      DeveloperAutomationRegistry.instance.adoptGame(session)!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final controller = DeveloperAutoPlayController.instance;
  final registry = DeveloperAutomationRegistry.instance;

  setUp(() {
    DeveloperToolsConfig.debugAvailableOverride = true;
    controller.resetForTest();
    registry.reset();
  });

  tearDown(() {
    controller.resetForTest();
    registry.reset();
    DeveloperToolsConfig.debugAvailableOverride = null;
  });

  group('driving a single game', () {
    test('advances only through real in-game actions', () async {
      final game = _ScriptedGame(gameId: 'copy_me', actionsToFinish: 4);
      game.register();

      await controller.playCurrentGame(speed: AutoPlaySpeed.veryFast);

      expect(game.actions, 4,
          reason: 'exactly the actions the game needed, no more');
      expect(game.session.isComplete, isTrue);
      expect(controller.status, AutoPlayStatus.finished);
      expect(controller.completedCount, 1, reason: 'one session per game');
    });

    test('waits out a demo phase instead of forcing input', () async {
      final game = _ScriptedGame(
        gameId: 'copy_me',
        actionsToFinish: 2,
        pollsBeforeReady: 5,
      );
      game.register();

      await controller.playCurrentGame(speed: AutoPlaySpeed.veryFast);

      expect(game.readyChecks, greaterThan(5),
          reason: 'it polled while the game was busy');
      expect(game.actions, 2, reason: 'and never acted early');
    });

    test('never acts on a game that has already completed', () async {
      final game = _ScriptedGame(gameId: 'match_it', actionsToFinish: 1);
      game.session.markComplete();
      game.register();

      await controller.playCurrentGame(speed: AutoPlaySpeed.veryFast);

      expect(game.actions, 0);
      expect(controller.status, AutoPlayStatus.finished);
    });
  });

  group('a four-game assessment', () {
    /// Registers each game as the previous one finishes, the way the
    /// pre-assessment flow does between rewards and transitions.
    Future<List<_ScriptedGame>> runFourGames(Future<void> run) async {
      const ids = ['copy_me', 'do_what_i_say', 'my_turn_your_turn', 'match_it'];
      final games = <_ScriptedGame>[];

      for (var i = 0; i < ids.length; i++) {
        final game = _ScriptedGame(gameId: ids[i], actionsToFinish: 2);
        games.add(game);
        game.register();
        // Let the controller drive this one to completion before the flow
        // moves on.
        while (!game.session.isComplete) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        if (i < ids.length - 1) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
      await run;
      return games;
    }

    test('plays all four, one session each', () async {
      final run = controller.start(
        mode: AutoPlayMode.preAssessment,
        expectedGameCount: 4,
        speed: AutoPlaySpeed.veryFast,
      );

      final games = await runFourGames(run);

      expect(games.map((g) => g.actions), [2, 2, 2, 2]);
      expect(controller.completedCount, 4);
      expect(controller.status, AutoPlayStatus.finished,
          reason: 'the run ends itself once the flow is played out');
    });

    test('stops on its own rather than driving the hand-off', () async {
      final run = controller.start(
        mode: AutoPlayMode.preAssessment,
        expectedGameCount: 4,
        speed: AutoPlaySpeed.veryFast,
      );
      await runFourGames(run);

      // Nothing is left registered, and the controller is no longer active —
      // the hand-off and its parent gate are left entirely alone.
      expect(controller.isActive, isFalse);
      expect(registry.activeGame?.isComplete, isTrue);
    });
  });

  group('pause, resume and stop', () {
    test('a paused run performs no further actions until resumed', () async {
      final game = _ScriptedGame(gameId: 'copy_me', actionsToFinish: 50);
      game.register();
      final run = controller.playCurrentGame(speed: AutoPlaySpeed.veryFast);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      controller.pause();
      expect(controller.status, AutoPlayStatus.paused);

      final atPause = game.actions;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(game.actions, atPause, reason: 'a paused run is really stopped');

      controller.resume();
      expect(controller.status, AutoPlayStatus.running);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(game.actions, greaterThan(atPause));

      controller.stop();
      await run;
    });

    test('stop ends the run and leaves the game where it stands', () async {
      final game = _ScriptedGame(gameId: 'copy_me', actionsToFinish: 100);
      game.register();
      final run = controller.playCurrentGame(speed: AutoPlaySpeed.veryFast);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      controller.stop();
      await run;

      expect(controller.isActive, isFalse);
      expect(controller.status, AutoPlayStatus.finished);
      expect(game.session.isComplete, isFalse,
          reason: 'stopping does not finish the game for the child');

      final afterStop = game.actions;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(game.actions, afterStop, reason: 'no stray loop kept running');
    });

    test('stop is safe while paused', () async {
      final game = _ScriptedGame(gameId: 'copy_me', actionsToFinish: 100);
      game.register();
      final run = controller.playCurrentGame(speed: AutoPlaySpeed.veryFast);

      await Future<void>.delayed(const Duration(milliseconds: 40));
      controller.pause();
      controller.stop();
      await run.timeout(const Duration(seconds: 2));

      expect(controller.isActive, isFalse);
    });
  });

  group('skip remaining', () {
    test('finishes only the games that are left', () async {
      // The flow is on game 3 of 4, so two games remain.
      registry.registerFlow(
        flowLabel: 'Pre-Assessment',
        gameIndex: 2,
        gameCount: 4,
        launchNow: () {},
      );
      expect(registry.flowGamesRemaining, 2);

      final run = controller.skipRemainingGames();

      final games = <_ScriptedGame>[];
      for (var i = 0; i < 2; i++) {
        final game = _ScriptedGame(gameId: 'game-$i', actionsToFinish: 2);
        games.add(game);
        game.register();
        while (!game.session.isComplete) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await run;

      expect(games.map((g) => g.actions), [2, 2]);
      expect(controller.completedCount, 2,
          reason: 'the already-played games are not replayed');
    });
  });

  group('the gate', () {
    test('a run cannot start when developer tools are unavailable', () async {
      DeveloperToolsConfig.debugAvailableOverride = false;
      final game = _ScriptedGame(gameId: 'copy_me');

      await controller.playCurrentGame(speed: AutoPlaySpeed.veryFast);

      expect(controller.status, AutoPlayStatus.idle);
      expect(controller.isActive, isFalse);
      expect(game.actions, 0);
    });

    test('a game cannot even register when tools are unavailable', () {
      DeveloperToolsConfig.debugAvailableOverride = false;

      expect(
        registry.adoptGame(DeveloperGameSession.forTest(
          gameId: 'copy_me',
          assessmentContext: 'pre_assessment',
          awaitingInput: () => true,
          performAction: () {},
        )),
        isNull,
      );
      expect(registry.activeGame, isNull);
    });
  });

  group('status line', () {
    test('reports the flow position the child can see', () async {
      registry.registerFlow(
        flowLabel: 'Pre-Assessment',
        gameIndex: 1,
        gameCount: 4,
        launchNow: () {},
      );
      final game = _ScriptedGame(gameId: 'copy_me', actionsToFinish: 100);
      game.register();
      final run = controller.start(
        mode: AutoPlayMode.preAssessment,
        expectedGameCount: 4,
        speed: AutoPlaySpeed.veryFast,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(controller.statusLine, 'DEV AUTO: Pre-Assessment — Game 2 of 4');

      controller.pause();
      expect(controller.statusLine,
          'DEV AUTO: Pre-Assessment — Game 2 of 4 (paused)');

      controller.stop();
      await run;
      expect(controller.statusLine, isNull, reason: 'no run, no status line');
    });
  });
}
