import 'dart:math';
import 'package:flutter/material.dart';

import '../reward_sfx_provider.dart';

/// Firework colors
final _fireworkColors = [
  const Color(0xFFFF6B6B), // Red
  const Color(0xFF4ECDC4), // Teal
  const Color(0xFFFFE66D), // Yellow
  const Color(0xFFDDA0DD), // Plum
  const Color(0xFF87CEEB), // Sky blue
  const Color(0xFFFFB6C1), // Light pink
  const Color(0xFF98FB98), // Pale green
  const Color(0xFFFFA500), // Orange
];

/// Rocket pattern types
enum _RocketPattern { stripes, dots, solid }

/// Individual firework rocket that launches and explodes
class _FireworkRocket extends StatefulWidget {
  final double initialX;
  final double size;
  final Color color;
  final _RocketPattern pattern;
  final Duration launchDelay;
  final VoidCallback onExploded;

  const _FireworkRocket({
    required this.initialX,
    required this.size,
    required this.color,
    required this.pattern,
    required this.launchDelay,
    required this.onExploded,
  });

  @override
  State<_FireworkRocket> createState() => _FireworkRocketState();
}

class _FireworkRocketState extends State<_FireworkRocket>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _launchAnimation;
  bool _hasExploded = false;
  bool _showExplosion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    _launchAnimation = Tween<double>(
      begin: 1.0, // Bottom of screen
      end: 0.2, // Near top
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuad,
    ));

    Future.delayed(widget.launchDelay, () {
      if (mounted) {
        _controller.forward().then((_) {
          if (mounted) {
            setState(() {
              _hasExploded = true;
              _showExplosion = true;
            });
            widget.onExploded();
            Future.delayed(const Duration(milliseconds: 800), () {
              if (mounted) {
                setState(() => _showExplosion = false);
              }
            });
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _triggerEarlyExplosion() {
    if (_hasExploded) return;
    _controller.stop();
    setState(() {
      _hasExploded = true;
      _showExplosion = true;
    });
    widget.onExploded();
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() => _showExplosion = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final y = _launchAnimation.value * screenHeight;
        final x = widget.initialX;

        return Stack(
          children: [
            // Rocket
            if (!_hasExploded)
              Positioned(
                left: x - widget.size / 2,
                top: y,
                child: GestureDetector(
                  onTap: _triggerEarlyExplosion,
                  child: CustomPaint(
                    size: Size(widget.size, widget.size * 2),
                    painter: _RocketPainter(
                      color: widget.color,
                      pattern: widget.pattern,
                    ),
                  ),
                ),
              ),
            // Explosion
            if (_showExplosion)
              Positioned(
                left: x - widget.size,
                top: y - widget.size,
                child: _ExplosionEffect(
                  size: widget.size * 2,
                  color: widget.color,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Custom painter for rockets
class _RocketPainter extends CustomPainter {
  final Color color;
  final _RocketPattern pattern;

  _RocketPainter({required this.color, required this.pattern});

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    // Rocket body (cylinder)
    final bodyRect = Rect.fromLTWH(
      width * 0.25,
      height * 0.2,
      width * 0.5,
      height * 0.6,
    );

    // Body gradient
    final gradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        color.withAlpha(255),
        color,
        color.withAlpha(255),
      ],
    );

    final bodyPaint = Paint()
      ..shader = gradient.createShader(bodyRect)
      ..style = PaintingStyle.fill;

    canvas.drawRect(bodyRect, bodyPaint);

    // Draw pattern
    _drawPattern(canvas, size);

    // Rocket nose (cone)
    final nosePath = Path();
    nosePath.moveTo(width * 0.25, height * 0.2);
    nosePath.lineTo(width * 0.5, 0);
    nosePath.lineTo(width * 0.75, height * 0.2);
    nosePath.close();

    final nosePaint = Paint()
      ..color = color.withAlpha(255)
      ..style = PaintingStyle.fill;

    canvas.drawPath(nosePath, nosePaint);

    // Rocket fins
    final finPaint = Paint()
      ..color = color.withAlpha(255)
      ..style = PaintingStyle.fill;

    // Left fin
    final leftFin = Path();
    leftFin.moveTo(width * 0.25, height * 0.7);
    leftFin.lineTo(0, height * 0.85);
    leftFin.lineTo(width * 0.25, height * 0.8);
    leftFin.close();
    canvas.drawPath(leftFin, finPaint);

    // Right fin
    final rightFin = Path();
    rightFin.moveTo(width * 0.75, height * 0.7);
    rightFin.lineTo(width, height * 0.85);
    rightFin.lineTo(width * 0.75, height * 0.8);
    rightFin.close();
    canvas.drawPath(rightFin, finPaint);

    // Fuse/spark at bottom
    final sparkPaint = Paint()
      ..color = Colors.orange
      ..style = PaintingStyle.fill;

    for (var i = 0; i < 5; i++) {
      final sparkY = height * 0.85 + i * 8;
      canvas.drawCircle(
        Offset(width * 0.5, sparkY),
        2 + i.toDouble(),
        sparkPaint..color = Colors.orange.withAlpha(150 - i * 30),
      );
    }
  }

  void _drawPattern(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    switch (pattern) {
      case _RocketPattern.stripes:
        final stripePaint = Paint()
          ..color = Colors.white.withAlpha(100)
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke;

        for (var i = 0; i < 4; i++) {
          canvas.drawLine(
            Offset(width * 0.3, height * (0.25 + i * 0.15)),
            Offset(width * 0.7, height * (0.25 + i * 0.15)),
            stripePaint,
          );
        }
        break;

      case _RocketPattern.dots:
        final dotPaint = Paint()
          ..color = Colors.white.withAlpha(100)
          ..style = PaintingStyle.fill;

        for (var row = 0; row < 3; row++) {
          for (var col = 0; col < 2; col++) {
            canvas.drawCircle(
              Offset(
                width * (0.35 + col * 0.3),
                height * (0.3 + row * 0.18),
              ),
              4,
              dotPaint,
            );
          }
        }
        break;

      case _RocketPattern.solid:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Explosion effect with stars
class _ExplosionEffect extends StatefulWidget {
  final double size;
  final Color color;

  const _ExplosionEffect({
    required this.size,
    required this.color,
  });

  @override
  State<_ExplosionEffect> createState() => _ExplosionEffectState();
}

class _ExplosionEffectState extends State<_ExplosionEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.5,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuad,
    ));

    _fadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _StarBurstPainter(
                color: widget.color,
                starCount: 12,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Painter for star burst explosion
class _StarBurstPainter extends CustomPainter {
  final Color color;
  final int starCount;

  _StarBurstPainter({required this.color, required this.starCount});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (var i = 0; i < starCount; i++) {
      final angle = (i * 2 * pi) / starCount;
      final distance = maxRadius * (0.5 + 0.5 * sin(i * 1.5));

      final starCenter = Offset(
        center.dx + distance * cos(angle),
        center.dy + distance * sin(angle),
      );

      _drawStar(
        canvas,
        starCenter,
        maxRadius * 0.15,
        color.withAlpha(200 - (i * 10).abs()),
      );
    }

    // Center burst
    canvas.drawCircle(
      center,
      maxRadius * 0.2,
      Paint()
        ..color = color.withAlpha(150)
        ..style = PaintingStyle.fill,
    );
  }

  void _drawStar(Canvas canvas, Offset center, double size, Color starColor) {
    final path = Path();
    final points = 5;
    final outerRadius = size;
    final innerRadius = size * 0.4;

    for (var i = 0; i < points * 2; i++) {
      final radius = i % 2 == 0 ? outerRadius : innerRadius;
      final angle = (i * pi / points) - pi / 2;
      final x = center.dx + radius * cos(angle);
      final y = center.dy + radius * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..color = starColor
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Fireworks reward effect widget.
///
/// Displays rockets launching and exploding into colorful stars.
class FireworksReward extends StatefulWidget {
  final VoidCallback onComplete;
  final VoidCallback? onAllExploded;
  final int rocketCount;
  final Duration duration;

  const FireworksReward({
    super.key,
    required this.onComplete,
    this.onAllExploded,
    this.rocketCount = 12,
    this.duration = const Duration(seconds: 6),
  });

  @override
  State<FireworksReward> createState() => _FireworksRewardState();
}

class _FireworksRewardState extends State<FireworksReward> {
  final List<_RocketConfig> _rockets = [];
  final _random = Random();
  int _explodedCount = 0;
  bool _isComplete = false;

  @override
  void initState() {
    super.initState();
    _generateRockets();
    _startCompletionTimer();
  }

  void _generateRockets() {
    for (var i = 0; i < widget.rocketCount; i++) {
      _rockets.add(_RocketConfig(
        initialX: 0.1 + _random.nextDouble() * 0.8,
        size: 40 + _random.nextDouble() * 30,
        color: _fireworkColors[_random.nextInt(_fireworkColors.length)],
        pattern: _RocketPattern.values[_random.nextInt(_RocketPattern.values.length)],
        launchDelay: Duration(milliseconds: i * 700 + _random.nextInt(1000)),
      ));
    }
  }

  void _startCompletionTimer() {
    Future.delayed(widget.duration, () {
      if (mounted && !_isComplete) {
        setState(() => _isComplete = true);
        widget.onComplete();
      }
    });
  }

  void _onRocketExploded() {
    RewardSfxProvider.playFireworkPop(context);
    _explodedCount++;
    if (_explodedCount >= widget.rocketCount && widget.onAllExploded != null) {
      widget.onAllExploded!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Stack(
      children: _rockets.map((config) {
        return _FireworkRocket(
          initialX: config.initialX * screenWidth,
          size: config.size,
          color: config.color,
          pattern: config.pattern,
          launchDelay: config.launchDelay,
          onExploded: _onRocketExploded,
        );
      }).toList(),
    );
  }
}

/// Configuration for a single rocket
class _RocketConfig {
  final double initialX;
  final double size;
  final Color color;
  final _RocketPattern pattern;
  final Duration launchDelay;

  _RocketConfig({
    required this.initialX,
    required this.size,
    required this.color,
    required this.pattern,
    required this.launchDelay,
  });
}
