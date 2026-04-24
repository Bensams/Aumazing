import 'dart:math';
import 'package:flutter/material.dart';

/// The type of sparkle particle element.
enum _ParticleType {
  /// 5-pointed star (various sizes).
  star,

  /// 4-pointed diamond/sparkle shape (✦).
  diamond,

  /// Elongated oval/streak radiating outward.
  streak,

  /// Small circular dot.
  dot,
}

/// Data class describing a single sparkle particle.
class _SparkleParticle {
  /// Angle from center in radians.
  final double angle;

  /// Normalized distance from center (0..1).
  final double distance;

  /// Base size of the particle.
  final double size;

  /// Type of particle to render.
  final _ParticleType type;

  /// Initial rotation offset in radians.
  final double rotation;

  /// Stagger delay factor (0..1) mapped to 0-200ms.
  final double staggerDelay;

  /// Color of this particle.
  final Color color;

  /// Opacity multiplier (for streaks/dots with transparency).
  final double opacity;

  const _SparkleParticle({
    required this.angle,
    required this.distance,
    required this.size,
    required this.type,
    required this.rotation,
    required this.staggerDelay,
    required this.color,
    required this.opacity,
  });
}

/// A sparkle burst effect with a central golden star and scattered particles.
///
/// Renders a single large 5-pointed star in the center surrounded by
/// smaller stars, diamond sparkles, elongated streaks, and dots that
/// burst outward from the center in a circular pattern.
///
/// Animation phases:
/// 1. Scatter (0-400ms): elements burst outward from center, scaling up
/// 2. Hold (400-800ms): elements stay at final positions
/// 3. Fade (800-1200ms): everything fades out together
///
/// Total animation duration: ~1200 ms.
class ThreeStarSparkle extends StatefulWidget {
  /// The screen position where the sparkle should appear (center point).
  final Offset position;

  /// Called when the animation finishes.
  final VoidCallback? onComplete;

  /// The overall size of the sparkle arrangement.
  final double size;

  const ThreeStarSparkle({
    super.key,
    required this.position,
    this.onComplete,
    this.size = 200.0,
  });

  @override
  State<ThreeStarSparkle> createState() => _ThreeStarSparkleState();
}

class _ThreeStarSparkleState extends State<ThreeStarSparkle>
    with TickerProviderStateMixin {
  // ── Animation controllers ───────────────────────────────────────────
  late final AnimationController _scatterController;
  late final AnimationController _holdController;
  late final AnimationController _fadeController;

  // ── Animations ──────────────────────────────────────────────────────
  late final Animation<double> _scatterProgress;
  late final Animation<double> _fadeOut;

  final _random = Random();
  late final List<_SparkleParticle> _particles;

  // ── Color palette ───────────────────────────────────────────────────
  static const _mainGold = Color(0xFFE8B730);
  static const _lightGold = Color(0xFFF0C850);
  static const _darkGold = Color(0xFFD4A020);
  static const _creamStreak = Color(0xFFF5E6B0);
  static const _creamDot = Color(0xFFF5E8C0);

  @override
  void initState() {
    super.initState();

    // Scatter phase: 0-400ms — elements burst outward
    _scatterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scatterProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scatterController, curve: Curves.easeOutCubic),
    );

    // Hold phase: 400-800ms — elements stay at final positions
    _holdController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // Fade phase: 800-1200ms — everything fades out
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );

    // Generate all particle data
    _particles = _generateParticles();

    // Start the animation sequence
    _startSequence();
  }

  List<_SparkleParticle> _generateParticles() {
    final particles = <_SparkleParticle>[];

    // ~8-10 smaller 5-pointed stars
    final starCount = 8 + _random.nextInt(3);
    for (var i = 0; i < starCount; i++) {
      final color = _random.nextBool() ? _mainGold : _lightGold;
      particles.add(_SparkleParticle(
        angle: _random.nextDouble() * 2 * pi,
        distance: 0.3 + _random.nextDouble() * 0.7,
        size: 4.0 + _random.nextDouble() * 8.0,
        type: _ParticleType.star,
        rotation: _random.nextDouble() * 2 * pi,
        staggerDelay: _random.nextDouble(),
        color: color,
        opacity: 1.0,
      ));
    }

    // ~6-8 four-pointed diamond/sparkle shapes
    final diamondCount = 6 + _random.nextInt(3);
    for (var i = 0; i < diamondCount; i++) {
      particles.add(_SparkleParticle(
        angle: _random.nextDouble() * 2 * pi,
        distance: 0.25 + _random.nextDouble() * 0.75,
        size: 3.0 + _random.nextDouble() * 6.0,
        type: _ParticleType.diamond,
        rotation: _random.nextDouble() * pi / 4,
        staggerDelay: _random.nextDouble(),
        color: _darkGold,
        opacity: 1.0,
      ));
    }

    // ~6 elongated oval/streak shapes
    for (var i = 0; i < 6; i++) {
      particles.add(_SparkleParticle(
        angle: _random.nextDouble() * 2 * pi,
        distance: 0.35 + _random.nextDouble() * 0.65,
        size: 6.0 + _random.nextDouble() * 10.0,
        type: _ParticleType.streak,
        rotation: 0, // rotation is computed from angle in painter
        staggerDelay: _random.nextDouble(),
        color: _creamStreak,
        opacity: 0.6,
      ));
    }

    // ~6-8 small circular dots
    final dotCount = 6 + _random.nextInt(3);
    for (var i = 0; i < dotCount; i++) {
      particles.add(_SparkleParticle(
        angle: _random.nextDouble() * 2 * pi,
        distance: 0.2 + _random.nextDouble() * 0.8,
        size: 1.5 + _random.nextDouble() * 3.0,
        type: _ParticleType.dot,
        rotation: 0,
        staggerDelay: _random.nextDouble(),
        color: _creamDot,
        opacity: 0.5,
      ));
    }

    return particles;
  }

  Future<void> _startSequence() async {
    // Phase 1: Scatter outward (0-400ms)
    _scatterController.forward();

    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    // Phase 2: Hold (400-800ms)
    _holdController.forward();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    // Phase 3: Fade out (800-1200ms)
    _fadeController.forward();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    widget.onComplete?.call();
  }

  @override
  void dispose() {
    _scatterController.dispose();
    _holdController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final halfSize = widget.size / 2;

    return Positioned(
      left: widget.position.dx - halfSize,
      top: widget.position.dy - halfSize,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _scatterController,
          _fadeController,
        ]),
        builder: (context, child) {
          return Opacity(
            opacity: _fadeOut.value,
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _SparkleburstPainter(
                  scatterProgress: _scatterProgress.value,
                  particles: _particles,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Painter that renders the central star and all scattered particles.
class _SparkleburstPainter extends CustomPainter {
  final double scatterProgress;
  final List<_SparkleParticle> particles;

  static const _mainGold = Color(0xFFE8B730);
  static const _lightGold = Color(0xFFF0C850);
  static const _darkGold = Color(0xFFD4A020);

  _SparkleburstPainter({
    required this.scatterProgress,
    required this.particles,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final center = Offset(centerX, centerY);
    final maxRadius = size.width * 0.45;

    // Draw scattered particles
    for (final particle in particles) {
      // Compute per-particle progress with stagger
      final staggerMs = particle.staggerDelay * 200; // 0-200ms delay
      final totalMs = 400.0;
      final adjustedProgress =
          ((scatterProgress * totalMs - staggerMs) / (totalMs - staggerMs))
              .clamp(0.0, 1.0);

      if (adjustedProgress <= 0) continue;

      final dist = maxRadius * particle.distance * adjustedProgress;
      final px = centerX + dist * cos(particle.angle);
      final py = centerY + dist * sin(particle.angle);
      final particleCenter = Offset(px, py);

      // Scale up as it moves outward
      final scale = adjustedProgress;
      final currentSize = particle.size * scale;

      if (currentSize < 0.5) continue;

      final alpha = (particle.opacity * 255).round().clamp(0, 255);
      final paint = Paint()
        ..color = particle.color.withAlpha(alpha)
        ..style = PaintingStyle.fill;

      switch (particle.type) {
        case _ParticleType.star:
          _drawFivePointedStar(
            canvas,
            particleCenter,
            currentSize,
            particle.rotation + adjustedProgress * 0.5,
            paint,
          );
          break;
        case _ParticleType.diamond:
          _drawFourPointedDiamond(
            canvas,
            particleCenter,
            currentSize,
            particle.rotation + adjustedProgress * 0.3,
            paint,
          );
          break;
        case _ParticleType.streak:
          _drawStreak(
            canvas,
            particleCenter,
            currentSize,
            particle.angle, // radiate outward from center
            paint,
          );
          break;
        case _ParticleType.dot:
          canvas.drawCircle(particleCenter, currentSize * 0.5, paint);
          break;
      }
    }

    // Draw central large star (always at center, scales with scatter)
    final centralStarSize = size.width * 0.15 * scatterProgress.clamp(0.0, 1.0);
    if (centralStarSize > 1) {
      _drawCentralStar(canvas, center, centralStarSize);
    }
  }

  /// Draws the large central 5-pointed star with a golden gradient.
  void _drawCentralStar(Canvas canvas, Offset center, double starSize) {
    final path = _starPath(center, starSize, starSize * 0.4, 5, -pi / 2);

    // Golden gradient fill
    const gradient = RadialGradient(
      colors: [_lightGold, _mainGold, _darkGold],
      stops: [0.0, 0.5, 1.0],
    );

    final rect = Rect.fromCircle(center: center, radius: starSize);
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);

    // Subtle outline
    canvas.drawPath(
      path,
      Paint()
        ..color = _darkGold.withAlpha(100)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  /// Draws a 5-pointed star particle.
  void _drawFivePointedStar(
    Canvas canvas,
    Offset center,
    double size,
    double rotation,
    Paint paint,
  ) {
    final path = _starPath(center, size, size * 0.4, 5, rotation - pi / 2);
    canvas.drawPath(path, paint);
  }

  /// Draws a 4-pointed diamond/sparkle shape (✦).
  void _drawFourPointedDiamond(
    Canvas canvas,
    Offset center,
    double size,
    double rotation,
    Paint paint,
  ) {
    final path = Path();
    const points = 4;
    final outerRadius = size;
    final innerRadius = size * 0.3;

    for (var i = 0; i < points * 2; i++) {
      final radius = i % 2 == 0 ? outerRadius : innerRadius;
      final angle = (i * pi / points) + rotation;
      final x = center.dx + radius * cos(angle);
      final y = center.dy + radius * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  /// Draws an elongated oval/streak radiating outward.
  void _drawStreak(
    Canvas canvas,
    Offset center,
    double size,
    double angle,
    Paint paint,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset.zero,
        width: size * 2.5,
        height: size * 0.5,
      ),
      Radius.circular(size * 0.25),
    );
    canvas.drawRRect(rect, paint);

    canvas.restore();
  }

  /// Creates a star path with the given parameters.
  Path _starPath(
    Offset center,
    double outerRadius,
    double innerRadius,
    int points,
    double startAngle,
  ) {
    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final radius = i % 2 == 0 ? outerRadius : innerRadius;
      final angle = startAngle + (i * pi / points);
      final x = center.dx + radius * cos(angle);
      final y = center.dy + radius * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _SparkleburstPainter oldDelegate) {
    return oldDelegate.scatterProgress != scatterProgress;
  }
}
