import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/animation.dart';

import '../../../config/game_motion.dart';
import '../../shared/fingertip_drag.dart';
import '../../shared/shape_painter_3d.dart';

/// The shape type drawn on each matchable card.
enum ShapeType { star, heart, circle, diamond, triangle }

/// A large, ASD-friendly tappable shape component for the Match It game.
///
/// Renders a colored rounded-rect card with a centered 3D shape icon.
/// Supports selection highlight, correct/incorrect feedback, hint state,
/// and gentle scale animations.
class MatchableShape extends PositionComponent
    with TapCallbacks, DragCallbacks, FingertipDrag {
  MatchableShape({
    required this.shapeType,
    required this.shapeColor,
    required this.index,
    required this.onSelected,
    this.onDragDropped,
    super.position,
    super.size,
  });

  final ShapeType shapeType;
  final Color shapeColor;
  final int index;

  /// Tap input: fired when the shape is tapped (selected).
  final void Function(int index) onSelected;

  /// Drag input: fired when the shape is dropped, with its centre in game
  /// coordinates so the game can find the shape it was dropped onto.
  final void Function(MatchableShape shape, Vector2 dropCenter)? onDragDropped;

  bool isSelected = false;
  bool isMatched = false;
  bool _showError = false;

  // ── Drag state ─────────────────────────────────────────────────────
  /// The pointer is being tracked by the drag recognizer.
  bool _pointerDown = false;

  /// The pointer has travelled past [_tapSlop] — a real drag, not a tap.
  bool _dragging = false;
  Vector2? _dragStartPos;
  /// Where the pointer went down, in game space. The tap/drag decision is
  /// DISPLACEMENT from here, not the sum of the pointer's deltas: accumulated
  /// deltas keep growing while a finger trembles in one spot, so a child with
  /// a tremor could cross the threshold — and lose their tap — without ever
  /// moving off the piece, which is the exact case the threshold exists to
  /// protect.
  Vector2? _pointerOrigin;

  /// Pointer travel (game px) below which a release counts as a tap.
  static const double _tapSlop = 14.0;

  // ── Hint state ─────────────────────────────────────────────────────
  bool _isHint = false;
  double _hintTime = 0.0;

  /// Whether this shape is currently showing a hint highlight.
  bool get isHint => _isHint;

  /// Sets the hint state and resets the animation timer.
  set isHint(bool v) {
    _isHint = v;
    if (v) {
      _hintTime = 0.0;
    }
  }

  /// Convenience method to activate the hint visual.
  void showHint() {
    isHint = true;
  }

  /// Convenience method to deactivate the hint visual.
  void hideHint() {
    isHint = false;
  }

  static const double _cornerRadius = 24.0;
  static const double _borderWidth = 3.0;

  // Flame's drag recognizer claims the pointer as soon as it moves at all,
  // which knocks the tap recognizer out of the gesture arena — so on a
  // component with both TapCallbacks and DragCallbacks, onTapUp only fires
  // for a perfectly still finger. Children are never that still, so taps are
  // resolved in onDragEnd instead (see [_tapSlop]); onTapUp remains as the
  // path for the rare tap the arena does award to the tap recognizer.
  @override
  void onTapDown(TapDownEvent event) {}

  @override
  void onTapUp(TapUpEvent event) {
    if (isMatched || _pointerDown) return;
    onSelected(index);
  }

  // ── Drag-and-drop input ─────────────────────────────────────────────

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (isMatched) return;
    _pointerDown = true;
    _dragging = false;
    _pointerOrigin = event.canvasPosition.clone();
    _dragStartPos = position.clone();
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (isMatched || !_pointerDown) return;

    if (!_dragging) {
      // Still tap-like: leave the card sitting in its slot so a shaky tap
      // doesn't visibly nudge it.
      final origin = _pointerOrigin;
      if (origin != null &&
          (event.canvasEndPosition - origin).length < _tapSlop) {
        return;
      }
      _dragging = true;
      priority = 100; // float above other shapes while dragging
      add(ScaleEffect.to(
        Vector2.all(1.1),
        EffectController(duration: 0.1, curve: Curves.easeOut),
      ));
      // Centring starts only once the gesture is confirmed as a drag — doing
      // it on the first pointer event would yank the card out from under a
      // child whose tap merely wobbled. The glide covers the catch-up.
      startFingertipFollow(event.canvasEndPosition);
      return;
    }

    moveFingertip(event.canvasEndPosition);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (!_pointerDown) return;
    _pointerDown = false;

    if (!_dragging) {
      // Released without ever leaving the card — that was a tap.
      if (!isMatched) onSelected(index);
      return;
    }

    _dragging = false;
    // Read the centre before the scale-down, so the drop point is the card as
    // the child last saw it.
    final dropCenter = visualCenter;
    stopFingertipFollow();
    priority = 0;
    scale = Vector2.all(1.0);
    // Snap instantly back to the slot, then let the game resolve the match
    // (feedback animations then play in the shape's home position).
    if (_dragStartPos != null) position = _dragStartPos!;
    onDragDropped?.call(this, dropCenter);
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    _pointerDown = false;
    if (!_dragging) return;
    _dragging = false;
    stopFingertipFollow();
    priority = 0;
    scale = Vector2.all(1.0);
    if (_dragStartPos != null) position = _dragStartPos!;
  }

  void select() {
    isSelected = true;
    add(ScaleEffect.by(
      Vector2.all(1.05),
      EffectController(duration: 0.15, curve: Curves.easeOut),
    ));
  }

  void deselect() {
    isSelected = false;
    scale = Vector2.all(1.0);
  }

  void markMatched() {
    isMatched = true;
    isSelected = false;
    add(ScaleEffect.by(
      Vector2.all(0.9),
      EffectController(duration: 0.3, curve: Curves.easeInOut),
    ));
  }

  void showError() {
    _showError = true;
    isSelected = true;
    add(
      SequenceEffect([
        MoveEffect.by(
          Vector2(6, 0),
          EffectController(duration: 0.05),
        ),
        MoveEffect.by(
          Vector2(-12, 0),
          EffectController(duration: 0.1),
        ),
        MoveEffect.by(
          Vector2(12, 0),
          EffectController(duration: 0.1),
        ),
        MoveEffect.by(
          Vector2(-6, 0),
          EffectController(duration: 0.05),
        ),
      ]),
    );
    Future.delayed(const Duration(milliseconds: 400), () {
      _showError = false;
      isSelected = false;
    });
  }

  @override
  void update(double dt) {
    super.update(dt);
    followFingertip(dt);
    if (_isHint) {
      _hintTime += dt;
    }
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);

    // Card background
    final bgAlpha = isMatched ? 30 : (_isHint ? 80 : (isSelected ? 80 : 40));
    Color? borderColor;
    if (_showError) borderColor = const Color(0xFFE88888);
    if (isSelected && !_showError) {
      borderColor = const Color(0xFF9B82C4).withAlpha(140);
    }
    if (_isHint) borderColor = const Color(0xFFFFA726);

    // Hint pulsing ring (same pattern as SequenceShape)
    if (_isHint) {
      final pulse = GameMotion.reduced
          ? 1.0
          : (math.sin(_hintTime * 2 * math.pi) + 1) / 2; // 0..1
      final pulseAlpha = (128 + 127 * pulse).round().clamp(0, 255);
      final hintPaint = Paint()
        ..color = const Color(0xFFFFA726).withAlpha(pulseAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(-8, -8, size.x + 16, size.y + 16),
          const Radius.circular(_cornerRadius + 4),
        ),
        hintPaint,
      );
    }

    ShapePainter3D.drawCard3D(
      canvas,
      rect,
      color: shapeColor,
      cornerRadius: _cornerRadius,
      alpha: bgAlpha,
      showBorder: isSelected || _showError || _isHint,
      borderColor: borderColor,
      borderWidth: _borderWidth,
    );

    // 3D shape icon in center
    final drawColor = isMatched ? shapeColor.withAlpha(80) : shapeColor;
    final shapeName = shapeType.name; // enum name matches shape_painter_3d keys
    ShapePainter3D.drawByName(
      canvas, shapeName, size.x / 2, size.y / 2, size.x * 0.3, drawColor,
    );
  }
}
