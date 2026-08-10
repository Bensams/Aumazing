import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/animation.dart';

/// Keeps a dragged component centred on the child's fingertip.
///
/// Children aim by putting their finger *on* the thing they mean, so the point
/// they touch is the point that should be hit-tested against a bin, a slot or
/// a target shape. Following the pointer's delta instead — the obvious
/// implementation, and what every game here did first — preserves whatever
/// offset the finger happened to grab at, so a card gripped by its corner is
/// dropped a half-card away from where the child pointed.
///
/// Mix into a [PositionComponent] with `DragCallbacks` and drive it from the
/// drag events:
///
/// ```dart
/// void onDragStart(e) => startFingertipFollow(e.canvasPosition);
/// void onDragUpdate(e) => moveFingertip(e.canvasEndPosition);
/// void update(dt) { super.update(dt); followFingertip(dt); }
/// void onDragEnd(e) { final at = visualCenter; stopFingertipFollow(); ... }
/// ```
///
/// Positions are in the component's PARENT space, which for every game here is
/// the game's own canvas space — none of them put a camera between the two.
mixin FingertipDrag on PositionComponent {
  Vector2? _pointer;

  /// How far the component's centre sat from the fingertip when it was picked
  /// up. Decays to zero over [_settleSeconds] rather than being cancelled at
  /// once: a card that teleports out from under a child's finger reads as the
  /// card escaping them, which is the opposite of the intent.
  Vector2 _grabOffset = Vector2.zero();

  /// Progress of that decay, 0 → 1.
  double _settle = 0;

  /// Long enough to read as a glide, short enough that the component is
  /// already under the fingertip by the time a child has moved it anywhere.
  static const double _settleSeconds = 0.12;

  /// Distance from [position] to the component's visual centre.
  ///
  /// Derived from [anchor] rather than assumed: these games mix `topLeft`
  /// components (whose position is a corner) with `center` ones (whose
  /// position is already the centre), and getting this wrong offsets a drop
  /// by half the component. [scale] is included because components are
  /// commonly scaled up while held.
  Vector2 get _centreOffset => Vector2(
        (0.5 - anchor.x) * size.x * scale.x,
        (0.5 - anchor.y) * size.y * scale.y,
      );

  /// Where the component's centre currently sits in its parent's space.
  Vector2 get visualCenter => position + _centreOffset;

  /// Whether a fingertip is currently being tracked.
  bool get isFollowingFingertip => _pointer != null;

  /// Begin following [pointer], gliding in from wherever the component is now.
  ///
  /// For a component that also handles taps, call this at the moment the
  /// gesture is *confirmed* as a drag, not on the first pointer event —
  /// otherwise a slightly shaky tap yanks the component under the finger.
  void startFingertipFollow(Vector2 pointer) {
    _pointer = pointer.clone();
    _grabOffset = visualCenter - pointer;
    _settle = 0;
  }

  /// Update the tracked fingertip position.
  void moveFingertip(Vector2 pointer) => _pointer?.setFrom(pointer);

  void stopFingertipFollow() => _pointer = null;

  /// Advance the follow. Call from `update`; returns whether it moved.
  ///
  /// Driven by ticks rather than drag events because the grab offset has to
  /// keep decaying while the finger is held still — Flame only reports a drag
  /// when the pointer actually moves, so a child who grabs a corner and pauses
  /// would otherwise be left holding the corner.
  bool followFingertip(double dt) {
    final pointer = _pointer;
    if (pointer == null) return false;
    _settle = math.min(1.0, _settle + dt / _settleSeconds);
    final remaining = 1.0 - Curves.easeOut.transform(_settle);
    position = pointer + _grabOffset * remaining - _centreOffset;
    return true;
  }
}
