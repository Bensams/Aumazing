import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../../config/game_motion.dart';

/// Which way the star is facing the child right now.
enum StarState {
  /// Eyes closed, dim. The child must not tap.
  asleep,

  /// Eyes open, bright, haloed. The tap window is open.
  awake,

  /// Briefly held after a correct tap, before the next trial.
  happy,
}

/// The single object the child watches in "Hintay!".
///
/// Deliberately one object on an otherwise empty canvas: the whole task is
/// *when* to tap, so anything else on screen is a competing demand on the
/// attention we are trying to measure.
///
/// The wake cue is carried on four channels at once — fill colour, the eyes
/// opening, a halo, and (from the screen wrapper) a sound. A child who misses
/// any one of them still gets the cue, which matters when the population
/// includes children with colour-vision or hearing differences.
class SleepyStar extends PositionComponent {
  SleepyStar({required Vector2 position, required double radius})
      : _radius = radius,
        super(
          position: position,
          size: Vector2.all(radius * 2),
          anchor: Anchor.center,
        );

  final double _radius;

  StarState _state = StarState.asleep;
  StarState get state => _state;

  /// Drives the sleep breathing and the wake pop.
  double _time = 0;

  /// Seconds since the last state change, used for the wake pop only.
  double _sinceChange = 0;

  static const Color _asleepFill = Color(0xFFD4C5E8); // AppColors.lavender
  static const Color _awakeFill = Color(0xFFFFF4C4); // AppColors.butterYellow
  static const Color _happyFill = Color(0xFFB8E8D4); // AppColors.mint
  static const Color _ink = Color(0xFF5A5A6B); // AppColors.foreground

  void setState(StarState next) {
    if (_state == next) return;
    _state = next;
    _sinceChange = 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    _sinceChange += dt;
  }

  /// Slow breathing while asleep (~0.24 Hz) — far below any photosensitivity
  /// threshold, and slow enough to read as "resting" rather than "pulsing".
  double get _scale {
    if (GameMotion.reduced) return 1.0;
    switch (_state) {
      case StarState.asleep:
        return 1.0 + 0.035 * math.sin(_time * 1.5);
      case StarState.awake:
      case StarState.happy:
        // A single settle from 1.10 → 1.05 over ~0.35s. No loop: once the cue
        // has landed, continued movement would only pull focus off the tap.
        final t = math.min(_sinceChange / 0.35, 1.0);
        return 1.10 - 0.05 * _easeOut(t);
    }
  }

  Color get _fill {
    switch (_state) {
      case StarState.asleep:
        return _asleepFill;
      case StarState.awake:
        return _awakeFill;
      case StarState.happy:
        return _happyFill;
    }
  }

  /// True when the star currently accepts a tap as correct.
  bool get isTappable => _state == StarState.awake;

  /// Distance from the star's centre, for hit testing in the parent game.
  double distanceFrom(Vector2 point) => (point - position).length;

  double get radius => _radius;

  @override
  void render(Canvas canvas) {
    final c = Offset(size.x / 2, size.y / 2);
    final s = _scale;

    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(s, s);
    canvas.translate(-c.dx, -c.dy);

    // Halo — only while awake, and only as a soft radial wash rather than a
    // ring, so it reads as "lit up" instead of "targeted".
    if (_state != StarState.asleep) {
      final haloPaint = Paint()
        ..shader = Gradient.radial(
          c,
          _radius * 1.5,
          const [Color(0x99FFF4C4), Color(0x00FFF4C4)],
          const [0.55, 1.0],
        );
      canvas.drawCircle(c, _radius * 1.5, haloPaint);
    }

    final path = _starPath(c, _radius);

    canvas.drawPath(path, Paint()..color = _fill);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0x295A5A6B),
    );

    _drawFace(canvas, c);
    canvas.restore();
  }

  /// A five-pointed star. Drawn as a path rather than an asset so the object
  /// recolours per state without shipping three images.
  Path _starPath(Offset c, double r) {
    final path = Path();
    const points = 5;
    final inner = r * 0.46;
    for (var i = 0; i < points * 2; i++) {
      final radius = i.isEven ? r : inner;
      final angle = -math.pi / 2 + i * math.pi / points;
      final x = c.dx + radius * math.cos(angle);
      final y = c.dy + radius * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  void _drawFace(Canvas canvas, Offset c) {
    final eyeDx = _radius * 0.22;
    final eyeY = c.dy - _radius * 0.02;
    final eyePaint = Paint()..color = _ink;
    final lidPaint = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = _radius * 0.055
      ..strokeCap = StrokeCap.round;

    if (_state == StarState.asleep) {
      // Closed lids: two gentle downward arcs.
      for (final dx in [-eyeDx, eyeDx]) {
        final path = Path()
          ..moveTo(c.dx + dx - _radius * 0.1, eyeY)
          ..quadraticBezierTo(
            c.dx + dx,
            eyeY + _radius * 0.09,
            c.dx + dx + _radius * 0.1,
            eyeY,
          );
        canvas.drawPath(path, lidPaint);
      }
      return;
    }

    for (final dx in [-eyeDx, eyeDx]) {
      canvas.drawCircle(Offset(c.dx + dx, eyeY), _radius * 0.075, eyePaint);
    }

    if (_state == StarState.happy) {
      // A small smile, only on success. The asleep and awake faces stay
      // neutral so the child never has to read emotion to play.
      final smile = Path()
        ..moveTo(c.dx - _radius * 0.16, c.dy + _radius * 0.2)
        ..quadraticBezierTo(
          c.dx,
          c.dy + _radius * 0.34,
          c.dx + _radius * 0.16,
          c.dy + _radius * 0.2,
        );
      canvas.drawPath(smile, lidPaint);
    }
  }
}

/// Standard ease-out cubic on a 0–1 input. A local helper rather than
/// `Curves.easeOut`, so this file keeps its `dart:ui`-only import surface.
double _easeOut(double t) {
  final inv = 1 - t;
  return 1 - inv * inv * inv;
}
