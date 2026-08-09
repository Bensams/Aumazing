import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart' show TextStyle;

import '../../shared/shape_painter_3d.dart';

/// A round token that lives in a side tray — either a buddy piece (left) or the
/// child's avatar piece (right).
///
/// Buddy pieces are non-interactive; the game animates them into a slot. Child
/// pieces are interactive during the child's turn: tap to select, or drag onto
/// a slot to place.
class GamePiece extends PositionComponent with TapCallbacks, DragCallbacks {
  GamePiece({
    required this.emoji,
    required this.color,
    required this.isChild,
    this.onTapped,
    this.onPickedUp,
    this.onDragEnded,
    required Vector2 position,
    required Vector2 size,
  }) : super(position: position, size: size, anchor: Anchor.center);

  final String emoji;
  final Color color;
  final bool isChild;

  /// Child tap: select this piece.
  final void Function(GamePiece piece)? onTapped;

  /// Child drag start.
  final void Function(GamePiece piece)? onPickedUp;

  /// Child drag release; [dropCenter] is the piece centre in game coordinates.
  final void Function(GamePiece piece, Vector2 dropCenter)? onDragEnded;

  /// Enabled only during the child's turn.
  bool interactive = false;
  bool selected = false;

  /// The pointer is being tracked by the drag recognizer.
  bool _pointerDown = false;

  /// The pointer has travelled past [_tapSlop] — a real drag, not a tap.
  bool _dragging = false;
  final Vector2 _dragTravel = Vector2.zero();
  late Vector2 _homePosition;

  /// Pointer travel (game px) below which a release counts as a tap.
  static const double _tapSlop = 14.0;

  late TextPaint _emojiPaint;

  static const double _borderWidth = 3.0;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _homePosition = position.clone();
    _emojiPaint = TextPaint(style: TextStyle(fontSize: size.y * 0.5));
  }

  void select() {
    if (selected) return;
    selected = true;
    add(ScaleEffect.to(
      Vector2.all(1.15),
      EffectController(duration: 0.12, curve: Curves.easeOut),
    ));
  }

  void deselect() {
    if (!selected) return;
    selected = false;
    add(ScaleEffect.to(Vector2.all(1.0), EffectController(duration: 0.12)));
  }

  /// Animate the piece into [targetCenter], then run [onDone].
  void moveToTarget(Vector2 targetCenter, {void Function()? onDone}) {
    interactive = false;
    selected = false;
    priority = 300;
    add(ScaleEffect.to(Vector2.all(1.0), EffectController(duration: 0.15)));
    add(MoveToEffect(
      targetCenter,
      EffectController(duration: 0.35, curve: Curves.easeInOut),
      onComplete: onDone,
    ));
  }

  void returnHome() {
    scale = Vector2.all(1.0);
    priority = 0;
    add(MoveToEffect(
      _homePosition,
      EffectController(duration: 0.2, curve: Curves.easeOut),
    ));
  }

  // ── Tap (select) ─────────────────────────────────────────────────────
  // Flame's drag recognizer claims the pointer on its first movement, which
  // knocks the tap recognizer out of the gesture arena — so onTapUp only
  // fires for a perfectly still finger. Taps are therefore resolved in
  // onDragEnd (see [_tapSlop]); this stays as the path for the rare tap the
  // arena does award to the tap recognizer.
  @override
  void onTapUp(TapUpEvent event) {
    if (isChild && interactive && !_pointerDown) onTapped?.call(this);
  }

  // ── Drag (place) ─────────────────────────────────────────────────────
  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (!isChild || !interactive) return;
    _pointerDown = true;
    _dragging = false;
    _dragTravel.setZero();
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (!_pointerDown) return;
    _dragTravel.add(event.localDelta);

    if (!_dragging) {
      // Still tap-like: leave the piece in the tray so a shaky tap doesn't
      // visibly nudge it.
      if (_dragTravel.length < _tapSlop) return;
      _dragging = true;
      priority = 300;
      onPickedUp?.call(this);
      add(ScaleEffect.to(Vector2.all(1.15), EffectController(duration: 0.1)));
      position += _dragTravel; // catch up on the travel so far
      return;
    }

    position += event.localDelta;
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (!_pointerDown) return;
    _pointerDown = false;

    if (!_dragging) {
      // Released without ever leaving the piece — that was a tap.
      if (isChild && interactive) onTapped?.call(this);
      return;
    }

    _dragging = false;
    onDragEnded?.call(this, position.clone()); // anchor.center → position is centre
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    _pointerDown = false;
    if (!_dragging) return;
    _dragging = false;
    returnHome();
  }

  @override
  void render(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final r = size.x / 2;

    ShapePainter3D.drawCircle(canvas, cx, cy, r * 0.9, color);

    // Highlight ring: bright when selected, subtle when interactive/ready.
    if (selected || (isChild && interactive)) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? _borderWidth + 1 : _borderWidth
        ..color = selected
            ? const Color(0xFFFFA726)
            : const Color(0xFFFFFFFF).withAlpha(150);
      canvas.drawCircle(Offset(cx, cy), r * 0.95, ring);
    }

    _emojiPaint.render(canvas, emoji, Vector2(cx, cy), anchor: Anchor.center);
  }
}
