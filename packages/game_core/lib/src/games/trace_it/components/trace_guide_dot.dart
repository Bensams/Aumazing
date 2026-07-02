import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/painting.dart' show TextStyle;

import '../../../config/game_motion.dart';

/// A "ghost finger" (👆) that travels along a stroke path to demonstrate
/// how to trace it. Removes itself when the demo finishes.
///
/// Under [GameMotion.reduced] it degrades to a stationary pulse at the
/// stroke's start point so no large motion is shown.
class TraceGuideDot extends PositionComponent {
  TraceGuideDot({
    required List<Vector2> path,
    double handSize = 64,
    this.speed = 220, // px per second along the path
  })  : _path = path,
        super(
          position: path.first.clone(),
          size: Vector2.all(handSize),
          anchor: Anchor.center,
          priority: 200, // above the glyph and the child's ink
        );

  final List<Vector2> _path;
  final double speed;

  int _segment = 0;
  double _segmentProgress = 0; // px travelled within the current segment

  late TextPaint _handPaint;
  bool _travelling = true;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _handPaint = TextPaint(style: TextStyle(fontSize: size.y * 0.72));

    if (GameMotion.reduced || _path.length < 2) {
      // Stationary demo: pulse twice at the start point, then disappear.
      _travelling = false;
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
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!_travelling) return;

    var travel = speed * dt;
    while (travel > 0 && _segment < _path.length - 1) {
      final from = _path[_segment];
      final to = _path[_segment + 1];
      final segmentLength = from.distanceTo(to);
      final remaining = segmentLength - _segmentProgress;

      if (travel < remaining) {
        _segmentProgress += travel;
        travel = 0;
      } else {
        travel -= remaining;
        _segment++;
        _segmentProgress = 0;
      }
    }

    if (_segment >= _path.length - 1) {
      _travelling = false;
      position = _path.last.clone();
      add(ScaleEffect.to(
        Vector2.all(0.0),
        EffectController(duration: 0.25, curve: Curves.easeIn),
        onComplete: removeFromParent,
      ));
      return;
    }

    final from = _path[_segment];
    final to = _path[_segment + 1];
    final t = _segmentProgress / from.distanceTo(to);
    position = from + (to - from) * t;
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
