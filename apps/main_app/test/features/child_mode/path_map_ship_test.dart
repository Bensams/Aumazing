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
  const _Host({required this.style, this.reducedMotion = false, this.navKey});
  final WorldStyle style;
  final bool reducedMotion;
  final GlobalKey<NavigatorState>? navKey;

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
}
