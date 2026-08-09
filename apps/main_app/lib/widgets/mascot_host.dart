import 'dart:async';

import 'package:flutter/material.dart';

import 'mascot.dart';

/// Drives the mascot owned by a [MascotHost] above it in the tree.
///
/// Screens react through this rather than placing their own mascot, so a game
/// says *what happened* ("that was correct") and stays out of the business of
/// where the character sits or how it animates.
class MascotController extends ChangeNotifier {
  MascotGesture _gesture = MascotGesture.wave;
  MascotPose _pose = MascotPose.idle;
  int _tick = 0;

  MascotGesture get gesture => _gesture;
  MascotPose get pose => _pose;
  int get tick => _tick;

  /// Play [gesture] once, then return to the current pose.
  void play(MascotGesture gesture) {
    // An explicit gesture supersedes a reaction still in progress, so a
    // pending reassurance can't surface on top of it seconds later.
    _cancelReassurance();
    _play(gesture);
  }

  void _play(MascotGesture gesture) {
    _gesture = gesture;
    _tick++;
    notifyListeners();
  }

  /// React to a wrong answer.
  ///
  /// Two beats, and the second is the point of the whole thing: a brief
  /// [MascotGesture.oops] so the child can see that the answer wasn't the one
  /// being looked for, then an [MascotPose.encourage] hold — "try again, I'm
  /// with you" — before returning to idle. The character is never left sad,
  /// and never shows anger or distress at the child.
  ///
  /// A wrong answer already plays a sound and an encouraging voice line; this
  /// is the visual half of the same message and is timed to sit alongside it.
  void reassure() {
    // A second mistake while the character is still responding to the first
    // must not restart the sequence. Flicking between sad and encouraging is
    // exactly the unpredictable motion this widget exists to prevent — and
    // the reassurance already on screen covers the new mistake too.
    if (_reassuring) return;
    _reassuring = true;
    _play(MascotGesture.oops);
    // Deliberately not routed through flash(): that cancels a reassurance in
    // progress, which is right when a screen calls it but would end this one
    // the instant it reached its encouraging half.
    _recover = Timer(MascotGesture.oops.duration, () {
      _setPose(MascotPose.encourage);
      _settle = Timer(_encourageHold, () {
        _reassuring = false;
        _setPose(MascotPose.idle);
      });
    });
  }

  /// How long the encouraging pose is held before the mascot returns to idle.
  /// Long enough to be read as a reply to the mistake, short enough that it
  /// isn't still there when the child answers again.
  static const Duration _encourageHold = Duration(milliseconds: 2200);

  /// Whether a [reassure] sequence is still on screen.
  bool get isReassuring => _reassuring;
  bool _reassuring = false;

  /// Change what the mascot rests as (e.g. [MascotPose.think] while loading).
  void rest(MascotPose pose) {
    _revert?.cancel();
    // A pose a screen asked for outright wins: the encouraging half of a
    // reaction must not reappear over it a second later.
    _cancelReassurance();
    _setPose(pose);
  }

  void _setPose(MascotPose pose) {
    if (_pose == pose) return;
    _pose = pose;
    notifyListeners();
  }

  /// Hold [pose] briefly, then return to idle.
  ///
  /// The expressive stills (`encourage`, `listen`, `think`) are single frames,
  /// so playing them as a gesture would flash past in a third of a second.
  /// Holding the pose is what makes them read.
  void flash(MascotPose pose,
      {Duration duration = const Duration(milliseconds: 2200)}) {
    rest(pose);
    _revert = Timer(duration, () => rest(MascotPose.idle));
  }

  Timer? _revert;

  /// Beats of a [reassure]: `_recover` hands the sad gesture over to the
  /// encouraging pose, `_settle` marks the sequence finished.
  Timer? _recover;
  Timer? _settle;

  void _cancelReassurance() {
    _recover?.cancel();
    _settle?.cancel();
    _reassuring = false;
  }

  @override
  void dispose() {
    _revert?.cancel();
    _cancelReassurance();
    super.dispose();
  }
}

/// Places one mascot over [child] and exposes a [MascotController] to
/// everything beneath it.
///
/// Mounting this once per flow means a screen never has to find room in its
/// own layout for the character, and the mascot survives navigation between
/// the screens inside that flow instead of reloading its sheets each time.
class MascotHost extends StatefulWidget {
  const MascotHost({
    super.key,
    required this.child,
    this.controller,
    this.character = MascotCharacter.bps,
    this.height = 92,
    this.alignment = Alignment.bottomLeft,
    this.padding = const EdgeInsets.all(12),
    this.entrance = MascotEntrance.fromLeft,
    this.greetOnAppear = true,
    this.semanticLabel,
  });

  final Widget child;

  /// Own the controller yourself when the code that drives the mascot sits
  /// *above* this host (a parent's callback can't reach it via [maybeOf],
  /// since the host is created in that parent's own `build`). Leave null and
  /// the host creates and disposes one for you.
  final MascotController? controller;

  final MascotCharacter character;
  final double height;

  /// Where the mascot sits over [child].
  final Alignment alignment;
  final EdgeInsets padding;

  /// How the mascot arrives the first time this host is mounted.
  final MascotEntrance entrance;
  final bool greetOnAppear;
  final String? semanticLabel;

  /// The controller for the nearest host, or null if there is none.
  static MascotController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_MascotScope>()
      ?.notifier;

  /// The controller for the nearest host. Throws if there is no host.
  static MascotController of(BuildContext context) {
    final c = maybeOf(context);
    assert(c != null, 'No MascotHost above this widget.');
    return c!;
  }

  @override
  State<MascotHost> createState() => _MascotHostState();
}

class _MascotHostState extends State<MascotHost> {
  MascotController? _owned;

  MascotController get _controller =>
      widget.controller ?? (_owned ??= MascotController());

  @override
  void dispose() {
    _owned?.dispose(); // only dispose what this host created
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _MascotScope(
      notifier: _controller,
      child: Stack(
        children: [
          widget.child,
          // IgnorePointer: the mascot is company, never a tap target that
          // could steal a touch from the game underneath.
          Positioned.fill(
            child: IgnorePointer(
              child: Padding(
                padding: widget.padding,
                child: Align(
                  alignment: widget.alignment,
                  child: ListenableBuilder(
                    listenable: _controller,
                    builder: (context, _) => Mascot(
                      character: widget.character,
                      height: widget.height,
                      pose: _controller.pose,
                      gesture: _controller.gesture,
                      gestureTrigger: _controller.tick,
                      entrance: widget.entrance,
                      greetOnAppear: widget.greetOnAppear,
                      semanticLabel: widget.semanticLabel,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MascotScope extends InheritedNotifier<MascotController> {
  const _MascotScope({required super.notifier, required super.child});
}
