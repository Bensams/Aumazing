import 'dart:ui' hide TextStyle, FontWeight;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart' show TextStyle, FontWeight;
import 'package:shared_ui/shared_ui.dart' show GameLanguage;

import '../../shared/fingertip_drag.dart';
import '../../shared/shape_painter_3d.dart';
import '../sari_sari_sort_game.dart' show StoreCategory;

/// Data describing a single sari-sari store item (Filipino context).
class StoreItemData {
  /// Filipino name, e.g. 'Tinapay'. Also the item's stable identifier: it is
  /// the analytics slug and the key the audio layer maps to a recording, so it
  /// stays put even when the printed label is translated.
  final String name;

  /// English display label, e.g. 'Bread'. Shown when the parent has chosen
  /// English — a child in an English-language session should read the word
  /// they are being taught, not the Filipino one.
  final String en;

  /// Emoji glyph used as the item's visual.
  final String emoji;

  /// The category this item belongs to (the correct bin).
  final StoreCategory category;

  /// The item's own natural/realistic color (e.g. banana = yellow), used to
  /// tint its card. Decoupled from [category] so color is not a sort shortcut.
  final Color color;

  const StoreItemData({
    required this.name,
    required this.en,
    required this.emoji,
    required this.category,
    required this.color,
  });

  /// The printed label for [language].
  ///
  /// Tagalog and Cebuano share [name]: these are sari-sari staples, and the
  /// everyday word for each one (tinapay, saging, sabon, sipilyo …) is the same
  /// in both. Only English needs its own column.
  String label(GameLanguage language) {
    switch (language) {
      case GameLanguage.english:
        return en;
      case GameLanguage.tagalog:
      case GameLanguage.cebuano:
        return name;
    }
  }
}

/// A large, ASD-friendly draggable store item for the Sari-Sari Store Sorting
/// game.
///
/// Renders a colored rounded-rect card with an emoji glyph and the item's
/// label in the session's [language]. The child picks it up and drops it into a [CategoryBin]. The owning
/// game decides whether the drop was correct via [onDropped]; this component
/// only handles movement, lift/return animations, and the locked (sorted)
/// state.
class DraggableItem extends PositionComponent with DragCallbacks, FingertipDrag {
  DraggableItem({
    required this.data,
    required this.color,
    required this.onPickedUp,
    required this.onDropped,
    this.onMoved,
    this.language = GameLanguage.english,
    required Vector2 position,
    required Vector2 size,
  }) : super(position: position, size: size) {
    homePosition = position.clone();
  }

  final StoreItemData data;
  final Color color;

  /// Language the card's label is printed in.
  final GameLanguage language;

  /// Fired when the child lifts the item (drag start).
  final void Function(DraggableItem item) onPickedUp;

  /// Fired when the child releases the item. [dropCenter] is the item's center
  /// in the game's coordinate space, used for bin hit-testing.
  final void Function(DraggableItem item, Vector2 dropCenter) onDropped;

  /// Fired every tick while the item is held, with its centre in game space,
  /// and once with null when it is let go.
  ///
  /// Ticks rather than drag events on purpose: this drives the mascot's gaze,
  /// and Flame only reports a drag when the finger actually moves. Driven off
  /// drag events alone the character's head would stall a frame or two behind
  /// whenever a child paused mid-drag — which is most of the time.
  final void Function(Vector2? center)? onMoved;

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
    startFingertipFollow(event.canvasPosition);
    add(ScaleEffect.to(
      Vector2.all(1.12),
      EffectController(duration: 0.12, curve: Curves.easeOut),
    ));
    onPickedUp(this);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (isLocked || !_dragging) return;
    moveFingertip(event.canvasEndPosition);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (followFingertip(dt)) onMoved?.call(visualCenter);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (isLocked || !_dragging) return;
    // Read the centre before the scale-down starts, so the drop point is the
    // item as the child last saw it.
    final dropCenter = visualCenter;
    _dragging = false;
    stopFingertipFollow();
    onMoved?.call(null);
    priority = 0;
    add(ScaleEffect.to(
      Vector2.all(1.0),
      EffectController(duration: 0.12, curve: Curves.easeOut),
    ));
    onDropped(this, dropCenter);
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    _dragging = false;
    stopFingertipFollow();
    onMoved?.call(null);
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

    // Only the wrong-bin state draws its own border; at rest the item takes
    // the parent's standing outline like every other object. It used to wear
    // a white one always, which on a board of items is indistinguishable from
    // a "this is the one" cue.
    ShapePainter3D.drawCard3D(
      canvas,
      rect,
      color: color,
      cornerRadius: _cornerRadius,
      alpha: 255, // bold, fully-saturated natural color
      showBorder: _showError,
      borderColor: _showError ? const Color(0xFFE88888) : null,
      borderWidth: 3.0,
    );

    _emojiPaint.render(
      canvas,
      data.emoji,
      Vector2(size.x / 2, size.y * 0.40),
      anchor: Anchor.center,
    );

    // White backing pill so the label stays legible on any item color.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.x * 0.08, size.y * 0.68, size.x * 0.84, size.y * 0.24),
        Radius.circular(size.y * 0.12),
      ),
      Paint()..color = const Color(0xFFFFFFFF).withAlpha(220),
    );
    _labelPaint.render(
      canvas,
      data.label(language),
      Vector2(size.x / 2, size.y * 0.80),
      anchor: Anchor.center,
    );
  }
}
