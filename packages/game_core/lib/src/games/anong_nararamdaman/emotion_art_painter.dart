import 'dart:ui';

import 'emotions.dart';

/// The drawing vocabulary shared by all three painters below: filled pastel
/// shapes, one dark outline weight, no gradients, no texture — the same set
/// `RoutineArtPainter` uses, so a fallback card sits beside a shipped one
/// without looking like it came from a different book.
class _Ink {
  static const Color ink = Color(0xFF3F3B4A);
  static const Color skin = Color(0xFFFFD9BE);
  static const Color mint = Color(0xFFB8E8D4);
  static const Color sky = Color(0xFFB8D8F0);
  static const Color peach = Color(0xFFFFD4C4);
  static const Color butter = Color(0xFFFFF4C4);
  static const Color lav = Color(0xFFD4C5E8);
  static const Color rose = Color(0xFFF2A8B0);
  static const Color white = Color(0xFFFFFDF8);
  static const Color brown = Color(0xFFC49A6C);

  static Paint fill(Color c) => Paint()..color = c;

  static Paint line([double w = 3.2]) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = ink;

  static void rrect(Canvas c, Rect r, double radius, Color f) {
    final rr = RRect.fromRectXY(r, radius, radius);
    c.drawRRect(rr, fill(f));
    c.drawRRect(rr, line());
  }

  static void circle(Canvas c, Offset o, double r, Color f) {
    c.drawCircle(o, r, fill(f));
    c.drawCircle(o, r, line());
  }
}

/// The geometry of one expression, as numbers a painter can interpolate.
///
/// Every field is a *deviation from neutral*, which is what makes the buddy's
/// neutral→emotion transition a straight lerp rather than a special case per
/// emotion. The three that carry almost all the recognisability are [smile],
/// [openness] and [browInner]; the rest are supporting detail.
class _Expression {
  const _Expression({
    this.smile = 0,
    this.openness = 0,
    this.browInner = 0,
    this.browLift = 0,
    this.eyeOpen = 1,
    this.tear = 0,
    this.sweat = 0,
    this.steam = 0,
    this.blush = 0.35,
  });

  /// Mouth curvature: +1 a full smile, 0 flat, −1 a full frown.
  final double smile;

  /// How far the mouth is open, 0–1. Surprise is mostly this.
  final double openness;

  /// Inner brow ends: +1 raised (sad, scared), −1 lowered (angry). This single
  /// number is the difference between a sad face and an angry one when the
  /// mouth of both is turned down, which is exactly the discrimination tier 2
  /// asks for — so the fallback has to draw it properly or the game is unfair.
  final double browInner;

  /// Both brows raised together (surprise), or pulled down (anger).
  final double browLift;

  /// Eye height multiplier — wide for fear and surprise.
  final double eyeOpen;

  /// A tear on the cheek (sad).
  final double tear;

  /// A sweat bead at the temple (scared).
  final double sweat;

  /// Puffs at the temples (angry).
  final double steam;

  /// Cheek colour.
  final double blush;

  static _Expression lerp(_Expression a, _Expression b, double t) =>
      _Expression(
        smile: _l(a.smile, b.smile, t),
        openness: _l(a.openness, b.openness, t),
        browInner: _l(a.browInner, b.browInner, t),
        browLift: _l(a.browLift, b.browLift, t),
        eyeOpen: _l(a.eyeOpen, b.eyeOpen, t),
        tear: _l(a.tear, b.tear, t),
        sweat: _l(a.sweat, b.sweat, t),
        steam: _l(a.steam, b.steam, t),
        blush: _l(a.blush, b.blush, t),
      );

  static double _l(double a, double b, double t) => a + (b - a) * t;
}

const _neutral = _Expression(smile: 0.08);

const Map<Emotion, _Expression> _expressions = {
  Emotion.happy: _Expression(
      smile: 1, openness: 0.22, browLift: 0.15, eyeOpen: 0.92, blush: 0.7),
  Emotion.sad: _Expression(
      smile: -0.9, browInner: 0.85, eyeOpen: 0.85, tear: 1, blush: 0.25),
  Emotion.scared: _Expression(
      smile: -0.45,
      openness: 0.5,
      browInner: 0.95,
      browLift: 0.55,
      eyeOpen: 1.45,
      sweat: 1,
      blush: 0.15),
  Emotion.surprised: _Expression(
      smile: 0, openness: 1, browInner: 0.1, browLift: 1, eyeOpen: 1.35),
  Emotion.angry: _Expression(
      smile: -0.75,
      openness: 0.12,
      browInner: -0.95,
      browLift: -0.25,
      eyeOpen: 0.9,
      steam: 1,
      blush: 0.8),
};

/// Draws a schematic face for [emotion] into a [size] × [size] box at [origin].
///
/// This is the fallback for a missing PNG and it is **not** a placeholder. The
/// game asks "how does he feel?", so a card that cannot answer that question
/// ends the session in practice even if the app keeps running. Every expression
/// therefore differs from every other in at least two of mouth curve, mouth
/// opening and brow angle — enough that the five are still told apart at card
/// size with the art bundle entirely absent.
class EmotionFacePainter {
  EmotionFacePainter._();

  static void paint(
    Canvas canvas,
    Emotion emotion,
    Offset origin,
    double size, {
    double t = 1.0,
  }) {
    final e = _Expression.lerp(
        _neutral, _expressions[emotion]!, t.clamp(0.0, 1.0));

    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(size / 100, size / 100);

    // Head.
    _Ink.circle(canvas, const Offset(50, 52), 38, _Ink.skin);

    // Hair: a simple cap, so the face reads as a child's rather than a smiley.
    final hair = Path()
      ..moveTo(14, 46)
      ..quadraticBezierTo(20, 10, 50, 10)
      ..quadraticBezierTo(80, 10, 86, 46)
      ..quadraticBezierTo(70, 30, 50, 30)
      ..quadraticBezierTo(30, 30, 14, 46)
      ..close();
    canvas.drawPath(hair, _Ink.fill(const Color(0xFF4A3F55)));
    canvas.drawPath(hair, _Ink.line(2.8));

    // Cheeks.
    if (e.blush > 0.01) {
      final blush = Paint()
        ..color = Color.fromRGBO(242, 168, 176, (e.blush * 0.75).clamp(0, 1));
      canvas.drawCircle(const Offset(26, 62), 7.5, blush);
      canvas.drawCircle(const Offset(74, 62), 7.5, blush);
    }

    _eyes(canvas, e);
    _brows(canvas, e);
    _mouth(canvas, e);
    _accents(canvas, e);

    canvas.restore();
  }

  static void _eyes(Canvas canvas, _Expression e) {
    final ry = (5.0 * e.eyeOpen).clamp(1.5, 12.0);
    const rx = 4.6;
    for (final dx in [35.0, 65.0]) {
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(dx, 50), width: rx * 2, height: ry * 2),
        _Ink.fill(_Ink.white),
      );
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(dx, 50), width: rx * 2, height: ry * 2),
        _Ink.line(2.4),
      );
      canvas.drawCircle(
          Offset(dx, 50), (2.6).clamp(1.0, ry), _Ink.fill(_Ink.ink));
    }
  }

  static void _brows(Canvas canvas, _Expression e) {
    // Baseline height, lifted or lowered as a whole.
    final y = 36.0 - e.browLift * 5.0;
    // Inner ends move opposite to the outer ends: raised inner reads sad or
    // frightened, lowered inner reads angry. 6 px of travel is plenty at this
    // scale and stays inside the forehead.
    final inner = y - e.browInner * 6.0;
    final outer = y + e.browInner * 2.5;

    canvas.drawPath(
      Path()
        ..moveTo(26, outer)
        ..quadraticBezierTo(31, outer - 2.5, 42, inner),
      _Ink.line(3.4),
    );
    canvas.drawPath(
      Path()
        ..moveTo(74, outer)
        ..quadraticBezierTo(69, outer - 2.5, 58, inner),
      _Ink.line(3.4),
    );
  }

  static void _mouth(Canvas canvas, _Expression e) {
    const cx = 50.0;
    const cy = 71.0;
    final halfW = 12.0 + e.openness * 2.0;

    if (e.openness > 0.08) {
      // An open mouth: an ellipse whose top and bottom edges still carry the
      // smile, so "open and happy" and "open and afraid" are not the same shape.
      final h = 4.0 + e.openness * 14.0;
      final path = Path()
        ..moveTo(cx - halfW, cy - e.smile * 2.0)
        ..quadraticBezierTo(cx, cy - h * 0.55 - e.smile * 4.0, cx + halfW,
            cy - e.smile * 2.0)
        ..quadraticBezierTo(
            cx, cy + h * 0.9 + e.smile * 2.0, cx - halfW, cy - e.smile * 2.0)
        ..close();
      canvas.drawPath(path, _Ink.fill(const Color(0xFF7A4550)));
      canvas.drawPath(path, _Ink.line(3.0));
      return;
    }

    // A closed mouth: one arc, curving up or down with [smile].
    canvas.drawPath(
      Path()
        ..moveTo(cx - halfW, cy)
        ..quadraticBezierTo(cx, cy + e.smile * 11.0, cx + halfW, cy),
      _Ink.line(3.6),
    );
  }

  static void _accents(Canvas canvas, _Expression e) {
    if (e.tear > 0.05) {
      final tear = Path()
        ..moveTo(31, 58)
        ..quadraticBezierTo(26, 66 + e.tear * 6, 31, 70 + e.tear * 6)
        ..quadraticBezierTo(36, 66 + e.tear * 6, 31, 58)
        ..close();
      canvas.drawPath(
          tear,
          _Ink.fill(Color.fromRGBO(
              120, 190, 232, (0.55 + e.tear * 0.45).clamp(0, 1))));
      canvas.drawPath(tear, _Ink.line(2.2));
    }
    if (e.sweat > 0.05) {
      final bead = Path()
        ..moveTo(84, 30)
        ..quadraticBezierTo(78, 38, 84, 42)
        ..quadraticBezierTo(90, 38, 84, 30)
        ..close();
      canvas.drawPath(bead, _Ink.fill(_Ink.sky));
      canvas.drawPath(bead, _Ink.line(2.2));
    }
    if (e.steam > 0.05) {
      final p = _Ink.line(2.6);
      canvas.drawPath(
          Path()
            ..moveTo(12, 30)
            ..quadraticBezierTo(6, 24, 11, 18),
          p);
      canvas.drawPath(
          Path()
            ..moveTo(88, 30)
            ..quadraticBezierTo(94, 24, 89, 18),
          p);
    }
  }
}

/// Draws a schematic situation picture.
///
/// Emblematic rather than narrative: one recognisable object per scene, drawn
/// large. A fallback scene only has to say *what happened* well enough for the
/// caption and the buddy's face to make sense together — the reasoning about
/// the emotion is carried by the face, which is the picture that must not fail.
class SceneArtPainter {
  SceneArtPainter._();

  static void paint(Canvas canvas, SceneArt art, Offset origin, double size) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(size / 100, size / 100);

    switch (art) {
      case SceneArt.gift:
        _gift(canvas);
        break;
      case SceneArt.finishedDrawing:
        _drawing(canvas);
        break;
      case SceneArt.iceCreamFell:
        _iceCream(canvas);
        break;
      case SceneArt.spilledDrink:
        _spilledDrink(canvas);
        break;
      case SceneArt.dogBarked:
        _dog(canvas);
        break;
      case SceneArt.loudThunder:
        _thunder(canvas);
        break;
      case SceneArt.jackInBox:
        _jackInBox(canvas);
        break;
      case SceneArt.surpriseBalloons:
        _balloons(canvas);
        break;
      case SceneArt.towerFell:
        _towerFell(canvas);
        break;
      case SceneArt.puzzleStuck:
        _puzzle(canvas);
        break;
    }

    canvas.restore();
  }

  static void _gift(Canvas c) {
    _Ink.rrect(c, const Rect.fromLTWH(22, 42, 56, 46), 6, _Ink.rose);
    c.drawLine(const Offset(50, 42), const Offset(50, 88), _Ink.line());
    c.drawLine(const Offset(22, 58), const Offset(78, 58), _Ink.line());
    // Bow.
    c.drawPath(
      Path()
        ..moveTo(50, 42)
        ..quadraticBezierTo(30, 34, 34, 24)
        ..quadraticBezierTo(44, 20, 50, 42)
        ..quadraticBezierTo(56, 20, 66, 24)
        ..quadraticBezierTo(70, 34, 50, 42)
        ..close(),
      _Ink.fill(_Ink.butter),
    );
    c.drawPath(
      Path()
        ..moveTo(50, 42)
        ..quadraticBezierTo(30, 34, 34, 24)
        ..quadraticBezierTo(44, 20, 50, 42)
        ..quadraticBezierTo(56, 20, 66, 24)
        ..quadraticBezierTo(70, 34, 50, 42)
        ..close(),
      _Ink.line(),
    );
  }

  static void _drawing(Canvas c) {
    _Ink.rrect(c, const Rect.fromLTWH(20, 18, 60, 64), 5, _Ink.white);
    // A child's sun-and-house doodle on the page.
    c.drawCircle(const Offset(36, 34), 8, _Ink.fill(_Ink.butter));
    c.drawCircle(const Offset(36, 34), 8, _Ink.line(2.4));
    c.drawPath(
      Path()
        ..moveTo(48, 68)
        ..lineTo(48, 48)
        ..lineTo(64, 38)
        ..lineTo(80 - 8, 48)
        ..lineTo(72, 68)
        ..close(),
      _Ink.fill(_Ink.mint),
    );
    c.drawPath(
      Path()
        ..moveTo(48, 68)
        ..lineTo(48, 48)
        ..lineTo(64, 38)
        ..lineTo(72, 48)
        ..lineTo(72, 68)
        ..close(),
      _Ink.line(2.4),
    );
    // A crayon lying beside it.
    _Ink.rrect(c, const Rect.fromLTWH(24, 84, 34, 9), 4, _Ink.rose);
  }

  static void _iceCream(Canvas c) {
    // Cone upside down on the ground, scoop already off it.
    c.drawPath(
      Path()
        ..moveTo(30, 60)
        ..lineTo(54, 60)
        ..lineTo(42, 88)
        ..close(),
      _Ink.fill(_Ink.brown),
    );
    c.drawPath(
      Path()
        ..moveTo(30, 60)
        ..lineTo(54, 60)
        ..lineTo(42, 88)
        ..close(),
      _Ink.line(),
    );
    _Ink.circle(c, const Offset(70, 78), 12, _Ink.peach);
    // Ground line, so the scoop is clearly *down* rather than floating.
    c.drawLine(const Offset(12, 90), const Offset(92, 90), _Ink.line(2.6));
    // A couple of motion ticks above the fallen scoop.
    c.drawLine(const Offset(70, 58), const Offset(70, 50), _Ink.line(2.2));
    c.drawLine(const Offset(82, 62), const Offset(88, 56), _Ink.line(2.2));
  }

  static void _spilledDrink(Canvas c) {
    // Cup on its side with the drink running out.
    c.save();
    c.translate(46, 56);
    c.rotate(1.1);
    _Ink.rrect(c, const Rect.fromLTWH(-14, -18, 28, 34), 5, _Ink.white);
    c.restore();
    c.drawPath(
      Path()
        ..moveTo(52, 66)
        ..quadraticBezierTo(72, 70, 82, 84)
        ..quadraticBezierTo(60, 92, 40, 84)
        ..quadraticBezierTo(44, 72, 52, 66)
        ..close(),
      _Ink.fill(_Ink.sky),
    );
    c.drawPath(
      Path()
        ..moveTo(52, 66)
        ..quadraticBezierTo(72, 70, 82, 84)
        ..quadraticBezierTo(60, 92, 40, 84)
        ..quadraticBezierTo(44, 72, 52, 66)
        ..close(),
      _Ink.line(2.6),
    );
  }

  static void _dog(Canvas c) {
    // A dog behind a fence: the fence is the reason this card is mild.
    _Ink.circle(c, const Offset(44, 46), 18, _Ink.brown);
    c.drawPath(
      Path()
        ..moveTo(30, 34)
        ..lineTo(26, 18)
        ..lineTo(40, 28)
        ..close(),
      _Ink.fill(_Ink.brown),
    );
    c.drawPath(
      Path()
        ..moveTo(58, 34)
        ..lineTo(62, 18)
        ..lineTo(48, 28)
        ..close(),
      _Ink.fill(_Ink.brown),
    );
    c.drawCircle(const Offset(38, 43), 2.6, _Ink.fill(_Ink.ink));
    c.drawCircle(const Offset(50, 43), 2.6, _Ink.fill(_Ink.ink));
    c.drawOval(
        Rect.fromCenter(
            center: const Offset(44, 54), width: 12, height: 9),
        _Ink.fill(const Color(0xFF7A4550)));
    // Fence pickets in front.
    for (var x = 14.0; x <= 86.0; x += 18) {
      _Ink.rrect(c, Rect.fromLTWH(x, 52, 10, 44), 3, _Ink.white);
    }
    c.drawLine(const Offset(10, 62), const Offset(94, 62), _Ink.line(2.6));
    // Bark marks.
    c.drawLine(const Offset(70, 30), const Offset(80, 26), _Ink.line(2.4));
    c.drawLine(const Offset(70, 38), const Offset(82, 38), _Ink.line(2.4));
  }

  static void _thunder(Canvas c) {
    c.drawPath(
      Path()
        ..addOval(const Rect.fromLTWH(16, 24, 34, 26))
        ..addOval(const Rect.fromLTWH(38, 18, 36, 30))
        ..addOval(const Rect.fromLTWH(58, 28, 28, 22)),
      _Ink.fill(const Color(0xFFCBD3DE)),
    );
    c.drawPath(
      Path()
        ..moveTo(52, 50)
        ..lineTo(40, 76)
        ..lineTo(50, 76)
        ..lineTo(42, 94)
        ..lineTo(66, 68)
        ..lineTo(54, 68)
        ..lineTo(62, 50)
        ..close(),
      _Ink.fill(_Ink.butter),
    );
    c.drawPath(
      Path()
        ..moveTo(52, 50)
        ..lineTo(40, 76)
        ..lineTo(50, 76)
        ..lineTo(42, 94)
        ..lineTo(66, 68)
        ..lineTo(54, 68)
        ..lineTo(62, 50)
        ..close(),
      _Ink.line(2.8),
    );
    // A window frame, because the whole point is that it is heard from indoors.
    c.drawRect(const Rect.fromLTWH(8, 10, 84, 84), _Ink.line(3.4));
  }

  static void _jackInBox(Canvas c) {
    _Ink.rrect(c, const Rect.fromLTWH(24, 56, 52, 38), 5, _Ink.sky);
    // Lid, flung open.
    c.save();
    c.translate(24, 56);
    c.rotate(-0.5);
    _Ink.rrect(c, const Rect.fromLTWH(0, -10, 52, 10), 3, _Ink.lav);
    c.restore();
    // Spring.
    c.drawPath(
      Path()
        ..moveTo(50, 56)
        ..lineTo(40, 48)
        ..lineTo(60, 42)
        ..lineTo(40, 36)
        ..lineTo(58, 30),
      _Ink.line(3.0),
    );
    _Ink.circle(c, const Offset(58, 22), 11, _Ink.butter);
    c.drawCircle(const Offset(54, 21), 2.2, _Ink.fill(_Ink.ink));
    c.drawCircle(const Offset(62, 21), 2.2, _Ink.fill(_Ink.ink));
  }

  static void _balloons(Canvas c) {
    const spots = [
      (Offset(30, 34), _Ink.rose),
      (Offset(54, 24), _Ink.butter),
      (Offset(74, 38), _Ink.mint),
    ];
    for (final (o, color) in spots) {
      c.drawOval(
          Rect.fromCenter(center: o, width: 30, height: 36), _Ink.fill(color));
      c.drawOval(
          Rect.fromCenter(center: o, width: 30, height: 36), _Ink.line(2.6));
      c.drawPath(
        Path()
          ..moveTo(o.dx, o.dy + 18)
          ..quadraticBezierTo(o.dx + 6, o.dy + 34, o.dx - 2, o.dy + 52),
        _Ink.line(2.0),
      );
    }
  }

  static void _towerFell(Canvas c) {
    // One block still standing, three scattered — a tower mid-collapse.
    _Ink.rrect(c, const Rect.fromLTWH(20, 68, 24, 22), 4, _Ink.mint);
    c.save();
    c.translate(58, 78);
    c.rotate(0.5);
    _Ink.rrect(c, const Rect.fromLTWH(-12, -11, 24, 22), 4, _Ink.sky);
    c.restore();
    c.save();
    c.translate(78, 56);
    c.rotate(-0.8);
    _Ink.rrect(c, const Rect.fromLTWH(-12, -11, 24, 22), 4, _Ink.rose);
    c.restore();
    c.save();
    c.translate(44, 40);
    c.rotate(0.9);
    _Ink.rrect(c, const Rect.fromLTWH(-12, -11, 24, 22), 4, _Ink.butter);
    c.restore();
    c.drawLine(const Offset(10, 92), const Offset(92, 92), _Ink.line(2.6));
  }

  static void _puzzle(Canvas c) {
    // A board with a gap, and a piece that will not go in.
    _Ink.rrect(c, const Rect.fromLTWH(14, 40, 48, 48), 5, _Ink.lav);
    c.drawRect(const Rect.fromLTWH(30, 56, 20, 20), _Ink.fill(_Ink.white));
    c.drawRect(const Rect.fromLTWH(30, 56, 20, 20), _Ink.line(2.6));
    c.save();
    c.translate(76, 34);
    c.rotate(0.6);
    _Ink.rrect(c, const Rect.fromLTWH(-12, -12, 24, 24), 4, _Ink.peach);
    c.restore();
    // Two short strain marks, the picture-book way of saying "it will not go".
    c.drawLine(const Offset(58, 26), const Offset(64, 20), _Ink.line(2.4));
    c.drawLine(const Offset(90, 26), const Offset(96, 20), _Ink.line(2.4));
  }
}

/// Draws a schematic caring-response picture for tier 3's second step.
class ResponseArtPainter {
  ResponseArtPainter._();

  static void paint(
      Canvas canvas, ResponseArt art, Offset origin, double size) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(size / 100, size / 100);

    switch (art) {
      case ResponseArt.hug:
        _hug(canvas);
        break;
      case ResponseArt.share:
        _share(canvas);
        break;
      case ResponseArt.sorry:
        _sorry(canvas);
        break;
      case ResponseArt.clap:
        _clap(canvas);
        break;
    }

    canvas.restore();
  }

  static void _hug(Canvas c) {
    // Two figures leaning together, arms across each other's backs.
    _Ink.rrect(c, const Rect.fromLTWH(16, 48, 34, 44), 14, _Ink.mint);
    _Ink.rrect(c, const Rect.fromLTWH(50, 48, 34, 44), 14, _Ink.sky);
    _Ink.circle(c, const Offset(33, 34), 15, _Ink.skin);
    _Ink.circle(c, const Offset(67, 34), 15, _Ink.skin);
    c.drawPath(
      Path()
        ..moveTo(22, 60)
        ..quadraticBezierTo(50, 74, 78, 60),
      _Ink.line(4.0),
    );
    for (final dx in [28.0, 38.0]) {
      c.drawCircle(Offset(dx, 34), 2.2, _Ink.fill(_Ink.ink));
    }
    for (final dx in [62.0, 72.0]) {
      c.drawCircle(Offset(dx, 34), 2.2, _Ink.fill(_Ink.ink));
    }
  }

  static void _share(Canvas c) {
    // An open palm holding a toy out toward the other side of the card.
    c.drawPath(
      Path()
        ..moveTo(14, 76)
        ..quadraticBezierTo(14, 58, 34, 58)
        ..lineTo(58, 58)
        ..quadraticBezierTo(70, 58, 70, 68)
        ..quadraticBezierTo(70, 80, 54, 80)
        ..lineTo(28, 80)
        ..quadraticBezierTo(14, 82, 14, 76)
        ..close(),
      _Ink.fill(_Ink.skin),
    );
    c.drawPath(
      Path()
        ..moveTo(14, 76)
        ..quadraticBezierTo(14, 58, 34, 58)
        ..lineTo(58, 58)
        ..quadraticBezierTo(70, 58, 70, 68)
        ..quadraticBezierTo(70, 80, 54, 80)
        ..lineTo(28, 80)
        ..quadraticBezierTo(14, 82, 14, 76)
        ..close(),
      _Ink.line(),
    );
    _Ink.circle(c, const Offset(44, 38), 17, _Ink.rose);
    c.drawPath(
      Path()
        ..moveTo(29, 34)
        ..quadraticBezierTo(44, 44, 59, 34),
      _Ink.line(2.4),
    );
    // A motion arrow: the toy is being offered, not merely held.
    c.drawPath(
      Path()
        ..moveTo(72, 34)
        ..lineTo(90, 34)
        ..moveTo(83, 27)
        ..lineTo(90, 34)
        ..lineTo(83, 41),
      _Ink.line(3.0),
    );
  }

  static void _sorry(Canvas c) {
    // A child with a hand on their chest and a small speech bubble: the gesture
    // carries it for a pre-reader, and the bubble says a word is being said.
    _Ink.circle(c, const Offset(38, 46), 20, _Ink.skin);
    _Ink.rrect(c, const Rect.fromLTWH(18, 68, 40, 28), 12, _Ink.mint);
    c.drawCircle(const Offset(32, 46), 2.6, _Ink.fill(_Ink.ink));
    c.drawCircle(const Offset(44, 46), 2.6, _Ink.fill(_Ink.ink));
    c.drawPath(
      Path()
        ..moveTo(31, 55)
        ..quadraticBezierTo(38, 51, 45, 55),
      _Ink.line(2.6),
    );
    // Hand on the chest.
    _Ink.circle(c, const Offset(44, 78), 8, _Ink.skin);
    // Speech bubble with a heart in it.
    _Ink.rrect(c, const Rect.fromLTWH(60, 18, 34, 26), 9, _Ink.white);
    c.drawPath(
      Path()
        ..moveTo(66, 42)
        ..lineTo(60, 52)
        ..lineTo(74, 44)
        ..close(),
      _Ink.fill(_Ink.white),
    );
    c.drawPath(
      Path()
        ..moveTo(77, 38)
        ..quadraticBezierTo(64, 30, 71, 24)
        ..quadraticBezierTo(77, 21, 77, 28)
        ..quadraticBezierTo(77, 21, 83, 24)
        ..quadraticBezierTo(90, 30, 77, 38)
        ..close(),
      _Ink.fill(_Ink.rose),
    );
  }

  static void _clap(Canvas c) {
    // Two hands meeting, with the little burst lines that read as sound.
    for (final flip in [false, true]) {
      c.save();
      if (flip) {
        c.translate(100, 0);
        c.scale(-1, 1);
      }
      c.drawPath(
        Path()
          ..moveTo(18, 44)
          ..quadraticBezierTo(12, 62, 26, 74)
          ..quadraticBezierTo(38, 84, 46, 74)
          ..lineTo(46, 44)
          ..quadraticBezierTo(34, 34, 18, 44)
          ..close(),
        _Ink.fill(_Ink.skin),
      );
      c.drawPath(
        Path()
          ..moveTo(18, 44)
          ..quadraticBezierTo(12, 62, 26, 74)
          ..quadraticBezierTo(38, 84, 46, 74)
          ..lineTo(46, 44)
          ..quadraticBezierTo(34, 34, 18, 44)
          ..close(),
        _Ink.line(),
      );
      c.restore();
    }
    final burst = _Ink.line(3.0);
    c.drawLine(const Offset(50, 30), const Offset(50, 18), burst);
    c.drawLine(const Offset(30, 34), const Offset(22, 24), burst);
    c.drawLine(const Offset(70, 34), const Offset(78, 24), burst);
  }
}
