import 'dart:math' as math;
import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/painting.dart' show TextStyle;

import '../../sari_sari_sort/components/draggable_item.dart';
import '../buddy_art_cache.dart';

class BuddyComponent extends PositionComponent {
  BuddyComponent({
    required this.kind,
    required Vector2 position,
    required Vector2 size,
  }) : super(position: position, size: size);

  final BuddyKind kind;
  BuddyPose pose = BuddyPose.present;
  StoreItemData? request;
  bool bubbleVisible = false;
  bool dimmed = false;
  bool _pulse = false;
  double _frameClock = 0;
  int _frame = 0;

  Rect get handTarget => Rect.fromCenter(
        center: Offset(size.x * 0.52, size.y * 0.70),
        width: size.x * 0.72,
        height: size.y * 0.52,
      );

  Vector2 get handCenter =>
      position + Vector2(size.x * 0.52, size.y * 0.70);

  bool accepts(Vector2 gamePoint) {
    final local = gamePoint - position;
    // Twenty percent breathing room turns an imprecise drag into a successful
    // social response instead of mislabelling it as a social error.
    final inflated = handTarget.inflate(math.max(size.x, size.y) * 0.10);
    return inflated.contains(local.toOffset());
  }

  void showRequest(StoreItemData item) {
    request = item;
    bubbleVisible = true;
    pose = BuddyPose.present;
  }

  void hideRequest() => bubbleVisible = false;

  void pulseBubble() {
    bubbleVisible = true;
    _pulse = true;
    add(SequenceEffect([
      ScaleEffect.to(Vector2.all(1.04),
          EffectController(duration: 0.18, curve: Curves.easeOut)),
      ScaleEffect.to(Vector2.all(1),
          EffectController(duration: 0.18, curve: Curves.easeIn)),
    ], onComplete: () => _pulse = false));
  }

  void celebrate() {
    pose = BuddyPose.celebrate;
    _frame = 0;
    _frameClock = 0;
  }

  void reassure() {
    pose = BuddyPose.oops;
    _frame = 0;
    _frameClock = 0;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (isMounted) pose = BuddyPose.encourage;
    });
  }

  @override
  void update(double dt) {
    super.update(dt);
    _frameClock += dt;
    if (_frameClock >= 0.12) {
      _frameClock = 0;
      _frame = (_frame + 1) % pose.frames;
    }
  }

  @override
  void render(Canvas canvas) {
    final alpha = dimmed ? 95 : 255;
    final image = TulongBuddyArt.of(kind, pose);
    final bubbleHeight = size.y * 0.30;
    final bodyTop = bubbleHeight * 0.70;

    if (image == null) {
      canvas.drawCircle(
        Offset(size.x / 2, bodyTop + (size.y - bodyTop) / 2),
        size.x * 0.30,
        Paint()..color = Color.fromARGB(alpha, 126, 191, 181),
      );
      TextPaint(style: TextStyle(fontSize: size.x * 0.28)).render(
        canvas,
        '\u{1F917}',
        Vector2(size.x / 2, bodyTop + (size.y - bodyTop) / 2),
        anchor: Anchor.center,
      );
    } else {
      final cellW = image.width / pose.cols;
      final cellH = image.height / pose.rows;
      final frame = _frame.clamp(0, pose.frames - 1);
      final src = Rect.fromLTWH(
        (frame % pose.cols) * cellW,
        (frame ~/ pose.cols) * cellH,
        cellW,
        cellH,
      );
      canvas.drawImageRect(
        image,
        src,
        Rect.fromLTWH(0, bodyTop, size.x, size.y - bodyTop),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Color.fromARGB(alpha, 255, 255, 255),
      );
    }

    if (bubbleVisible && request != null) {
      final bubble = RRect.fromRectAndRadius(
        Rect.fromLTWH(size.x * 0.08, 0, size.x * 0.68, bubbleHeight),
        Radius.circular(bubbleHeight * 0.28),
      );
      canvas.drawRRect(bubble, Paint()..color = const Color(0xFFFFFFFF));
      canvas.drawRRect(
        bubble,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _pulse ? 6 : 3
          ..color = const Color(0xFF6C9BD2),
      );
      TextPaint(style: TextStyle(fontSize: bubbleHeight * 0.58)).render(
        canvas,
        request!.emoji,
        Vector2(size.x * 0.42, bubbleHeight * 0.50),
        anchor: Anchor.center,
      );
    }
  }
}
