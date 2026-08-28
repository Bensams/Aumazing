import 'dart:math' as math;
import 'dart:ui';

/// The four greetings a buddy can offer in "Kumusta!".
///
/// Each one is a *social bid* a Filipino child meets every day — a wave from
/// across the room, a palm held up for a high-five, a fist offered for a bump,
/// a thumb raised in approval. They were chosen because all four are answered
/// with the same gesture they are offered with, so the child never has to learn
/// a mapping on top of the social skill itself.
///
/// [spriteAction] names the sprite sheet the buddy plays. Only [wave] has a
/// sheet drawn for this gesture; the other three are *composed* from sheets
/// that already ship (see `buddy_art_cache.dart`), which is why the mapping
/// lives here rather than being assumed from the slug.
enum Greeting {
  /// An open hand swinging — the greeting every other one is measured against.
  wave('wave', 'wave'),

  /// A flat palm held up, waiting to be met. `present` is the sheet: an open
  /// palm raised toward the viewer, generated as "look at this" but reading as
  /// an offered hand once there is no object in it.
  highFive('high_five', 'present'),

  /// A closed hand held out. `celebrate` raises both closed hands, which is the
  /// only closed-hand sheet either character has.
  fistBump('fist_bump', 'celebrate'),

  /// A thumb up. `point` is the nearest sheet — one hand raised with a rigid
  /// digit extended — and is the one action whose handedness is already pinned
  /// (see scripts/SPRITES.md), so it never mirrors between frames.
  thumbsUp('thumbs_up', 'point');

  const Greeting(this.slug, this.spriteAction);

  /// Stable analytics identifier. Never rename: it lands in telemetry.
  final String slug;

  /// Sprite-sheet action the buddy plays to offer this greeting.
  final String spriteAction;
}

/// Draws [greeting] as a painted hand inside [box].
///
/// Vector glyphs rather than generated art, for the same reason
/// `sari_sari_sort` paints its cards: an icon the child must hit has to stay
/// crisp at any size and recolour with the palette, and four hands are simple
/// enough that a bundled PNG would only add a way for the row to render blank.
///
/// The four hands are deliberately distinguishable by *silhouette* alone —
/// open with motion arcs, open without, closed, closed with a thumb — so a
/// child with a colour-vision difference tells them apart the same way.
void paintGreetingGlyph(
  Canvas canvas,
  Greeting greeting,
  Rect box, {
  required Color skin,
  required Color ink,
}) {
  final s = box.shortestSide;
  final centre = box.center;
  final fill = Paint()..color = skin;
  final stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = s * 0.05
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = ink;

  switch (greeting) {
    case Greeting.wave:
      _openHand(canvas, centre, s, fill, stroke, tilt: -0.28, arcs: true);
    case Greeting.highFive:
      _openHand(canvas, centre, s, fill, stroke, tilt: 0, arcs: false);
    case Greeting.fistBump:
      _fist(canvas, centre, s, fill, stroke, thumbUp: false);
    case Greeting.thumbsUp:
      _fist(canvas, centre, s, fill, stroke, thumbUp: true);
  }
}

/// Palm plus four fingers and a thumb. [tilt] leans the whole hand (the wave
/// is drawn mid-swing); [arcs] adds the two motion strokes that separate a
/// *wave* from a *high-five*, which are otherwise the same hand.
void _openHand(
  Canvas canvas,
  Offset centre,
  double s,
  Paint fill,
  Paint stroke, {
  required double tilt,
  required bool arcs,
}) {
  canvas.save();
  canvas.translate(centre.dx, centre.dy);
  canvas.rotate(tilt);

  final palm = RRect.fromRectAndRadius(
    Rect.fromCenter(
        center: Offset(0, s * 0.16), width: s * 0.44, height: s * 0.34),
    Radius.circular(s * 0.14),
  );
  canvas.drawRRect(palm, fill);
  canvas.drawRRect(palm, stroke);

  // Four fingers, the middle pair a touch longer, as a real hand reads.
  const dxs = [-0.165, -0.055, 0.055, 0.165];
  const lengths = [0.26, 0.32, 0.30, 0.24];
  for (var i = 0; i < dxs.length; i++) {
    final finger = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(s * dxs[i], -s * (lengths[i] / 2 + 0.005)),
        width: s * 0.095,
        height: s * lengths[i],
      ),
      Radius.circular(s * 0.05),
    );
    canvas.drawRRect(finger, fill);
    canvas.drawRRect(finger, stroke);
  }

  // Thumb, off to the side and shorter, so the hand has a front and a back.
  canvas.save();
  canvas.translate(-s * 0.24, s * 0.10);
  canvas.rotate(-0.6);
  final thumb = RRect.fromRectAndRadius(
    Rect.fromCenter(center: Offset.zero, width: s * 0.10, height: s * 0.22),
    Radius.circular(s * 0.05),
  );
  canvas.drawRRect(thumb, fill);
  canvas.drawRRect(thumb, stroke);
  canvas.restore();

  if (arcs) {
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.045
      ..strokeCap = StrokeCap.round
      ..color = stroke.color.withValues(alpha: 0.55);
    for (final r in [0.34, 0.46]) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(-s * 0.02, -s * 0.02), radius: s * r),
        -math.pi * 0.62,
        math.pi * 0.34,
        false,
        arcPaint,
      );
    }
  }

  canvas.restore();
}

/// A closed hand. [thumbUp] raises the thumb, which is the only difference
/// between the fist-bump and the thumbs-up — and the reason the fist is drawn
/// with a wrist, so the two never collapse into one blob.
void _fist(
  Canvas canvas,
  Offset centre,
  double s,
  Paint fill,
  Paint stroke, {
  required bool thumbUp,
}) {
  canvas.save();
  canvas.translate(centre.dx, centre.dy + (thumbUp ? s * 0.08 : 0));

  final knuckles = RRect.fromRectAndRadius(
    Rect.fromCenter(center: Offset.zero, width: s * 0.46, height: s * 0.42),
    Radius.circular(s * 0.15),
  );
  canvas.drawRRect(knuckles, fill);
  canvas.drawRRect(knuckles, stroke);

  // Curled fingers: three shallow grooves across the front of the fist.
  final groove = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = s * 0.035
    ..strokeCap = StrokeCap.round
    ..color = stroke.color.withValues(alpha: 0.7);
  for (final dy in [-0.09, 0.0, 0.09]) {
    canvas.drawLine(
        Offset(-s * 0.16, s * dy), Offset(s * 0.16, s * dy), groove);
  }

  if (thumbUp) {
    final thumb = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset(-s * 0.10, -s * 0.34),
          width: s * 0.14,
          height: s * 0.30),
      Radius.circular(s * 0.07),
    );
    canvas.drawRRect(thumb, fill);
    canvas.drawRRect(thumb, stroke);
  } else {
    // The wrist, below the fist: a hand offered forward, not held up. Without
    // it the fist reads as a thumbs-up that has lost its thumb.
    final wrist = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset(0, s * 0.30), width: s * 0.30, height: s * 0.20),
      Radius.circular(s * 0.08),
    );
    canvas.drawRRect(wrist, fill);
    canvas.drawRRect(wrist, stroke);
  }

  canvas.restore();
}
