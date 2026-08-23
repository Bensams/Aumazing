import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:game_core/game_core.dart';
import 'package:shared_ui/shared_ui.dart';

import 'package:aumazing/features/child_mode/path_map_view.dart';
import 'package:aumazing/services/learning_path_service.dart';

/// Three real registry games make a path whose per-game art is what a child
/// would actually see.
List<LearningPathEntry> _path() {
  const ids = ['match_it', 'copy_me', 'do_what_i_say'];
  final out = <LearningPathEntry>[];
  for (final id in ids) {
    final g = GameRegistry.find(id);
    if (g != null) {
      out.add(LearningPathEntry(game: g, difficulty: 1, areaKey: 'play'));
    }
  }
  return out;
}

/// Hosts a [PathMapView] whose completed set can be advanced, so a test can
/// drive a completion the way finishing a game does in the app.
class _Host extends StatefulWidget {
  const _Host({
    required this.style,
    this.reducedMotion = false,
    this.navKey,
    this.onShipDocked,
  });
  final WorldStyle style;
  final bool reducedMotion;
  final GlobalKey<NavigatorState>? navKey;
  final VoidCallback? onShipDocked;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late final List<LearningPathEntry> path = _path();
  late Set<String> completed = {path.first.game.id};

  void finishCurrent() {
    final next = path.firstWhere(
      (e) => !completed.contains(e.game.id),
      orElse: () => path.last,
    );
    setState(() => completed = {...completed, next.game.id});
  }

  /// Rebuild without advancing — the lobby does this after taking a parked
  /// path "Next", which is what arms the already-docked announce.
  void tick() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: widget.navKey,
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 500,
          child: PathMapView(
            path: path,
            completedGameIds: completed,
            difficultyOverride: null,
            style: widget.style,
            reducedMotion: widget.reducedMotion,
            currentStepKey: GlobalKey(),
            onLaunch: (_, __) {},
            onShipDocked: widget.onShipDocked,
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('a spaceship is docked on the path in the space world',
      (tester) async {
    await tester.pumpWidget(const _Host(style: WorldStyles.nightSky));
    await tester.pump();
    expect(find.byType(Spaceship), findsOneWidget);
  });

  testWidgets('no spaceship in the classic world', (tester) async {
    await tester.pumpWidget(const _Host(style: WorldStyles.classic));
    await tester.pump();
    expect(find.byType(Spaceship), findsNothing);
  });

  testWidgets('the ship flies onward to the next step on completion',
      (tester) async {
    await tester.pumpWidget(const _Host(style: WorldStyles.nightSky));
    await tester.pump();
    final startX = tester.getCenter(find.byType(Spaceship)).dx;

    // Finish the current game — the next step (to the right) becomes current.
    final host = tester.state<_HostState>(find.byType(_Host));
    host.finishCurrent();
    await tester.pump(); // kick off the flight

    // Mid-flight it has already moved off its start dock.
    await tester.pump(const Duration(milliseconds: 500));
    final midX = tester.getCenter(find.byType(Spaceship)).dx;
    expect(midX, greaterThan(startX));

    // Past the flight duration it has landed further along the path. (A plain
    // pump, not pumpAndSettle — the idle hover bob never settles.)
    await tester.pump(const Duration(milliseconds: 900));
    final endX = tester.getCenter(find.byType(Spaceship)).dx;
    expect(endX, greaterThan(startX + 100));
  });

  testWidgets('a flight queued while in a game plays on return to the path',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _Host(style: WorldStyles.nightSky, navKey: navKey),
    );
    await tester.pump();
    final startX = tester.getCenter(find.byType(Spaceship)).dx;

    // Cover the path with a game screen, the way launching a game does.
    navKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('game'))),
    );
    await tester.pumpAndSettle();

    // Finish the current game while the path is hidden — the flight is queued,
    // not run off screen.
    tester.state<_HostState>(find.byType(_Host)).finishCurrent();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Return to the path. The queued flight now plays: partway through, the
    // ship is between its old dock and its destination (proving it animated on
    // return rather than having jumped while hidden); then it lands advanced.
    navKey.currentState!.pop();
    await tester.pump(); // begin the pop
    await tester.pump(const Duration(milliseconds: 400)); // pop completes
    await tester.pump(const Duration(milliseconds: 300)); // into the flight
    final midX = tester.getCenter(find.byType(Spaceship)).dx;
    await tester.pump(const Duration(milliseconds: 1000)); // land
    final endX = tester.getCenter(find.byType(Spaceship)).dx;

    expect(midX, greaterThan(startX));
    expect(midX, lessThan(endX));
    expect(endX, greaterThan(startX + 100));
  });

  testWidgets('reduced motion snaps the ship without a flight', (tester) async {
    await tester.pumpWidget(
      const _Host(style: WorldStyles.nightSky, reducedMotion: true),
    );
    await tester.pump();
    final startX = tester.getCenter(find.byType(Spaceship)).dx;

    tester.state<_HostState>(find.byType(_Host)).finishCurrent();
    await tester.pump(); // one frame — no animation should be scheduled
    expect(tester.hasRunningAnimations, isFalse);
    final afterX = tester.getCenter(find.byType(Spaceship)).dx;
    expect(afterX, greaterThan(startX + 100));
  });

  testWidgets('onShipDocked fires once the ship finishes flying to the next '
      'step', (tester) async {
    var docked = 0;
    await tester.pumpWidget(
      _Host(style: WorldStyles.nightSky, onShipDocked: () => docked++),
    );
    await tester.pump();

    // Nothing has completed yet — the ship is idle on its dock, no dock event.
    expect(docked, 0);

    tester.state<_HostState>(find.byType(_Host)).finishCurrent();
    await tester.pump(); // kick off the flight

    // Still in flight — the game must not open until the ship arrives.
    await tester.pump(const Duration(milliseconds: 500));
    expect(docked, 0, reason: 'launched before the ship docked');

    // Past the 1100ms flight the ship lands and the dock is announced once.
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(); // let the post-frame notify run
    expect(docked, 1);
  });

  testWidgets('reduced motion announces the dock on the snap', (tester) async {
    var docked = 0;
    await tester.pumpWidget(
      _Host(
        style: WorldStyles.nightSky,
        reducedMotion: true,
        onShipDocked: () => docked++,
      ),
    );
    await tester.pump();
    expect(docked, 0);

    tester.state<_HostState>(find.byType(_Host)).finishCurrent();
    await tester.pump(); // snap, no flight
    await tester.pump(); // let the post-frame notify run
    expect(tester.hasRunningAnimations, isFalse);
    expect(docked, 1, reason: 'a snapped arrival is still an arrival');
  });

  testWidgets('classic world announces the dock on the snap', (tester) async {
    var docked = 0;
    await tester.pumpWidget(
      _Host(style: WorldStyles.classic, onShipDocked: () => docked++),
    );
    await tester.pump();
    expect(find.byType(Spaceship), findsNothing);
    expect(docked, 0);

    tester.state<_HostState>(find.byType(_Host)).finishCurrent();
    await tester.pump();
    await tester.pump();
    expect(docked, 1, reason: 'no ship still means the step advanced');
  });

  testWidgets(
      'returning to a ship already on the current step still announces dock',
      (tester) async {
    var docked = 0;
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _Host(
        style: WorldStyles.nightSky,
        navKey: navKey,
        onShipDocked: () => docked++,
      ),
    );
    await tester.pump();
    expect(docked, 0);

    // Cover the path without advancing it — a replay of an earlier step, then
    // "Next", lands back on a ship that has nowhere to fly.
    navKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('game')),
      ),
    );
    await tester.pumpAndSettle();
    expect(docked, 0);

    navKey.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Lobby setState after taking the parked launch.
    tester.state<_HostState>(find.byType(_Host)).tick();
    await tester.pump();
    await tester.pump(); // post-frame notify
    expect(docked, 1, reason: 'a parked Next must not wait on a flight that '
        'will never start');
  });
}
