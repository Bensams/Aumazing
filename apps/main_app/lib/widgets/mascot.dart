import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// shared_ui exports its own AnimatedBuilder, which would shadow Flutter's.
import 'package:shared_ui/shared_ui.dart' hide AnimatedBuilder;

import '../providers/child_provider.dart';

/// Which character is on screen.
enum MascotCharacter {
  bps,
  reiz;

  Future<CharacterSprites> load() => switch (this) {
        MascotCharacter.bps => CharacterSprites.bps(),
        MascotCharacter.reiz => CharacterSprites.reiz(),
      };
}

/// The pose the mascot *rests* on between gestures. Each maps to a
/// single-frame sheet; [idle] uses the idle sheet's rest frame.
enum MascotPose { idle, encourage, listen, sleepy, think }

/// A short animation played once on demand, after which the mascot returns
/// to its [MascotPose].
enum MascotGesture {
  wave,
  celebrate,
  nod,
  point,

  /// A soft "oh — not quite" after a wrong answer: shoulders dip, the smile
  /// softens, and the character looks down for a moment.
  ///
  /// Deliberately *disappointment*, not distress and never anger. A crying
  /// mascot models distress at a child who has just made a mistake, which is
  /// the one reaction this app must not have (see CALM_MASCOT.md). Never play
  /// this on its own either — [MascotController.reassure] is the only
  /// intended caller, because it guarantees the character recovers into an
  /// encouraging pose instead of being left sad.
  oops;

  /// How many times the frame cycle repeats before the mascot rests.
  ///
  /// A celebration plays under the reward overlay, which runs for ~10 s — at
  /// 12 frames and 6 fps the default two loops end after four seconds, long
  /// before the child looks away from the confetti, so it reads as "the
  /// character did nothing". Everything else stays brief: a nod acknowledges
  /// one answer and must not turn into a performance, and an `oops` plays
  /// exactly once — repeating it would dwell on the mistake.
  int get loops => switch (this) {
        MascotGesture.celebrate => 5,
        MascotGesture.oops => 1,
        _ => 2,
      };

  /// Roughly how long this gesture takes to play, from its sheet's frame count
  /// at CalmMascot's default rate. Lets a caller sequence what comes *after*
  /// the gesture without hard-coding a duration that silently drifts out of
  /// step when a sheet is re-cut.
  Duration get duration {
    final frames = CharacterSprites.layout[name]?.frames ?? 6;
    return Duration(milliseconds: (frames * loops * 1000 / _gestureFps).round());
  }
}

/// CalmMascot's default gesture rate; it clamps anything passed to 3–8 fps.
const double _gestureFps = 6;

/// A mascot with the app-side plumbing every appearance needs: loads the
/// character's sprite sheets (cached process-wide after the first load),
/// honours the child's reduced-motion setting, and can make an entrance.
///
/// Two separate ideas, matching how the sheets are authored:
///  * [pose] is what the character *is* — the still it rests on.
///  * [gesture] is what it *does* — a frame sequence played when
///    [gestureTrigger] changes, after which it returns to [pose].
///
/// Between the two it blinks on its own (see [blink]), so resting is not the
/// same as being frozen.
///
/// While the sheets decode it shows [fallback] (or reserves the space) so
/// layout never jumps.
class Mascot extends StatefulWidget {
  const Mascot({
    super.key,
    this.character = MascotCharacter.bps,
    this.height = 140,
    this.pose = MascotPose.idle,
    this.gesture = MascotGesture.wave,
    this.gestureTrigger,
    this.gaze,
    this.entrance = MascotEntrance.none,
    this.greetOnAppear = true,
    this.greetDelay = const Duration(milliseconds: 500),
    this.blink = true,
    this.fallback,
    this.semanticLabel,
  });

  final MascotCharacter character;

  /// Display height in logical pixels. Keep consistent across appearances —
  /// predictable size reads as calm.
  final double height;

  /// The resting pose.
  final MascotPose pose;

  /// Which gesture [gestureTrigger] plays.
  final MascotGesture gesture;

  /// Change this value to play [gesture] once.
  final Object? gestureTrigger;

  /// What the character is watching, as a fraction of the screen — (0,0) is
  /// the top-left corner, (1,1) the bottom-right. Null — the default — means
  /// it isn't watching anything and rests on [pose] as usual.
  ///
  /// Wired to a game's drag position, this makes the character follow the
  /// object in the child's hand, which is the point: it turns a mechanical
  /// drag into something the character is paying attention to.
  ///
  /// Ignored under reduced motion. A character whose gaze poses haven't been
  /// generated still leans toward the point, so the follow degrades rather
  /// than disappearing.
  final Offset? gaze;

  /// How the mascot arrives on first appearance.
  final MascotEntrance entrance;

  /// Whether the mascot greets with [gesture] shortly after appearing (or,
  /// with an entrance, once it has arrived).
  final bool greetOnAppear;

  /// Delay before the greeting — lets an entrance transition settle first.
  final Duration greetDelay;

  /// Whether the character blinks on its own between gestures.
  ///
  /// On by default: a rest pose that never changes reads as a photograph
  /// propped up beside the game rather than someone keeping the child
  /// company. Turn it off only where the blink would be noise — a test
  /// measuring gesture frames, say.
  final bool blink;

  /// Shown while sprite sheets load. Defaults to an empty box of the same
  /// height so layout stays stable.
  final Widget? fallback;

  final String? semanticLabel;

  @override
  State<Mascot> createState() => _MascotState();
}

/// How a mascot arrives on screen.
enum MascotEntrance {
  /// Appear in place.
  none,

  /// Travel in from off-screen left, then greet.
  fromLeft,

  /// Travel in from off-screen right, then greet.
  fromRight,
}

class _MascotState extends State<Mascot> with TickerProviderStateMixin {
  CharacterSprites? _sprites;
  late final AnimationController _travel;

  /// The gentle sink that accompanies [MascotGesture.oops].
  late final AnimationController _droop;

  /// How far the mascot sinks during an `oops`, as a fraction of its height.
  /// Small enough to read as a sigh rather than a fall — the character must
  /// still look like it is standing where it was.
  static const double _droopDepth = 0.04;

  /// Internal greet counter, combined with [Mascot.gestureTrigger].
  int _greetTick = 0;

  /// Walk-cycle playback, live only while travelling on.
  Timer? _stepTimer;
  int _stepFrame = 0;
  bool _walking = false;

  /// Held to the top of CalmMascot's 3–8 fps envelope: the walk is brief and
  /// legible, and must not become the one place motion gets busier.
  static const double _walkFps = 8;

  /// Idle blink: `_blinkNext` waits out the gap, `_blinkHold` marks the end of
  /// the cycle. [_blinking] swaps the idle sheet in as the gesture frames.
  Timer? _blinkNext;
  Timer? _blinkHold;
  int _blinkTick = 0;
  bool _blinking = false;

  /// When the gesture currently on screen finishes. A blink defers past it
  /// rather than queueing behind it — a blink that has waited is worth
  /// nothing, so it is always cheaper to skip one than to risk cutting into
  /// what the controller asked for.
  DateTime _busyUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// Gap between blinks, sampled fresh each time. A blink is involuntary and
  /// irregular; on a fixed period it reads as a metronome, which is exactly
  /// the predictable-but-mechanical motion that makes a character feel like a
  /// looping asset instead of company.
  static const Duration _blinkMinGap = Duration(seconds: 4);
  static const Duration _blinkMaxGap = Duration(seconds: 7);

  final Random _rng = Random();

  bool get _reducedMotion {
    try {
      return context.read<ChildProvider>().reducedMotion;
    } catch (_) {
      return false; // ChildProvider may be absent (e.g. isolated tests).
    }
  }

  @override
  void initState() {
    super.initState();
    _travel = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _droop = AnimationController(
      vsync: this,
      duration: MascotGesture.oops.duration,
    );
    widget.character.load().then((s) {
      if (!mounted) return;
      setState(() => _sprites = s);
      _begin();
    }).catchError((Object e, StackTrace st) {
      // A missing or mis-cut sheet used to fail silently and simply leave the
      // mascot absent, which is invisible until someone notices the character
      // never shows up. Surface it instead.
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'mascot',
        context: ErrorDescription(
            'loading sprite sheets for ${widget.character.name}'),
      ));
    });
  }

  /// Walk on (if asked), then greet. Under reduced motion the mascot is
  /// simply already there — travel is vestibular motion, so it is skipped
  /// entirely rather than shortened.
  void _begin() {
    final travels =
        widget.entrance != MascotEntrance.none && !_reducedMotion;
    if (!travels) {
      _travel.value = 1;
      _scheduleGreet(widget.greetDelay);
    } else {
      _startStepping();
      _travel.forward().whenComplete(() {
        if (!mounted) return;
        _stopStepping();
        _scheduleGreet(widget.greetDelay);
      });
    }
    _scheduleBlink();
  }

  /// Cycles the walk sheet while the mascot travels. Falls back silently to
  /// the settle-bob if the character has no walk sheet.
  void _startStepping() {
    if ((_sprites?.frames('walk') ?? const []).isEmpty) return;
    _walking = true;
    _stepTimer = Timer.periodic(
      Duration(milliseconds: (1000 / _walkFps).round()),
      (_) {
        if (mounted) setState(() => _stepFrame++);
      },
    );
  }

  void _stopStepping() {
    _stepTimer?.cancel();
    _stepTimer = null;
    if (_walking) setState(() => _walking = false);
  }

  void _scheduleGreet(Duration delay) {
    if (!widget.greetOnAppear) return;
    // Bump on a later frame than the first build with sprites, so CalmMascot
    // sees the trigger *change* and plays.
    Future.delayed(delay, () {
      if (!mounted) return;
      setState(() {
        _greetTick++;
        _markBusy(widget.gesture.duration);
      });
    });
  }

  /// Note that a gesture holds the screen for [d], so a blink stays out of
  /// its way.
  void _markBusy(Duration d) => _busyUntil = DateTime.now().add(d);

  /// Waits a randomised gap, then blinks.
  void _scheduleBlink() {
    _blinkNext?.cancel();
    if (!widget.blink) return;
    final spread = _blinkMaxGap.inMilliseconds - _blinkMinGap.inMilliseconds;
    _blinkNext = Timer(
      _blinkMinGap + Duration(milliseconds: _rng.nextInt(spread + 1)),
      _blink,
    );
  }

  /// Plays the idle sheet's blink cycle, if this is a moment for one.
  ///
  /// The idle sheet is cut as rest / half / closed / half / open, so the cycle
  /// begins and ends on the very pose already on screen — which is why it can
  /// be dropped in as a gesture without a cross-fade or a visible hand-off.
  void _blink() {
    final frames = _sprites?.frames('idle') ?? const <ImageProvider>[];
    // Every reason not to blink right now resolves the same way: skip this
    // one and wait out another gap. Silently doing nothing would stop the
    // blinking for the rest of the mascot's life the first time a celebration
    // happened to overlap the timer.
    final busy = DateTime.now().isBefore(_busyUntil);
    if (frames.length < 2 ||
        busy ||
        _walking ||
        _reducedMotion ||
        widget.pose != MascotPose.idle) {
      _scheduleBlink();
      return;
    }
    setState(() {
      _blinking = true;
      _blinkTick++;
    });
    _blinkHold = Timer(_blinkCycle(frames.length), () {
      if (mounted) setState(() => _blinking = false);
      _scheduleBlink();
    });
  }

  /// How long to leave the blink frames in place.
  ///
  /// One frame longer than CalmMascot needs to play them: it cancels its own
  /// frame timer a beat after this fires, and swapping the frame list out from
  /// under it mid-cycle would flash a single frame of the *other* action.
  static Duration _blinkCycle(int frames) =>
      Duration(milliseconds: ((frames + 1) * 1000 / _gestureFps).round());

  void _cancelBlink() {
    _blinkNext?.cancel();
    _blinkHold?.cancel();
    _blinkNext = null;
    _blinkHold = null;
    _blinking = false;
  }

  @override
  void didUpdateWidget(Mascot old) {
    super.didUpdateWidget(old);
    // The sink is the app's own motion, layered over whatever the sheet does,
    // so it runs off the same trigger CalmMascot plays the frames on. It is
    // also the whole of the reaction on a character whose `oops` sheet hasn't
    // been generated yet.
    final played = widget.gestureTrigger != null &&
        widget.gestureTrigger != old.gestureTrigger;
    if (played && widget.gesture == MascotGesture.oops && !_reducedMotion) {
      _droop.forward(from: 0);
    }
    if (played) {
      // The controller wins outright. Dropping a blink already in flight is
      // safe because it lasts under a second and starts and ends on the rest
      // pose — the frames the gesture is about to replace anyway.
      _markBusy(widget.gesture.duration);
      _cancelBlink();
      _scheduleBlink();
    } else if (widget.blink != old.blink) {
      _cancelBlink();
      _scheduleBlink();
    }
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    _cancelBlink();
    _droop.dispose();
    _travel.dispose();
    super.dispose();
  }

  /// 0 → 1 → 0 across the gesture: ease down, hold at the bottom, ease back.
  ///
  /// The hold is what makes the beat legible; a symmetric dip reads as a bounce
  /// and bouncing is the opposite of the message.
  static double _sink(double t) {
    const down = 0.30, up = 0.70;
    if (t < down) return Curves.easeInOut.transform(t / down);
    if (t < up) return 1;
    return 1 - Curves.easeInOut.transform((t - up) / (1 - up));
  }

  /// Tips [child] toward the point it is watching.
  ///
  /// Small on purpose. The whole envelope this widget sits in exists to keep
  /// the character from becoming the busiest thing on screen, and a mascot
  /// swinging about while a child is concentrating on dragging something is
  /// exactly that. At these amounts it reads, correctly, as attention rather
  /// than as an animation competing with the game.
  Widget _lean(Widget child, Offset gaze) {
    // −1 at the left/top edge of the screen, +1 at the right/bottom.
    final side = (gaze.dx.clamp(0.0, 1.0) - 0.5) * 2;
    final vertical = (gaze.dy.clamp(0.0, 1.0) - 0.5) * 2;
    return Transform(
      // Feet, not centre: the character tips over to see past something,
      // rather than rotating on the spot like a dial.
      alignment: Alignment.bottomCenter,
      transform: Matrix4.identity()
        ..translateByDouble(
          side * widget.height * _leanShift,
          // Down only. Rising to follow something high would lift the
          // character off the floor it is standing on; sinking to follow
          // something low reads as crouching to look, which is what a person
          // would actually do.
          vertical > 0 ? vertical * widget.height * _crouchShift : 0,
          0,
          1,
        )
        ..rotateZ(side * _leanRadians),
      child: child,
    );
  }

  /// Peak tilt at the edges of the screen, ~5°.
  static const double _leanRadians = 5 * pi / 180;

  /// Peak sideways shift, as a fraction of the mascot's height. Leaning alone
  /// is legible but reads as stiff; a little travel with it looks like the
  /// character shifting its weight to follow along.
  static const double _leanShift = 0.05;

  /// Peak downward shift when watching something near the bottom of the
  /// screen. Smaller than [_leanShift] — the mascot already sits low, and any
  /// more of a drop starts to read as sliding off the screen.
  static const double _crouchShift = 0.03;

  ImageProvider _restImage(CharacterSprites s) => widget.pose == MascotPose.idle
      ? s.rest
      : (s.still(widget.pose.name) ?? s.rest);

  @override
  Widget build(BuildContext context) {
    final sprites = _sprites;
    if (sprites == null) {
      return widget.fallback ?? SizedBox(height: widget.height);
    }

    final walkFrames = sprites.frames('walk');
    final stepping = _walking && walkFrames.isNotEmpty;

    // Tracking is a *lookup* into the gaze sheet, not playback, so — like the
    // walk cycle — it bypasses CalmMascot, which exists to play a sequence and
    // then rest. Walking still wins: a character crossing the screen has
    // somewhere to be, and its own sheet already says where it is looking.
    final gazing = (widget.gaze != null && !_reducedMotion && !stepping)
        ? sprites.gazeFrameFor(widget.gaze!.dx, widget.gaze!.dy)
        : null;

    // A blink borrows the gesture channel — CalmMascot plays one frame list at
    // a time — so it is expressed as "which action is playing", not as motion
    // layered on top. The pose check also covers a pose change arriving
    // mid-blink: the blink is from the idle sheet, and playing it over
    // `encourage` would look like the character dropped that pose and picked
    // it up again a second later.
    final blinkFrames = sprites.frames('idle');
    final blinking = _blinking &&
        blinkFrames.length > 1 &&
        widget.pose == MascotPose.idle;

    // Two cases drive the frame themselves instead of handing it to
    // CalmMascot, which by design plays a sequence and then rests: walking on
    // (the cycle must keep going until the character arrives) and tracking a
    // drag (the frame is chosen by where the finger is, not by elapsed time).
    final ImageProvider? directFrame =
        stepping ? walkFrames[_stepFrame % walkFrames.length] : gazing;

    final Widget mascot = directFrame != null
        ? Semantics(
            label: widget.semanticLabel,
            image: true,
            child: SizedBox(
              height: widget.height,
              child: Image(
                image: directFrame,
                height: widget.height,
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            ),
          )
        : CalmMascot(
            image: _restImage(sprites),
            height: widget.height,
            reducedMotion: _reducedMotion,
            gestureFrames:
                blinking ? blinkFrames : sprites.frames(widget.gesture.name),
            gestureLoops: blinking ? 1 : widget.gesture.loops,
            // Only ever *bumped* — the counters make each play distinct
            // without a change when `blinking` falls back to false, so
            // CalmMascot rests on the pose instead of replaying the gesture.
            gestureTrigger:
                '${widget.gestureTrigger}-$_greetTick-$_blinkTick',
            semanticLabel: widget.semanticLabel,
          );

    // Leaning toward what it is watching, layered UNDER the eyes.
    //
    // The two carry different halves of the effect and neither is enough
    // alone. The gaze poses are three points — hard left, straight ahead, hard
    // right — so by themselves the character would snap between them; the lean
    // is continuous and fills in everything in between. And a character whose
    // gaze poses haven't been generated yet still follows the drag with its
    // body rather than doing nothing.
    //
    // Pivoted at the feet so it reads as the character leaning over to see,
    // not as the picture being rotated.
    final Widget watching = (widget.gaze == null || _reducedMotion)
        ? mascot
        : _lean(mascot, widget.gaze!);

    // Sinking is a small translation of the whole character, so it is skipped
    // under reduced motion along with every other movement.
    final Widget body = _reducedMotion
        ? watching
        : AnimatedBuilder(
            animation: _droop,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, widget.height * _droopDepth * _sink(_droop.value)),
              child: child,
            ),
            child: watching,
          );

    if (widget.entrance == MascotEntrance.none || _reducedMotion) {
      return body;
    }

    final sign = widget.entrance == MascotEntrance.fromLeft ? -1.0 : 1.0;
    return AnimatedBuilder(
      animation: _travel,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_travel.value);
        // Travel is expressed in multiples of the mascot's own height, so the
        // entrance reads the same at any size.
        final dx = sign * (1 - t) * widget.height * 2.2;
        // The walk sheet carries its own bob, so only add one as a fallback
        // for a character that has no walk frames yet.
        final bob = (_travel.isAnimating && !stepping)
            ? -(widget.height * 0.02) *
                (1 - t) *
                (1 - 2 * ((_travel.value * 4) % 1.0 - 0.5).abs())
            : 0.0;
        return Transform.translate(offset: Offset(dx, bob), child: child);
      },
      child: body,
    );
  }
}
