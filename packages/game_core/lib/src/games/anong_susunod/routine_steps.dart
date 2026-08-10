import 'dart:math' as math;
import 'dart:ui';

import 'package:shared_ui/shared_ui.dart';

/// One step of an everyday routine — a single card in the visual schedule.
///
/// The illustration is drawn from paths rather than shipped as an image so a
/// card recolours with the child's palette, stays crisp at any card size, and
/// costs nothing in bundle weight. Fourteen raster assets would also have to be
/// redrawn the day the art style changes; these do not.
class RoutineStep {
  const RoutineStep(this.id, this.art, this.en, this.tl, this.ceb);

  /// Stable identifier, also used in analytics round data.
  final String id;

  /// Which illustration to paint.
  final RoutineArt art;

  final String en;
  final String tl;
  final String ceb;

  String label(GameLanguage language) {
    switch (language) {
      case GameLanguage.tagalog:
        return tl;
      case GameLanguage.cebuano:
        return ceb;
      case GameLanguage.english:
        return en;
    }
  }
}

/// The illustrations available to routine cards.
enum RoutineArt {
  wake,
  brushTeeth,
  breakfast,
  school,
  washHands,
  sitAtTable,
  eat,
  clearPlate,
  bath,
  pajamas,
  sleep,
  getToy,
  play,
  putAway,
}

/// A named routine: four steps in their correct order.
class Routine {
  const Routine(this.id, this.en, this.tl, this.ceb, this.steps);

  final String id;
  final String en;
  final String tl;
  final String ceb;
  final List<RoutineStep> steps;

  String title(GameLanguage language) {
    switch (language) {
      case GameLanguage.tagalog:
        return tl;
      case GameLanguage.cebuano:
        return ceb;
      case GameLanguage.english:
        return en;
    }
  }
}

/// The four routines, one per round.
///
/// Chosen because every one of them is a real sequence a Filipino 2–6 year old
/// lives through daily. A routine the child already performs is a routine they
/// can be *reminded* of — which is what makes this both an assessment probe and
/// a functional-skills intervention, rather than an abstract ordering puzzle.
///
/// Translations are drafts pending native-speaker review; see the note in
/// docs/ before these ship to a child.
const List<Routine> kRoutines = [
  Routine('umaga', 'Morning', 'Umaga', 'Buntag', [
    RoutineStep('wake', RoutineArt.wake, 'Wake up', 'Gumising', 'Pagmata'),
    RoutineStep('brush', RoutineArt.brushTeeth, 'Brush teeth', 'Magsipilyo',
        'Manepilyo'),
    RoutineStep('breakfast', RoutineArt.breakfast, 'Eat breakfast',
        'Kumain ng almusal', 'Mokaon og pamahaw'),
    RoutineStep('school', RoutineArt.school, 'Go to school',
        'Pumasok sa paaralan', 'Moadto sa eskwelahan'),
  ]),
  Routine('kainan', 'Mealtime', 'Kainan', 'Pagkaon', [
    RoutineStep('wash', RoutineArt.washHands, 'Wash your hands',
        'Maghugas ng kamay', 'Manghugas ug kamot'),
    RoutineStep('sit', RoutineArt.sitAtTable, 'Sit at the table',
        'Umupo sa mesa', 'Molingkod sa lamesa'),
    RoutineStep('eat', RoutineArt.eat, 'Eat', 'Kumain', 'Mokaon'),
    RoutineStep('clear', RoutineArt.clearPlate, 'Clear the plate',
        'Ligpitin ang plato', 'Hiposa ang plato'),
  ]),
  Routine('gabi', 'Bedtime', 'Gabi', 'Gabii', [
    RoutineStep('bath', RoutineArt.bath, 'Take a bath', 'Maligo', 'Maligo'),
    RoutineStep('pajamas', RoutineArt.pajamas, 'Put on pajamas',
        'Magsuot ng pajama', 'Mosul-ob og pajama'),
    RoutineStep('brush', RoutineArt.brushTeeth, 'Brush teeth', 'Magsipilyo',
        'Manepilyo'),
    RoutineStep('sleep', RoutineArt.sleep, 'Sleep', 'Matulog', 'Matulog'),
  ]),
  Routine('laro', 'Playtime', 'Laro', 'Dula', [
    RoutineStep('toy', RoutineArt.getToy, 'Get the toy', 'Kunin ang laruan',
        'Kuhaa ang dulaan'),
    RoutineStep('play', RoutineArt.play, 'Play', 'Maglaro', 'Magdula'),
    RoutineStep('away', RoutineArt.putAway, 'Put the toy away',
        'Ibalik ang laruan', 'Ihipos ang dulaan'),
    RoutineStep('wash', RoutineArt.washHands, 'Wash your hands',
        'Maghugas ng kamay', 'Manghugas ug kamot'),
  ]),
];

/// Paints a routine illustration into a [size] × [size] box at [origin].
///
/// Every illustration is built from the same small vocabulary — filled pastel
/// shapes, one dark outline weight, no gradients, no texture. Consistency
/// across the set matters more than any individual drawing: TEACCH structuring
/// is undermined by cards that each look like they came from a different book.
class RoutineArtPainter {
  RoutineArtPainter._();

  static const Color _ink = Color(0xFF3F3B4A);
  static const Color _skin = Color(0xFFFFD9BE);
  static const Color _mint = Color(0xFFB8E8D4);
  static const Color _sky = Color(0xFFB8D8F0);
  static const Color _peach = Color(0xFFFFD4C4);
  static const Color _butter = Color(0xFFFFF4C4);
  static const Color _lav = Color(0xFFD4C5E8);
  static const Color _white = Color(0xFFFFFDF8);

  static void paint(
    Canvas canvas,
    RoutineArt art,
    Offset origin,
    double size,
  ) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(size / 100, size / 100);

    switch (art) {
      case RoutineArt.wake:
        _wake(canvas);
        break;
      case RoutineArt.brushTeeth:
        _brushTeeth(canvas);
        break;
      case RoutineArt.breakfast:
        _breakfast(canvas);
        break;
      case RoutineArt.school:
        _school(canvas);
        break;
      case RoutineArt.washHands:
        _washHands(canvas);
        break;
      case RoutineArt.sitAtTable:
        _sitAtTable(canvas);
        break;
      case RoutineArt.eat:
        _eat(canvas);
        break;
      case RoutineArt.clearPlate:
        _clearPlate(canvas);
        break;
      case RoutineArt.bath:
        _bath(canvas);
        break;
      case RoutineArt.pajamas:
        _pajamas(canvas);
        break;
      case RoutineArt.sleep:
        _sleep(canvas);
        break;
      case RoutineArt.getToy:
        _getToy(canvas);
        break;
      case RoutineArt.play:
        _play(canvas);
        break;
      case RoutineArt.putAway:
        _putAway(canvas);
        break;
    }

    canvas.restore();
  }

  // ── Drawing helpers ──────────────────────────────────────────────────

  static Paint _fill(Color c) => Paint()..color = c;

  static Paint _line([double w = 3.2]) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = _ink;

  static void _rrect(Canvas c, Rect r, double radius, Color fill) {
    final rr = RRect.fromRectXY(r, radius, radius);
    c.drawRRect(rr, _fill(fill));
    c.drawRRect(rr, _line());
  }

  static void _circle(Canvas c, Offset o, double r, Color fill) {
    c.drawCircle(o, r, _fill(fill));
    c.drawCircle(o, r, _line());
  }

  /// A simple face: two eyes, and a mouth whose curve is set by [smile]
  /// (positive = happy, 0 = neutral, negative = sleeping/closed).
  static void _face(Canvas c, Offset o, double r, {double smile = 1}) {
    final eyeDx = r * 0.34;
    if (smile < 0) {
      // Closed lids.
      for (final dx in [-eyeDx, eyeDx]) {
        c.drawPath(
          Path()
            ..moveTo(o.dx + dx - r * 0.16, o.dy - r * 0.05)
            ..quadraticBezierTo(o.dx + dx, o.dy + r * 0.12,
                o.dx + dx + r * 0.16, o.dy - r * 0.05),
          _line(2.6),
        );
      }
    } else {
      for (final dx in [-eyeDx, eyeDx]) {
        c.drawCircle(Offset(o.dx + dx, o.dy - r * 0.06), r * 0.11, _fill(_ink));
      }
    }
    if (smile != 0) {
      c.drawPath(
        Path()
          ..moveTo(o.dx - r * 0.26, o.dy + r * 0.3)
          ..quadraticBezierTo(
              o.dx, o.dy + r * 0.3 + r * 0.26 * smile.abs(), o.dx + r * 0.26,
              o.dy + r * 0.3),
        _line(2.6),
      );
    }
  }

  // ── Illustrations ────────────────────────────────────────────────────

  static void _wake(Canvas c) {
    // Sun on the horizon behind a child stretching awake.
    _circle(c, const Offset(72, 30), 15, _butter);
    for (var i = 0; i < 8; i++) {
      final a = i * 3.14159 / 4;
      c.drawLine(
        Offset(72 + 19 * _cos(a), 30 + 19 * _sin(a)),
        Offset(72 + 25 * _cos(a), 30 + 25 * _sin(a)),
        _line(2.6),
      );
    }
    _circle(c, const Offset(38, 46), 17, _skin);
    _face(c, const Offset(38, 46), 17);
    // Arms up — the universal "just woke" pose.
    c.drawPath(
      Path()
        ..moveTo(24, 66)
        ..lineTo(14, 44)
        ..moveTo(52, 66)
        ..lineTo(62, 48),
      _line(4),
    );
    _rrect(c, const Rect.fromLTWH(22, 64, 32, 26), 9, _mint);
  }

  static void _brushTeeth(Canvas c) {
    _circle(c, const Offset(42, 44), 20, _skin);
    // Open mouth showing teeth — the thing being brushed.
    final mouth = Rect.fromCenter(
        center: const Offset(42, 54), width: 20, height: 13);
    c.drawOval(mouth, _fill(_white));
    c.drawOval(mouth, _line(2.6));
    c.drawLine(const Offset(33, 50), const Offset(51, 50), _line(2.2));
    for (final dx in [-6.5, 6.5]) {
      c.drawCircle(Offset(42 + dx, 38), 2.2, _fill(_ink));
    }
    // Toothbrush, bristles at the mouth.
    c.save();
    c.translate(58, 60);
    c.rotate(-0.6);
    _rrect(c, const Rect.fromLTWH(0, -5, 34, 10), 5, _sky);
    _rrect(c, const Rect.fromLTWH(-13, -7, 15, 14), 4, _white);
    c.restore();
  }

  static void _breakfast(Canvas c) {
    _rrect(c, const Rect.fromLTWH(14, 62, 72, 8), 4, _lav); // table
    // Bowl with steam.
    final bowl = Path()
      ..moveTo(26, 44)
      ..lineTo(74, 44)
      ..quadraticBezierTo(70, 64, 50, 64)
      ..quadraticBezierTo(30, 64, 26, 44)
      ..close();
    c.drawPath(bowl, _fill(_mint));
    c.drawPath(bowl, _line());
    c.drawLine(const Offset(24, 44), const Offset(76, 44), _line());
    for (final x in [42.0, 50.0, 58.0]) {
      c.drawPath(
        Path()
          ..moveTo(x, 34)
          ..quadraticBezierTo(x + 5, 28, x, 22),
        _line(2.6),
      );
    }
  }

  static void _school(Canvas c) {
    _rrect(c, const Rect.fromLTWH(20, 44, 60, 40), 5, _peach);
    final roof = Path()
      ..moveTo(14, 44)
      ..lineTo(50, 20)
      ..lineTo(86, 44)
      ..close();
    c.drawPath(roof, _fill(_sky));
    c.drawPath(roof, _line());
    _rrect(c, const Rect.fromLTWH(42, 60, 16, 24), 3, _butter); // door
    _rrect(c, const Rect.fromLTWH(26, 54, 12, 12), 2, _white);
    _rrect(c, const Rect.fromLTWH(62, 54, 12, 12), 2, _white);
    c.drawLine(const Offset(50, 20), const Offset(50, 10), _line(2.6));
    _rrect(c, const Rect.fromLTWH(50, 8, 14, 9), 2, _mint); // flag
  }

  static void _washHands(Canvas c) {
    // Tap and running water over two hands.
    _rrect(c, const Rect.fromLTWH(16, 20, 10, 26), 4, _lav);
    _rrect(c, const Rect.fromLTWH(16, 20, 40, 9), 4, _lav);
    c.drawLine(const Offset(52, 30), const Offset(52, 42), _line(3.6));
    for (final o in [const Offset(48, 46), const Offset(56, 52)]) {
      c.drawPath(
        Path()
          ..moveTo(o.dx, o.dy)
          ..quadraticBezierTo(o.dx + 4, o.dy + 6, o.dx, o.dy + 11),
        _line(2.6)..color = _sky,
      );
    }
    _circle(c, const Offset(40, 70), 15, _skin);
    _circle(c, const Offset(60, 72), 14, _skin);
    // Bubbles.
    for (final b in [
      const Offset(30, 50),
      const Offset(68, 58),
      const Offset(24, 62)
    ]) {
      _circle(c, b, 4.5, _white);
    }
  }

  static void _sitAtTable(Canvas c) {
    _rrect(c, const Rect.fromLTWH(10, 52, 80, 8), 4, _lav); // table top
    c.drawLine(const Offset(20, 60), const Offset(20, 86), _line(3.6));
    c.drawLine(const Offset(80, 60), const Offset(80, 86), _line(3.6));
    // Child seated behind it.
    _circle(c, const Offset(58, 30), 15, _skin);
    _face(c, const Offset(58, 30), 15);
    _rrect(c, const Rect.fromLTWH(44, 44, 28, 12), 6, _mint);
    // Chair back.
    _rrect(c, const Rect.fromLTWH(76, 26, 9, 34), 4, _peach);
  }

  static void _eat(Canvas c) {
    _circle(c, const Offset(50, 52), 26, _white);
    _circle(c, const Offset(50, 52), 17, _butter);
    // Fork and spoon either side.
    c.drawLine(const Offset(16, 32), const Offset(16, 74), _line(3.4));
    c.drawLine(const Offset(11, 32), const Offset(11, 44), _line(2.4));
    c.drawLine(const Offset(21, 32), const Offset(21, 44), _line(2.4));
    c.drawLine(const Offset(84, 44), const Offset(84, 74), _line(3.4));
    final spoon =
        Rect.fromCenter(center: const Offset(84, 36), width: 13, height: 18);
    c.drawOval(spoon, _fill(_white));
    c.drawOval(spoon, _line(2.6));
  }

  static void _clearPlate(Canvas c) {
    // Plate being carried to the sink — arrow shows the direction of travel.
    _circle(c, const Offset(34, 46), 20, _white);
    _circle(c, const Offset(34, 46), 12, _mint);
    c.drawPath(
      Path()
        ..moveTo(56, 46)
        ..lineTo(74, 46)
        ..moveTo(67, 39)
        ..lineTo(74, 46)
        ..lineTo(67, 53),
      _line(3.4),
    );
    _rrect(c, const Rect.fromLTWH(72, 58, 22, 24), 4, _sky); // sink/basin
    c.drawLine(const Offset(72, 66), const Offset(94, 66), _line(2.4));
    _rrect(c, const Rect.fromLTWH(8, 70, 60, 8), 4, _lav);
  }

  static void _bath(Canvas c) {
    final tub = Path()
      ..moveTo(14, 50)
      ..lineTo(86, 50)
      ..quadraticBezierTo(84, 82, 50, 82)
      ..quadraticBezierTo(16, 82, 14, 50)
      ..close();
    c.drawPath(tub, _fill(_sky));
    c.drawPath(tub, _line());
    c.drawLine(const Offset(10, 50), const Offset(90, 50), _line());
    // Foam and a rubber duck: the recognisable bath cue for this age group.
    for (final b in [
      const Offset(30, 44),
      const Offset(44, 40),
      const Offset(60, 43)
    ]) {
      _circle(c, b, 7, _white);
    }
    _circle(c, const Offset(68, 38), 9, _butter);
    c.drawCircle(const Offset(71, 36), 1.8, _fill(_ink));
    c.drawPath(
      Path()
        ..moveTo(76, 39)
        ..lineTo(83, 41)
        ..lineTo(76, 43)
        ..close(),
      _fill(_peach),
    );
  }

  static void _pajamas(Canvas c) {
    // A one-piece laid flat — reads as clothing without needing a body.
    final top = Path()
      ..moveTo(34, 26)
      ..lineTo(66, 26)
      ..lineTo(80, 40)
      ..lineTo(70, 50)
      ..lineTo(66, 46)
      ..lineTo(66, 84)
      ..lineTo(34, 84)
      ..lineTo(34, 46)
      ..lineTo(30, 50)
      ..lineTo(20, 40)
      ..close();
    c.drawPath(top, _fill(_lav));
    c.drawPath(top, _line());
    // Stars on the fabric — a pyjama pattern children recognise.
    for (final s in [
      const Offset(44, 56),
      const Offset(58, 66),
      const Offset(46, 74)
    ]) {
      c.drawCircle(s, 3.2, _fill(_butter));
    }
    c.drawLine(const Offset(50, 84), const Offset(50, 62), _line(2.2));
  }

  static void _sleep(Canvas c) {
    _rrect(c, const Rect.fromLTWH(12, 52, 76, 26), 6, _lav); // bed
    _rrect(c, const Rect.fromLTWH(12, 44, 18, 20), 6, _white); // pillow
    _circle(c, const Offset(30, 50), 12, _skin);
    _face(c, const Offset(30, 50), 12, smile: -1);
    _rrect(c, const Rect.fromLTWH(38, 54, 48, 18), 6, _mint); // blanket
    // zzz
    for (var i = 0; i < 3; i++) {
      final s = 8.0 - i * 2;
      final x = 56.0 + i * 12;
      final y = 34.0 - i * 10;
      c.drawPath(
        Path()
          ..moveTo(x, y)
          ..lineTo(x + s, y)
          ..lineTo(x, y + s)
          ..lineTo(x + s, y + s),
        _line(2.4),
      );
    }
  }

  static void _getToy(Canvas c) {
    // A hand reaching for a ball on a shelf.
    _circle(c, const Offset(62, 40), 20, _peach);
    c.drawPath(
      Path()
        ..moveTo(44, 34)
        ..quadraticBezierTo(62, 46, 80, 34),
      _line(2.6),
    );
    c.drawPath(
      Path()
        ..moveTo(44, 46)
        ..quadraticBezierTo(62, 34, 80, 46),
      _line(2.6),
    );
    _rrect(c, const Rect.fromLTWH(16, 62, 24, 20), 8, _skin); // hand
    c.drawPath(
      Path()
        ..moveTo(40, 68)
        ..lineTo(52, 60),
      _line(3.4),
    );
  }

  static void _play(Canvas c) {
    // Blocks stacked — solitary constructive play.
    _rrect(c, const Rect.fromLTWH(26, 58, 24, 24), 5, _mint);
    _rrect(c, const Rect.fromLTWH(52, 58, 24, 24), 5, _sky);
    _rrect(c, const Rect.fromLTWH(39, 34, 24, 24), 5, _peach);
    c.drawCircle(const Offset(38, 70), 3.2, _fill(_ink));
    c.drawCircle(const Offset(64, 70), 3.2, _fill(_ink));
    c.drawCircle(const Offset(51, 46), 3.2, _fill(_ink));
  }

  static void _putAway(Canvas c) {
    // Toy box with the lid open and a ball dropping in.
    _rrect(c, const Rect.fromLTWH(20, 52, 60, 34), 6, _peach);
    c.drawPath(
      Path()
        ..moveTo(20, 52)
        ..lineTo(30, 36)
        ..lineTo(90, 36)
        ..lineTo(80, 52),
      _line(),
    );
    _circle(c, const Offset(52, 26), 11, _mint);
    c.drawPath(
      Path()
        ..moveTo(52, 40)
        ..lineTo(52, 48)
        ..moveTo(47, 43)
        ..lineTo(52, 48)
        ..lineTo(57, 43),
      _line(2.8),
    );
    c.drawLine(const Offset(34, 66), const Offset(66, 66), _line(2.2));
  }

  static double _cos(double a) => math.cos(a);
  static double _sin(double a) => math.sin(a);
}
