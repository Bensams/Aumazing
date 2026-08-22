import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import 'package:game_core/game_core.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../services/learning_path_service.dart';

/// Where a step sits in the child's progression. Each state is coded by
/// *shape* (badge outline) as well as color, so the distinction survives
/// color-blindness and the muting applied to locked steps.
enum PathStepState {
  /// Finished. Still replayable.
  done,

  /// The step to play next — the one the guiding hand points at.
  current,

  /// Unlocked but not next (completed out of order from the "All" view).
  available,

  /// Sequentially locked: an earlier step is unfinished.
  locked,
}

/// "My Path" drawn as a level map: each step is a platform floating over the
/// world's scene, joined by a dotted trail that fills in behind the child.
///
/// The map replaces the old card row because a row of equal cards carries no
/// sense of direction, and My Path is the child's *visual schedule* — done,
/// now, next. A trail that visibly runs out at the current step communicates
/// "how much is left" without any reading.
///
/// The scene itself is not drawn here; the lobby paints [WorldBackdrop] behind
/// its whole body so the header sits on the same sky.
class PathMapView extends StatefulWidget {
  const PathMapView({
    super.key,
    required this.path,
    required this.completedGameIds,
    this.starsEarnedTodayGameIds = const {},
    required this.difficultyOverride,
    required this.style,
    required this.currentStepKey,
    required this.onLaunch,
    this.reducedMotion = false,
  });

  final List<LearningPathEntry> path;

  final Set<String> completedGameIds;

  /// Games that have already paid their star today (AUM-284/285).
  ///
  /// Separate from [completedGameIds], which means "finished as a path step"
  /// and never resets. This one is about today only, and a game can easily be
  /// in one and not the other: a step finished last week has long since paid,
  /// and its star is waiting again.
  final Set<String> starsEarnedTodayGameIds;

  /// Parent's manual difficulty override; wins over the path's own level.
  final int? difficultyOverride;

  final WorldStyle style;

  /// Anchors the lobby's guiding hand to the current step.
  final GlobalKey currentStepKey;

  final void Function(String gameId, int difficulty) onLaunch;

  /// Reduced-motion opt-out: the spaceship snaps to its new step instead of
  /// flying, and does not idle-bob.
  final bool reducedMotion;

  /// Horizontal distance between one platform's centre and the next.
  static const _stepSpacing = 172.0;

  /// How far a platform rises or falls from the mid-line. Alternating gives
  /// the trail its up-and-down travel without needing a second scroll axis.
  static const _amplitude = 34.0;

  static const _platformWidth = 132.0;

  /// Leading and trailing breathing room inside the scroll.
  static const _edgeInset = AppSpacing.lg;

  @override
  State<PathMapView> createState() => _PathMapViewState();
}

class _PathMapViewState extends State<PathMapView>
    with TickerProviderStateMixin {
  /// The flight from one step's dock to the next. Idle at 0 (docked at the
  /// source) or 1 (docked at the destination); animates 0→1 on a completion.
  late final AnimationController _flight;

  /// A gentle idle bob so the docked ship reads as hovering, not stuck on.
  late final AnimationController _bob;

  /// The step the ship is docked at (or flying towards).
  late int _shownIndex;

  /// Where the current flight started; null when the ship has never moved.
  int? _fromIndex;

  /// The spaceship is a space-world motif — it rides the path only in a world
  /// that dresses the scene for it (Night Sky). Classic keeps the bare map.
  bool get _showShip => widget.style.hasBackdrop;

  @override
  void initState() {
    super.initState();
    _shownIndex = _currentIndex;
    _flight = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _bob = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (!widget.reducedMotion && _showShip) _bob.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(PathMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A completion (or a switch to a longer/shorter path) moved the "play next"
    // step. Fly the ship there. The controller ticks only while this route is
    // on screen — when the child finishes a game the lobby is covered, so the
    // flight is queued and plays the moment they come back to the path, which
    // is exactly when they can see it.
    final target = _currentIndex;
    if (target == _shownIndex) return;
    if (widget.reducedMotion || !_showShip) {
      setState(() => _shownIndex = target);
      return;
    }
    setState(() {
      _fromIndex = _shownIndex;
      _shownIndex = target;
    });
    _flight.forward(from: 0);
  }

  @override
  void dispose() {
    _flight.dispose();
    _bob.dispose();
    super.dispose();
  }

  /// The first step the child has not finished — the one to play next.
  int get _currentIndex {
    final i = widget.path
        .indexWhere((e) => !widget.completedGameIds.contains(e.game.id));
    return i < 0 ? 0 : i;
  }

  PathStepState _stateFor(int index) {
    final entry = widget.path[index];
    if (widget.completedGameIds.contains(entry.game.id)) {
      return PathStepState.done;
    }
    if (!LearningPathService.isUnlocked(
        widget.path, index, widget.completedGameIds)) {
      return PathStepState.locked;
    }
    return index == _currentIndex
        ? PathStepState.current
        : PathStepState.available;
  }

  /// Centre of the platform for [index] within the scroll content.
  Offset _anchor(int index, double height) {
    final x = PathMapView._edgeInset +
        PathMapView._platformWidth / 2 +
        index * PathMapView._stepSpacing;
    // Even steps ride high, odd steps dip — a simple alternation reads as a
    // journey without the trail ever doubling back on itself.
    final y =
        height * 0.5 + (index.isEven ? -PathMapView._amplitude : PathMapView._amplitude);
    return Offset(x, y);
  }

  /// Where the ship hovers for a step: just off the platform's bottom-right
  /// corner, so it reads as parked on that card without a landing pad drawn.
  Offset _dock(Offset anchor) => Offset(
        anchor.dx + PathMapView._platformWidth / 2 - 6,
        anchor.dy + _PathStep.height / 2 - 40,
      );

  @override
  Widget build(BuildContext context) {
    final path = widget.path;
    final contentWidth = PathMapView._edgeInset * 2 +
        PathMapView._platformWidth +
        (path.length - 1) * PathMapView._stepSpacing;

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final anchors = [
          for (var i = 0; i < path.length; i++) _anchor(i, height),
        ];
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: contentWidth,
            height: height,
            child: Stack(
              // The ship rises above its dock on the flight arc; don't clip it.
              clipBehavior: Clip.none,
              children: [
                // The trail sits under the platforms so it appears to run
                // behind them rather than across their faces.
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TrailPainter(
                      anchors: anchors,
                      travelled: [
                        for (final entry in path)
                          widget.completedGameIds.contains(entry.game.id),
                      ],
                      style: widget.style,
                    ),
                  ),
                ),
                for (var i = 0; i < path.length; i++)
                  Positioned(
                    left: anchors[i].dx - PathMapView._platformWidth / 2,
                    // The platform's own column is taller than the anchor
                    // point; centre it vertically on the anchor.
                    top: anchors[i].dy - _PathStep.height / 2,
                    child: _wrapCurrent(
                      i,
                      _PathStep(
                        entry: path[i].game,
                        stepNumber: i + 1,
                        state: _stateFor(i),
                        starEarnedToday: widget.starsEarnedTodayGameIds.contains(
                          path[i].game.id,
                        ),
                        difficulty:
                            (widget.difficultyOverride ?? path[i].difficulty)
                                .clamp(1, 3),
                        style: widget.style,
                        onTap: _onTapFor(i),
                      ),
                    ),
                  ),
                // The travelling marker rides above every platform.
                if (_showShip) _buildShip(anchors),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The spaceship, docked on the current step and flying to the next when the
  /// path advances.
  Widget _buildShip(List<Offset> anchors) {
    if (anchors.isEmpty) return const SizedBox.shrink();
    const shipSize = 58.0;
    // Guard the indices: a path can shrink between builds.
    final toIdx = _shownIndex.clamp(0, anchors.length - 1);
    final fromIdx = (_fromIndex ?? _shownIndex).clamp(0, anchors.length - 1);

    return ListenableBuilder(
      listenable: Listenable.merge([_flight, _bob]),
      builder: (context, _) {
        final flying = _flight.isAnimating;
        final e = Curves.easeInOut.transform(_flight.value);

        final from = _dock(anchors[fromIdx]);
        final to = _dock(anchors[toIdx]);
        var pos = Offset.lerp(from, to, e)!;

        // A single sine hump: the ship lifts off the card, arcs over the trail,
        // and settles onto the next — no doubling back, nothing to overshoot.
        final arc = math.sin(e * math.pi);
        pos = pos.translate(0, -arc * 40);

        // Bank the nose along the direction of travel at the peak of the arc,
        // returning upright as it docks. Idle, it sits level.
        final delta = to - from;
        final travelAngle =
            delta.distance < 1 ? 0.0 : math.atan2(delta.dy, delta.dx);
        final angle = travelAngle * arc;

        // Grows a touch mid-flight (coming closer), plus a small idle bob so a
        // parked ship still breathes.
        final scale = 1 + 0.16 * arc;
        final bob = (!flying && !widget.reducedMotion)
            ? math.sin(_bob.value * math.pi * 2) * 3
            : 0.0;

        return Positioned(
          left: pos.dx - shipSize / 2,
          top: pos.dy - shipSize / 2 + bob,
          child: IgnorePointer(
            child: Transform.rotate(
              angle: angle,
              child: Transform.scale(
                scale: scale,
                child: Spaceship(
                  size: shipSize,
                  accent: widget.style.currentRing,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The guiding hand anchors on the current step, so only that one is keyed.
  Widget _wrapCurrent(int index, Widget child) => index == _currentIndex
      ? KeyedSubtree(key: widget.currentStepKey, child: child)
      : child;

  VoidCallback? _onTapFor(int index) {
    if (_stateFor(index) == PathStepState.locked) return null;
    final difficulty =
        (widget.difficultyOverride ?? widget.path[index].difficulty)
            .clamp(1, 3);
    return () => widget.onLaunch(widget.path[index].game.id, difficulty);
  }
}

/// "Today's star is already got" on a path step (AUM-286).
///
/// The same star-and-tick as the lobby card's badge, sized for the smaller
/// platform. Nothing else changes: the step keeps its colour and its tap,
/// because the game is still playable and a child on the path should still
/// be able to walk it. A dimmed step would read as a lock, and this map
/// already has a real one of those.
class _StarEarnedMarker extends StatelessWidget {
  const _StarEarnedMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.white.withAlpha(235),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 4),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('⭐', style: TextStyle(fontSize: 11)),
          SizedBox(width: 2),
          Icon(Icons.check_rounded, size: 11, color: Color(0xFF6FAE97)),
        ],
      ),
    );
  }
}

/// The dotted trail joining consecutive platforms.
///
/// Segments behind the child are drawn in the world's "travelled" colour and
/// slightly larger; segments ahead are dimmer and smaller. The change of
/// weight, not just colour, is what makes the boundary legible at a glance.
class _TrailPainter extends CustomPainter {
  const _TrailPainter({
    required this.anchors,
    required this.travelled,
    required this.style,
  });

  final List<Offset> anchors;

  /// Per-step completion; segment `i` is travelled when step `i` is done.
  final List<bool> travelled;

  final WorldStyle style;

  /// Gap between dot centres along a segment.
  static const _dotSpacing = 17.0;

  /// The trail leaves each platform's edge rather than its centre.
  static const _clearance = 62.0;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < anchors.length - 1; i++) {
      final isTravelled = travelled[i];
      final paint = Paint()
        ..color = isTravelled ? style.trailTravelled : style.trailAhead;
      final from = anchors[i];
      final to = anchors[i + 1];
      final delta = to - from;
      final distance = delta.distance;
      if (distance <= _clearance * 2) continue;

      // Walk the segment, skipping the stretch covered by each platform.
      final direction = delta / distance;
      final start = from + direction * _clearance;
      final usable = distance - _clearance * 2;
      final count = (usable / _dotSpacing).floor();
      if (count <= 0) continue;
      // Distribute the remainder so the dots stay centred between platforms.
      final lead = (usable - count * _dotSpacing) / 2;

      for (var d = 0; d <= count; d++) {
        final centre = start + direction * (lead + d * _dotSpacing);
        canvas.drawCircle(centre, isTravelled ? 3.4 : 2.6, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_TrailPainter oldDelegate) =>
      oldDelegate.style != style ||
      !listEquals(oldDelegate.travelled, travelled) ||
      !listEquals(oldDelegate.anchors, anchors);
}

/// One step of the path: a floating platform carrying the game's own colour
/// and icon, a state badge, and the game's name below.
///
/// The platform is themed but its face is **not** — the face keeps
/// `GameEntry.gradientColors`, which is the child's learned cue for which game
/// this is. A world that repainted every step the same colour would take that
/// cue away.
class _PathStep extends StatelessWidget {
  const _PathStep({
    required this.entry,
    required this.stepNumber,
    required this.state,
    required this.starEarnedToday,
    required this.difficulty,
    required this.style,
    required this.onTap,
  });

  final GameEntry entry;
  final int stepNumber;
  final PathStepState state;

  /// Whether this step's game has already paid its star today.
  ///
  /// Drawn on the platform rather than swapped into the state badge above it:
  /// the badge carries step *state* (done / current / locked), which is a
  /// different question from whether today's star is still there, and folding
  /// two meanings into one symbol would make both unreadable.
  final bool starEarnedToday;
  final int difficulty;
  final WorldStyle style;
  final VoidCallback? onTap;

  static const width = PathMapView._platformWidth;

  /// Badge + platform + label. Fixed so the map can position by centre.
  static const height = 150.0;

  static const _faceHeight = 74.0;

  static const _tierColors = {
    1: Color(0xFF6FAE97), // sage — gentle
    2: Color(0xFFDD9B4A), // amber — moderate
    3: Color(0xFFC96B6B), // clay — challenge
  };

  bool get _isCurrent => state == PathStepState.current;
  bool get _isLocked => state == PathStepState.locked;

  String get _semanticLabel {
    // Appended to the state's own wording rather than given a second node —
    // the step is deliberately one TalkBack stop, exactly as the lobby card is.
    final star = starEarnedToday ? ", got today's star" : '';
    switch (state) {
      case PathStepState.done:
        return 'Step $stepNumber, ${entry.name}, finished$star';
      case PathStepState.current:
        return 'Step $stepNumber, ${entry.name}, play this next$star';
      case PathStepState.available:
        return 'Step $stepNumber, ${entry.name}$star';
      case PathStepState.locked:
        return 'Step $stepNumber, ${entry.name}, locked$star';
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildBadge(),
        const SizedBox(height: 6),
        // The star marker rides on the platform's corner. `Clip.none` so it
        // can sit proud of the rock without the column growing — the map
        // positions every step by a fixed height.
        Stack(
          clipBehavior: Clip.none,
          children: [
            _buildPlatform(),
            if (starEarnedToday)
              const Positioned(top: -6, right: -6, child: _StarEarnedMarker()),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          entry.name,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.labelSmall.copyWith(
            color: style.labelOnScene,
            fontWeight: _isCurrent ? FontWeight.w800 : FontWeight.w600,
            // A dark scene needs the label lifted off the sky behind it.
            shadows: const [
              Shadow(color: Color(0x99000000), blurRadius: 4),
            ],
          ),
        ),
      ],
    );

    return Semantics(
      label: _semanticLabel,
      button: onTap != null,
      enabled: onTap != null,
      child: SizedBox(
        width: width,
        height: height,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: step,
          ),
        ),
      ),
    );
  }

  /// The floating rock: the game's colours on top, the world's shade beneath.
  Widget _buildPlatform() {
    // Registry entries carry a varying number of gradient colours (three, at
    // the time of writing), so the stops are derived rather than hard-coded —
    // a mismatch between the two lists throws inside createShader and silently
    // costs the whole decoration, leaving only the drop shadow on screen.
    final faceColors = entry.gradientColors;
    final gradientColors = [...faceColors, style.platformShade];
    final gradientStops = <double>[
      for (var i = 0; i < faceColors.length; i++)
        faceColors.length == 1 ? 0.0 : (i / (faceColors.length - 1)) * 0.55,
      1.0,
    ];

    final face = Container(
      width: width,
      height: _faceHeight,
      decoration: BoxDecoration(
        // Rounded on top, tighter below — reads as a slab seen slightly from
        // above, without needing a custom path or any artwork.
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(26),
          bottom: Radius.circular(10),
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gradientColors,
          stops: gradientStops,
        ),
        border: _isCurrent
            ? Border.all(color: style.currentRing, width: 3)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isLocked ? 0.18 : 0.38),
            blurRadius: _isCurrent ? 22 : 14,
            offset: Offset(0, _isCurrent ? 10 : 6),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The game's own logo, so a step on the path is recognisable as the
          // same game the child saw in the lobby row.
          GameLogo(
            asset: entry.logoAsset,
            size: 52,
            fallbackIcon: entry.icon,
            fallbackColor: AppColors.white,
            semanticLabel: entry.name,
          ),
          // Difficulty tier as a small dot, bottom-right — present for the
          // parent, and far too small to distract the child.
          Positioned(
            right: 8,
            bottom: 6,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _tierColors[difficulty] ?? _tierColors[2],
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.white.withValues(alpha: 0.8),
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (!_isLocked) return face;
    // Mute over an opaque base: bare `Opacity` blends toward whatever is
    // behind, which on a dark sky would drag the platform into the backdrop
    // instead of fading it.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.platformShade,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(26),
          bottom: Radius.circular(10),
        ),
      ),
      child: Opacity(opacity: 0.45, child: face),
    );
  }

  /// State badge above the platform. Shape carries the meaning: ringed circle
  /// for the current step, plain circle for done and available, rounded square
  /// for locked.
  Widget _buildBadge() {
    switch (state) {
      case PathStepState.current:
        return Container(
          width: 38,
          height: 38,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: style.currentRing, width: 2.5),
          ),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: style.badgeCurrent,
              shape: BoxShape.circle,
            ),
            child: Text('$stepNumber', style: _badgeTextStyle),
          ),
        );
      case PathStepState.done:
        return Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: style.badgeDone,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded,
              size: 19, color: AppColors.white),
        );
      case PathStepState.locked:
        return Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: style.badgeLocked,
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(Icons.lock_rounded,
              size: 17, color: AppColors.white),
        );
      case PathStepState.available:
        return Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: style.badgeAvailable,
            shape: BoxShape.circle,
          ),
          child: Text('$stepNumber', style: _badgeTextStyle),
        );
    }
  }

  static final _badgeTextStyle = AppTextStyles.labelSmall.copyWith(
    color: AppColors.white,
    fontWeight: FontWeight.w800,
  );
}
