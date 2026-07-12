import 'dart:async';

import 'package:flutter/material.dart';

/// An ASD-safe animated mascot.
///
/// This widget *enforces* a calm-motion envelope so a character can't
/// overstimulate a young viewer no matter how it's used:
///
/// - **Breathing idle** — a single still gently scales 1.0 ↔ [breatheScale]
///   over [breathePeriod] with an ease-in-out curve. One image, feels
///   alive, never jitters.
/// - **Cross-fades, not frame-flips** — changing [image] fades between
///   poses over [crossFadeDuration]; no hard cuts, bounces, or spins.
/// - **Optional gentle gesture** — a short [gestureFrames] loop plays at a
///   rate clamped to 3–8 fps for a few loops, then rests on [image]. This
///   caps the "busy-ness" of any waving/nodding animation.
/// - **Reduced-motion aware** — when [reducedMotion] is true, ALL motion
///   stops: the mascot is a static pose (breathing off, gestures skipped).
///   Pose changes still fade (opacity is not vestibular motion).
///
/// The character animates on demand and then rests; it is never a
/// perpetually-moving distraction.
class CalmMascot extends StatefulWidget {
  const CalmMascot({
    super.key,
    required this.image,
    this.height = 240,
    this.reducedMotion = false,
    this.breathe = true,
    this.breathePeriod = const Duration(milliseconds: 2600),
    this.breatheScale = 1.03,
    this.crossFadeDuration = const Duration(milliseconds: 300),
    this.gestureFrames,
    this.gestureTrigger,
    this.gestureFps = 6,
    this.gestureLoops = 2,
    this.semanticLabel,
  });

  /// The resting pose. Changing it cross-fades to the new pose.
  final ImageProvider image;

  /// Display height in logical pixels (width scales to fit). Keep this
  /// consistent across appearances — predictable size reads as calm.
  final double height;

  /// When true, all motion is disabled (static pose). Wire this to the
  /// child's reduced-motion / animation-intensity setting.
  final bool reducedMotion;

  /// Whether the gentle breathing idle plays (ignored under reduced motion).
  final bool breathe;

  /// One full breathing cycle. 2–3 s reads as calm; shorter feels anxious.
  final Duration breathePeriod;

  /// Peak breathing scale. Kept small (≤ ~1.05) so the motion is subtle;
  /// values are clamped to [1.0, 1.06].
  final double breatheScale;

  /// Fade duration when [image] changes.
  final Duration crossFadeDuration;

  /// Optional short frame sequence for a gentle gesture (e.g. a wave).
  /// Frames should be the same character at the same size/anchor.
  final List<ImageProvider>? gestureFrames;

  /// Change this value (e.g. increment an int) to play the gesture once.
  final Object? gestureTrigger;

  /// Gesture playback rate, clamped to 3–8 fps (slow, legible motion).
  final double gestureFps;

  /// How many times the gesture loops before resting.
  final int gestureLoops;

  final String? semanticLabel;

  @override
  State<CalmMascot> createState() => _CalmMascotState();
}

class _CalmMascotState extends State<CalmMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath;
  Timer? _gestureTimer;
  int _gestureFrameIndex = -1; // -1 = not playing a gesture

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: widget.breathePeriod,
    );
    _syncBreathing();
  }

  @override
  void didUpdateWidget(CalmMascot old) {
    super.didUpdateWidget(old);
    if (old.reducedMotion != widget.reducedMotion ||
        old.breathe != widget.breathe ||
        old.breathePeriod != widget.breathePeriod) {
      _breath.duration = widget.breathePeriod;
      _syncBreathing();
    }
    // A changed trigger starts the gesture (unless motion is reduced).
    if (widget.gestureTrigger != null &&
        widget.gestureTrigger != old.gestureTrigger) {
      _playGesture();
    }
  }

  void _syncBreathing() {
    final shouldBreathe = widget.breathe && !widget.reducedMotion;
    if (shouldBreathe) {
      if (!_breath.isAnimating) _breath.repeat(reverse: true);
    } else {
      _breath.stop();
      _breath.value = 0;
    }
  }

  void _playGesture() {
    final frames = widget.gestureFrames;
    if (frames == null || frames.isEmpty || widget.reducedMotion) return;

    _gestureTimer?.cancel();
    // Clamp the rate so a gesture can never be a fast, busy flip.
    final fps = widget.gestureFps.clamp(3.0, 8.0);
    final totalFrames = frames.length * widget.gestureLoops;
    var step = 0;
    setState(() => _gestureFrameIndex = 0);

    _gestureTimer = Timer.periodic(
      Duration(milliseconds: (1000 / fps).round()),
      (timer) {
        step++;
        if (step >= totalFrames) {
          timer.cancel();
          if (mounted) setState(() => _gestureFrameIndex = -1); // rest
          return;
        }
        if (mounted) {
          setState(() => _gestureFrameIndex = step % frames.length);
        }
      },
    );
  }

  @override
  void dispose() {
    _gestureTimer?.cancel();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frames = widget.gestureFrames;
    final playingGesture =
        _gestureFrameIndex >= 0 && frames != null && frames.isNotEmpty;

    // During a gesture, show the current frame (no cross-fade — the frames
    // themselves are the motion). Under reduced motion, swap poses instantly
    // (zero animation). Otherwise use a gentle cross-fade on change.
    final Widget picture;
    if (playingGesture) {
      picture = Image(
        image: frames[_gestureFrameIndex],
        height: widget.height,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    } else if (widget.reducedMotion) {
      picture = Image(
        image: widget.image,
        height: widget.height,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    } else {
      picture = AnimatedSwitcher(
        duration: widget.crossFadeDuration,
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        child: Image(
          key: ValueKey<ImageProvider>(widget.image),
          image: widget.image,
          height: widget.height,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
      );
    }

    final scaleCap = widget.breatheScale.clamp(1.0, 1.06);
    final content =
        (widget.breathe && !widget.reducedMotion && !playingGesture)
            ? AnimatedBuilder(
                animation: _breath,
                builder: (context, child) {
                  final t =
                      Curves.easeInOut.transform(_breath.value);
                  return Transform.scale(
                    scale: 1.0 + (scaleCap - 1.0) * t,
                    child: child,
                  );
                },
                child: picture,
              )
            : picture;

    return Semantics(
      label: widget.semanticLabel,
      image: true,
      child: SizedBox(height: widget.height, child: content),
    );
  }
}
