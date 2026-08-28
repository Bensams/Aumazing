import 'dart:async';

import 'package:flutter/foundation.dart';
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

  /// What the character is watching, as a fraction of the screen — (0,0) is
  /// the top-left corner, (1,1) the bottom-right — or null when it is watching
  /// nothing.
  ///
  /// Deliberately a separate notifier from the controller's own
  /// [notifyListeners]: this changes on every frame of a drag, and routing it
  /// through the main channel would rebuild the pose and gesture plumbing at
  /// 60 fps to move one pair of eyes.
  ValueListenable<Offset?> get gaze => _gaze;
  final ValueNotifier<Offset?> _gaze = ValueNotifier<Offset?>(null);

  /// Track a point on the screen, or stop tracking at null.
  ///
  /// Smoothed rather than followed exactly. A child's drag is jerky, and eyes
  /// that copied it frame for frame would twitch — the opposite of the calm
  /// attention this is meant to convey. The lag also reads as the character
  /// *following* the object rather than being welded to it, and it keeps the
  /// gaze from flickering between two poses when a finger hovers on the line
  /// between them.
  void watch(Offset? at) {
    if (at == null) {
      _gaze.value = null;
      return;
    }
    final target = Offset(at.dx.clamp(0.0, 1.0), at.dy.clamp(0.0, 1.0));
    final current = _gaze.value;
    _gaze.value = current == null
        ? target
        : current + (target - current) * _gazeGain;
  }

  /// Per-frame catch-up fraction. At 60 fps this closes most of a
  /// screen-width swing in about a fifth of a second: visibly a follow, not a
  /// lag the child would notice waiting for.
  static const double _gazeGain = 0.18;

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
    _gaze.dispose();
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
    this.character,
    this.costumeId,
    this.height = 92,
    this.alignment = Alignment.bottomLeft,
    this.padding = const EdgeInsets.all(12),
    this.entrance = MascotEntrance.fromLeft,
    this.greetOnAppear = true,
    this.semanticLabel,
    this.showMascot = true,
  });

  final Widget child;

  /// Whether the visible mascot is painted over [child]. False for a game that
  /// draws its own character (see [kGamesWithOwnCharacter]): the scope and
  /// controller stay in place so a screen's reaction calls remain valid, but no
  /// second character appears in the corner.
  final bool showMascot;

  /// Own the controller yourself when the code that drives the mascot sits
  /// *above* this host (a parent's callback can't reach it via [maybeOf],
  /// since the host is created in that parent's own `build`). Leave null and
  /// the host creates and disposes one for you.
  final MascotController? controller;

  /// Which character to show. Null — the usual case — follows the child's
  /// own choice from their profile, so a game screen never has to know or
  /// pass it. An explicit value is for the rare screen that must show a
  /// specific character regardless (the buddy in Sabay Tayo).
  final MascotCharacter? character;

  /// The equipped costume, as a [Costume.id]. Null follows the profile too.
  final String? costumeId;
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
    // Watched, not read: equipping a costume must change the mascot without
    // needing the screen to be rebuilt from above. Null where no ChildProvider
    // is mounted above this host — see [mascotProfileOf].
    final profile = mascotProfileOf(context);
    // A game that draws its own character keeps the controller (so its reaction
    // calls stay valid) but hides the corner mascot, so the child sees one
    // character, not two.
    if (!widget.showMascot) {
      return _MascotScope(notifier: _controller, child: widget.child);
    }
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
                    // Gaze is rebuilt on its own inner builder so a drag moves
                    // the head without re-running the pose/gesture plumbing.
                    builder: (context, _) => ValueListenableBuilder<Offset?>(
                      valueListenable: _controller.gaze,
                      builder: (context, gaze, _) => Mascot(
                        // Falls back to the child's own choice when the host
                        // was not given one, which is nearly always.
                        character: widget.character ??
                            MascotCharacter.fromId(profile?.characterId),
                        costumeId: widget.costumeId ?? profile?.equippedCostume,
                        height: widget.height,
                        pose: _controller.pose,
                        gesture: _controller.gesture,
                        gestureTrigger: _controller.tick,
                        gaze: gaze,
                        entrance: widget.entrance,
                        greetOnAppear: widget.greetOnAppear,
                        semanticLabel: widget.semanticLabel,
                      ),
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

/// Game ids whose Flame scene already draws its own on-screen character (the
/// buddy who points, greets, takes turns or needs help). For these the corner
/// mascot is suppressed via `MascotHost.showMascot: false`, so a child is never
/// asked to read "where is he looking?" with two characters in the room.
///
/// The mascot *controller* still lives — reaction calls
/// (`MascotHost.maybeOf(context)?.reassure()` etc.) stay valid no-ops — only
/// the visible character is withheld. The in-game buddy carries the feedback.
///
/// `anong_nararamdaman` draws the child's own character as the emotion face
/// (see the game's per-character face art), so the corner mascot steps aside
/// there too — the feeling on screen belongs to the one character on screen.
const Set<String> kGamesWithOwnCharacter = {
  'sabay_tayo',
  'kumusta',
  'my_turn_your_turn',
  'tulong_kaibigan',
  'anong_nararamdaman',
};
