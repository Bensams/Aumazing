import 'dart:math' as math;
import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/painting.dart' show TextStyle;

import '../../sari_sari_sort/components/draggable_item.dart';
import '../../shared/sprite_fit.dart';
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

  /// Height of the request bubble, drawn across the top of the component.
  double get _bubbleHeight => size.y * 0.30;

  /// The box the character is drawn into, below the bubble.
  Rect get _bodyBox {
    final top = _bubbleHeight * 0.70;
    return Rect.fromLTWH(0, top, size.x, size.y - top);
  }

  /// Where the character actually lands inside [_bodyBox].
  ///
  /// The sprite is letterboxed to keep its proportions (see [fitSpriteCell]),
  /// so on a box that is wider or taller than the cell the drawn character is
  /// narrower than the component. Hit-testing against the component instead of
  /// the drawing is what let a child "hand" an item to empty space beside the
  /// buddy — and, worse, miss the buddy they were aiming at.
  Rect get drawnBody {
    final image = TulongBuddyArt.of(kind, pose);
    if (image == null) return _bodyBox;
    return fitSpriteCell(
      _bodyBox,
      image.width / pose.cols,
      image.height / pose.rows,
    );
  }

  /// The box a dropped card has to land in to count as "handed to this buddy".
  ///
  /// It spans the buddy's full drawn width and the lower 80% of the body,
  /// because a four-year-old aims at the character they can see, not at the
  /// hands. A zone drawn tighter than the sprite made honest attempts read as
  /// motor misses; see [accepts] for the tolerance on top of this.
  Rect get handTarget {
    final body = drawnBody;
    return Rect.fromCenter(
      center: Offset(body.center.dx, body.top + body.height * 0.60),
      width: body.width,
      height: body.height * 0.80,
    );
  }

  Vector2 get handCenter {
    final body = drawnBody;
    return position + Vector2(body.center.dx, body.top + body.height * 0.62);
  }

  /// Slack added around [handTarget], as a fraction of the component's longer
  /// side, to forgive the aim of a child still building fine motor control.
  static const double _tolerance = 0.16;

  bool accepts(Vector2 gamePoint) => distanceTo(gamePoint) != null;

  /// How far [gamePoint] lands from the centre of the accept zone, or null if
  /// it misses the zone entirely.
  ///
  /// Two buddies share the character column on a tier-3 round, and with this
  /// much tolerance their zones overlap in the gutter between them. The caller
  /// uses this to give an ambiguous drop to the buddy it landed nearest,
  /// instead of to whichever buddy happens to be checked first.
  double? distanceTo(Vector2 gamePoint) {
    final local = (gamePoint - position).toOffset();
    // Sixteen percent breathing room turns an imprecise drag into a successful
    // social response instead of mislabelling it as a social error.
    final inflated = handTarget.inflate(math.max(size.x, size.y) * _tolerance);
    if (!inflated.contains(local)) return null;
    return (local - handTarget.center).distance;
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
    add(
      SequenceEffect([
        ScaleEffect.to(
          Vector2.all(1.04),
          EffectController(duration: 0.18, curve: Curves.easeOut),
        ),
        ScaleEffect.to(
          Vector2.all(1),
          EffectController(duration: 0.18, curve: Curves.easeIn),
        ),
      ], onComplete: () => _pulse = false),
    );
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
    final bubbleHeight = _bubbleHeight;
    final body = _bodyBox;
    final bodyTop = body.top;

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
      // Fit the cell inside the body box instead of filling it. The box is
      // derived from the playfield and its proportions vary with the device;
      // stretching the character to match turned the buddy into a smear on
      // every short landscape canvas. See [fitSpriteCell].
      canvas.drawImageRect(
        image,
        src,
        fitSpriteCell(body, cellW, cellH),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Color.fromARGB(alpha, 255, 255, 255),
      );
    }

    if (bubbleVisible && request != null) {
      // Sit the bubble over the character the child is looking at, not over the
      // component's own box: when the sprite is letterboxed the two are not the
      // same, and a bubble pinned to the box drifts off to one side. It stays
      // above [_bodyBox] either way, so it never covers a face.
      final drawn = drawnBody;
      final bubbleW = math.min(
        size.x * 0.76,
        math.max(drawn.width * 0.86, 1.0),
      );
      final bubbleRect = Rect.fromLTWH(
        (drawn.center.dx - bubbleW / 2).clamp(
          0.0,
          math.max(size.x - bubbleW, 0.0),
        ),
        0,
        bubbleW,
        bubbleHeight,
      );
      final bubble = RRect.fromRectAndRadius(
        bubbleRect,
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
        Vector2(bubbleRect.center.dx, bubbleHeight * 0.50),
        anchor: Anchor.center,
      );
    }
  }
}
