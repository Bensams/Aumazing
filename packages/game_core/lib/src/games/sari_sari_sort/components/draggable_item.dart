import 'dart:ui' hide TextStyle, FontWeight;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart' show TextStyle, FontWeight;

import '../../shared/shape_painter_3d.dart';
import '../sari_sari_sort_game.dart' show StoreCategory;

/// Data describing a single sari-sari store item (Filipino context).
class StoreItemData {
  /// Filipino display label, e.g. 'Tinapay'.
  final String name;

  /// Emoji glyph used as the item's visual.
  final String emoji;

  /// The category this item belongs to (the correct bin).
  final StoreCategory category;

  /// The item's own natural/realistic color (e.g. banana = yellow), used to
  /// tint its card. Decoupled from [category] so color is not a sort shortcut.
  final Color color;

  const StoreItemData({
    required this.name,
    required this.emoji,
    required this.category,
    required this.color,
  });
}

/// A large, ASD-friendly draggable store item for the Sari-Sari Store Sorting
/// game.
///
/// Renders a colored rounded-rect card with an emoji glyph and a Filipino
/// label. The child picks it up and drops it into a [CategoryBin]. The owning
/// game decides whether the drop was correct via [onDropped]; this component
/// only handles movement, lift/return animations, and the locked (sorted)
/// state.
class DraggableItem extends PositionComponent with DragCallbacks {
  DraggableItem({
    required this.data,
    required this.color,
    required this.onPickedUp,
    required this.onDropped,
    required Vector2 position,
    required Vector2 size,
  }) : super(position: position, size: size) {
    homePosition = position.clone();
  }

  final StoreItemData data;
  final Color color;

  /// Fired when the child lifts the item (drag start).
  final void Function(DraggableItem item) onPickedUp;

  /// Fired when the child releases the item. [dropCenter] is the item's center
  /// in the game's coordinate space, used for bin hit-testing.
  final void Function(DraggableItem item, Vector2 dropCenter) onDropped;

  /// Where the item rests in its tray. Used to snap back after a wrong drop.
  late Vector2 homePosition;

  /// Set once the item is correctly sorted into a bin. Locked items no longer
  /// respond to dragging.
  bool isLocked = false;

  bool _dragging = false;
  bool _showError = false;

  late TextPaint _emojiPaint;
  late TextPaint _labelPaint;

  static const double _cornerRadius = 22.0;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _emojiPaint = TextPaint(
      style: TextStyle(fontSize: size.y * 0.42),
    );
    _labelPaint = TextPaint(
      style: TextStyle(
        fontSize: size.y * 0.16,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF4A4458),
      ),
    );
  }

  // ── Drag handling ────────────────────────────────────────────────────

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (isLocked) return;
    _dragging = true;
    priority = 100; // float above other items + bins while dragging
    add(ScaleEffect.to(
      Vector2.all(1.12),
      EffectController(duration: 0.12, curve: Curves.easeOut),
    ));
    onPickedUp(this);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (isLocked || !_dragging) return;
    position += event.localDelta;
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (isLocked || !_dragging) return;
    _dragging = false;
    priority = 0;
    add(ScaleEffect.to(
      Vector2.all(1.0),
      EffectController(duration: 0.12, curve: Curves.easeOut),
    ));
    onDropped(this, position + size / 2);
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    _dragging = false;
    priority = 0;
    returnHome();
  }

  // ── Outcome animations ───────────────────────────────────────────────

  /// Animate the item back to its tray slot (wrong / cancelled drop).
  void returnHome() {
    scale = Vector2.all(1.0);
    add(MoveToEffect(
      homePosition,
      EffectController(duration: 0.25, curve: Curves.easeInOut),
    ));
  }

  /// Brief red shake to signal a wrong bin.
  void showError() {
    _showError = true;
    add(SequenceEffect([
      MoveEffect.by(Vector2(6, 0), EffectController(duration: 0.05)),
      MoveEffect.by(Vector2(-12, 0), EffectController(duration: 0.1)),
      MoveEffect.by(Vector2(12, 0), EffectController(duration: 0.1)),
      MoveEffect.by(Vector2(-6, 0), EffectController(duration: 0.05)),
    ]));
    Future.delayed(const Duration(milliseconds: 400), () {
      _showError = false;
    });
  }

  /// Lock the item into [binCenter], shrinking it as it settles in the bin.
  void lockInto(Vector2 binCenter, {VoidCallback? onSettled}) {
    isLocked = true;
    _dragging = false;
    priority = 0;
    final target = binCenter - (size * 0.3) / 2; // shrink to 30% near bin center
    add(MoveToEffect(
      target,
      EffectController(duration: 0.3, curve: Curves.easeInOut),
    ));
    add(ScaleEffect.to(
      Vector2.all(0.3),
      EffectController(duration: 0.3, curve: Curves.easeInOut),
      onComplete: onSettled,
    ));
  }

  // ── Rendering ────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);

    final borderColor =
        _showError ? const Color(0xFFE88888) : color.withAlpha(160);

    ShapePainter3D.drawCard3D(
      canvas,
      rect,
      color: color,
      cornerRadius: _cornerRadius,
      alpha: _dragging ? 70 : 50,
      showBorder: _dragging || _showError,
      borderColor: borderColor,
      borderWidth: 3.0,
    );

    _emojiPaint.render(
      canvas,
      data.emoji,
      Vector2(size.x / 2, size.y * 0.40),
      anchor: Anchor.center,
    );
    _labelPaint.render(
      canvas,
      data.name,
      Vector2(size.x / 2, size.y * 0.80),
      anchor: Anchor.center,
    );
  }
}
