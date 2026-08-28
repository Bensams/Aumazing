import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/world_theme.dart';

/// The scene drawn behind the "My Path" map.
///
/// Fills whatever box it is given. On the path screen that is the whole body,
/// so the scene sits behind the header and the platforms alike; at a small
/// size with a [borderRadius] it doubles as the settings preview swatch.
///
/// Everything here is static. Nothing twinkles, drifts or animates — an
/// unpredictably moving background competes with the steps for a child's
/// attention, and the steps are the thing to look at.
class WorldBackdrop extends StatelessWidget {
  const WorldBackdrop({super.key, required this.style, this.borderRadius = 0});

  final WorldStyle style;

  /// Corner rounding. Zero for the full-bleed scene, non-zero for a swatch.
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    if (!style.hasBackdrop) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: style.backdropGradient,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (style.kind == WorldBackdropKind.stars)
              const CustomPaint(painter: _StarFieldPainter()),
            // Optional illustrated layer. A missing or unreadable asset
            // degrades to the painted scene alone rather than an error box.
            if (style.backdropAsset != null)
              Image.asset(
                style.backdropAsset!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }
}

/// A fixed star field, two distant planets, a nebula glow, and the curve of a
/// planet surface along the bottom.
///
/// Everything is placed in **fractions of the box**, so the scene composes the
/// same way at swatch size and full-screen.
///
/// Star positions come from a **seeded** generator, so they are identical on
/// every repaint. An unseeded `Random` would reshuffle the sky on each rebuild
/// — the background would flicker whenever a step completed.
class _StarFieldPainter extends CustomPainter {
  const _StarFieldPainter();

  static const _seed = 20260729;
  static const _starCount = 90;

  @override
  void paint(Canvas canvas, Size size) {
    _paintNebula(canvas, size);
    _paintStars(canvas, size);
    // Planets before the surface, so the surface can occlude their lower edge.
    _paintPlanet(canvas, size,
        centre: Offset(size.width * 0.11, size.height * 0.30),
        radius: size.shortestSide * 0.15,
        base: const Color(0xFF3FBFD4),
        highlight: const Color(0xFF8FEAF0),
        ringed: true);
    _paintPlanet(canvas, size,
        centre: Offset(size.width * 0.88, size.height * 0.22),
        radius: size.shortestSide * 0.11,
        base: const Color(0xFF4A6BD8),
        highlight: const Color(0xFF9BB4FF),
        ringed: false);
    _paintSurface(canvas, size);
  }

  /// A broad, very soft glow behind the middle of the sky. Kept low-contrast:
  /// it should give the sky depth, never compete with a platform.
  void _paintNebula(Canvas canvas, Size size) {
    final centre = Offset(size.width * 0.5, size.height * 0.55);
    final radius = size.width * 0.42;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF8E7BD8).withValues(alpha: 0.34),
          const Color(0xFF6A5AB0).withValues(alpha: 0.10),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: centre, radius: radius));
    canvas.drawCircle(centre, radius, paint);
  }

  void _paintStars(Canvas canvas, Size size) {
    final random = math.Random(_seed);
    final paint = Paint();
    for (var i = 0; i < _starCount; i++) {
      final dx = random.nextDouble() * size.width;
      // Keep the sky clear of the lower band, where the surface sits.
      final dy = random.nextDouble() * size.height * 0.78;
      final radius = 0.7 + random.nextDouble() * 1.6;
      // Varying brightness is what stops it reading as a regular dot grid.
      paint.color = Colors.white.withValues(
        alpha: 0.25 + random.nextDouble() * 0.55,
      );
      canvas.drawCircle(Offset(dx, dy), radius, paint);
    }
  }

  void _paintPlanet(
    Canvas canvas,
    Size size, {
    required Offset centre,
    required double radius,
    required Color base,
    required Color highlight,
    required bool ringed,
  }) {
    // Light from the upper left, so both planets agree with each other.
    final body = Paint()
      ..shader = RadialGradient(
        colors: [highlight, base],
        stops: const [0.0, 1.0],
      ).createShader(
        Rect.fromCircle(
          center: centre.translate(-radius * 0.3, -radius * 0.3),
          radius: radius * 1.5,
        ),
      );
    canvas.drawCircle(centre, radius, body);

    if (!ringed) return;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, radius * 0.11)
      ..color = highlight.withValues(alpha: 0.65);
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(-0.32);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: radius * 3.1,
        height: radius * 0.9,
      ),
      ring,
    );
    canvas.restore();
  }

  /// The planet the path runs along: a very large circle whose top arc crosses
  /// the box near the bottom, so the platforms appear to float above ground.
  void _paintSurface(Canvas canvas, Size size) {
    final radius = size.width * 1.15;
    final centre = Offset(size.width / 2, size.height + radius - 24);
    canvas.drawCircle(centre, radius, Paint()..color = const Color(0xFF2A2350));
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.18);
    canvas.drawCircle(centre, radius, rim);
  }

  @override
  bool shouldRepaint(_StarFieldPainter oldDelegate) => false;
}
