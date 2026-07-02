import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/painting.dart' show TextStyle;

import '../../config/game_motion.dart';

/// An animated "ghost hand" (👆) that demonstrates the required gesture.
///
/// Used by the Easy difficulty tier as a visual interactive guide:
/// - [GhostHand.drag] travels from the item to its target (shows *how to
///   drag*), pressing down at the start and lifting at the end.
/// - [GhostHand.tap] pulses twice over a target (shows *where to tap*).
///
/// The component removes itself when the demo finishes. Under
/// [GameMotion.reduced] the drag demo degrades to a stationary pulse at the
/// target so no large motion is shown.
class GhostHand extends PositionComponent {
  GhostHand.drag({
    required Vector2 from,
    required Vector2 to,
    double handSize = 72,
  })  : _to = to.clone(),
        _tapOnly = false,
        super(
          position: from.clone(),
          size: Vector2.all(handSize),
          anchor: Anchor.center,
          priority: 200, // above items, bins, and dragged cards
        );

  GhostHand.tap({
    required Vector2 at,
    double handSize = 72,
  })  : _to = at.clone(),
        _tapOnly = true,
        super(
          position: at.clone(),
          size: Vector2.all(handSize),
          anchor: Anchor.center,
          priority: 200,
        );

  final Vector2 _to;
  final bool _tapOnly;

  late TextPaint _handPaint;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _handPaint = TextPaint(
      style: TextStyle(fontSize: size.y * 0.72),
    );

    if (_tapOnly || GameMotion.reduced) {
      // Stationary demo: sit on the target and pulse twice.
      position = _to.clone();
      add(SequenceEffect(
        [
          ScaleEffect.to(Vector2.all(1.25),
              EffectController(duration: 0.35, curve: Curves.easeOut)),
          ScaleEffect.to(Vector2.all(1.0),
              EffectController(duration: 0.35, curve: Curves.easeIn)),
          ScaleEffect.to(Vector2.all(1.25),
              EffectController(duration: 0.35, curve: Curves.easeOut)),
          ScaleEffect.to(Vector2.all(0.0),
              EffectController(duration: 0.3, curve: Curves.easeIn)),
        ],
        onComplete: removeFromParent,
      ));
      return;
    }

    // Full drag demo: press down at the item, glide to the target, lift off.
    add(SequenceEffect(
      [
        ScaleEffect.to(Vector2.all(0.85),
            EffectController(duration: 0.25, curve: Curves.easeOut)), // press
        MoveToEffect(_to,
            EffectController(duration: 1.2, curve: Curves.easeInOut)),
        ScaleEffect.to(Vector2.all(1.1),
            EffectController(duration: 0.2, curve: Curves.easeOut)), // lift
        ScaleEffect.to(Vector2.all(0.0),
            EffectController(duration: 0.25, curve: Curves.easeIn)),
      ],
      onComplete: removeFromParent,
    ));
  }

  @override
  void render(Canvas canvas) {
    // Soft halo so the hand reads on any background.
    canvas.drawCircle(
      Offset(size.x / 2, size.y / 2),
      size.x * 0.52,
      Paint()..color = const Color(0xFFFFFFFF).withAlpha(150),
    );
    _handPaint.render(
      canvas,
      '👆',
      Vector2(size.x / 2, size.y / 2),
      anchor: Anchor.center,
    );
  }
}
