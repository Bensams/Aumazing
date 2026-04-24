import 'dart:math';
import 'package:flutter/material.dart';

import '../reward_sfx_provider.dart';
import 'sine_curve.dart';

/// Balloon colors with various shades
final _balloonColors = [
  const Color(0xFFFF6B6B), // Red
  const Color(0xFF4ECDC4), // Teal
  const Color(0xFFFFE66D), // Yellow
  const Color(0xFF95E1D3), // Mint
  const Color(0xFFFFA07A), // Salmon
  const Color(0xFFDDA0DD), // Plum
  const Color(0xFF87CEEB), // Sky blue
  const Color(0xFFFFB6C1), // Light pink
  const Color(0xFF98D8C8), // Seafoam
  const Color(0xFFF7DC6F), // Golden
];

/// Balloon pattern types
enum _BalloonPattern { solid, stars, dots, stripes, checkered }

/// Individual balloon that floats up and can be popped
class _PoppableBalloon extends StatefulWidget {
  final double initialX;
  final double size;
  final Color color;
  final _BalloonPattern pattern;
  final Duration floatDuration;
  final VoidCallback onPopped;

  const _PoppableBalloon({
    required this.initialX,
    required this.size,
    required this.color,
    required this.pattern,
    required this.floatDuration,
    required this.onPopped,
  });

  @override
  State<_PoppableBalloon> createState() => _PoppableBalloonState();
}

class _PoppableBalloonState extends State<_PoppableBalloon>
    with TickerProviderStateMixin {
  late AnimationController _floatController;
  late AnimationController _bobController;
  late Animation<double> _yAnimation;
  late Animation<double> _swayAnimation;
  late Animation<double> _bobAnimation;
  bool _isPopped = false;
  bool _hasReachedTop = false;
  double _popX = 0;
  double _popY = 0;

  @override
  void initState() {
    super.initState();

    // Float controller - moves balloon from bottom to top
    _floatController = AnimationController(
      vsync: this,
      duration: widget.floatDuration,
    );

    // Bob controller - gentle up/down movement once balloon reaches top
    _bobController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Float from bottom to top - stop before top edge so balloon is fully visible
    _yAnimation = Tween<double>(
      begin: 1.2, // Start below screen
      end: 0.05, // Stop near top (balloon fully visible)
    ).animate(CurvedAnimation(
      parent: _floatController,
      curve: Curves.easeOutCubic,
    ));

    // Very gentle sway side to side during float
    _swayAnimation = Tween<double>(
      begin: -0.02,
      end: 0.02,
    ).animate(CurvedAnimation(
      parent: _floatController,
      curve: const SineCurve(),
    ));

    // Gentle bob animation once at top (small vertical oscillation)
    _bobAnimation = Tween<double>(
      begin: -8.0,
      end: 8.0,
    ).animate(CurvedAnimation(
      parent: _bobController,
      curve: Curves.easeInOut,
    ));

    // When float completes, start bobbing at the top
    _floatController.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_isPopped) {
        setState(() => _hasReachedTop = true);
        _bobController.repeat(reverse: true);
      }
    });

    _floatController.forward();
  }

  void _pop() {
    if (_isPopped) return;

    // Capture current position for pop effect
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    if (_hasReachedTop) {
      // Balloon is bobbing at top
      _popX = widget.initialX;
      _popY = 0.05 * screenHeight + _bobAnimation.value;
    } else {
      // Balloon is still floating up
      _popX = widget.initialX + (_swayAnimation.value * screenWidth * 0.1);
      _popY = _yAnimation.value * screenHeight;
    }

    setState(() => _isPopped = true);
    _bobController.stop();
    widget.onPopped();
  }

  @override
  void dispose() {
    _floatController.dispose();
    _bobController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Balloon is popped - show particles
    if (_isPopped) {
      return Positioned(
        left: _popX - widget.size / 2,
        top: _popY,
        child: _PopParticles(
          size: widget.size,
          color: widget.color,
        ),
      );
    }

    return AnimatedBuilder(
      animation: Listenable.merge([_floatController, _bobController]),
      builder: (context, child) {
        final screenHeight = MediaQuery.of(context).size.height;
        final screenWidth = MediaQuery.of(context).size.width;

        double x;
        double y;

        if (_hasReachedTop) {
          // Balloon reached top - bob gently in place
          x = widget.initialX;
          y = 0.05 * screenHeight + _bobAnimation.value;
        } else {
          // Balloon is floating up
          x = widget.initialX +
              (_swayAnimation.value * screenWidth * 0.1);
          y = _yAnimation.value * screenHeight;
        }

        return Positioned(
          left: x - widget.size / 2,
          top: y,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _pop,
            child: CustomPaint(
              size: Size(widget.size, widget.size * 1.2),
              painter: _BalloonPainter(
                color: widget.color,
                pattern: widget.pattern,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Custom painter for balloons with patterns
class _BalloonPainter extends CustomPainter {
  final Color color;
  final _BalloonPattern pattern;

  _BalloonPainter({required this.color, required this.pattern});

  @override
  void paint(Canvas canvas, Size size) {
    final balloonWidth = size.width;
    final balloonHeight = size.height * 0.85;

    // Balloon body - oval/egg shape: wide round top, narrow pointy bottom
    final bodyPath = Path();
    bodyPath.moveTo(balloonWidth / 2, 0);
    bodyPath.cubicTo(
      balloonWidth * 0.95, balloonHeight * 0.15,
      balloonWidth * 0.85, balloonHeight * 0.75,
      balloonWidth / 2, balloonHeight,
    );
    bodyPath.cubicTo(
      balloonWidth * 0.15, balloonHeight * 0.75,
      balloonWidth * 0.05, balloonHeight * 0.15,
      balloonWidth / 2, 0,
    );
    bodyPath.close();

    // Use saveLayer to isolate the balloon body + pattern rendering.
    // This prevents semi-transparent pattern paint from compositing
    // through the balloon body and creating visible bands on the background.
    final layerBounds = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.saveLayer(layerBounds, Paint());

    // Clip everything in this layer to the balloon shape
    canvas.clipPath(bodyPath);

    // Base balloon gradient — use fully opaque colors inside the layer
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        color,
        color,
        color,
      ],
    );

    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromLTWH(0, 0, balloonWidth, balloonHeight),
      )
      ..style = PaintingStyle.fill;

    canvas.drawPath(bodyPath, paint);

    // Draw pattern — already clipped to bodyPath by the layer clip above
    _drawPattern(canvas, size, balloonWidth, balloonHeight);

    // Draw highlight (shiny reflection) - on the round top part
    final highlightPaint = Paint()
      ..color = Colors.white.withAlpha(120)
      ..style = PaintingStyle.fill;

    canvas.drawOval(
      Rect.fromLTWH(
        balloonWidth * 0.2,
        balloonHeight * 0.08,
        balloonWidth * 0.25,
        balloonHeight * 0.2,
      ),
      highlightPaint,
    );

    // End the isolated layer — composites balloon onto the main canvas
    canvas.restore();

    // Small knot at bottom of balloon body (drawn outside clip/layer)
    final knotPaint = Paint()
      ..color = color.withAlpha(180)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(balloonWidth / 2, balloonHeight),
      3,
      knotPaint,
    );

    // Draw string - hanging down from the knot
    final stringPaint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final stringPath = Path();
    stringPath.moveTo(balloonWidth / 2, balloonHeight);
    stringPath.quadraticBezierTo(
      balloonWidth / 2 + 8,
      balloonHeight + size.height * 0.08,
      balloonWidth / 2 - 5,
      size.height,
    );
    canvas.drawPath(stringPath, stringPaint);
  }

  void _drawPattern(Canvas canvas, Size size, double width, double height) {
    final patternPaint = Paint()
      ..color = Colors.white.withAlpha(100)
      ..style = PaintingStyle.fill;

    switch (pattern) {
      case _BalloonPattern.stars:
        for (var i = 0; i < 5; i++) {
          final x = width * (0.2 + i * 0.15);
          final y = height * (0.2 + (i % 2) * 0.3);
          _drawStar(canvas, Offset(x, y), width * 0.08);
        }
        break;

      case _BalloonPattern.dots:
        for (var row = 0; row < 3; row++) {
          for (var col = 0; col < 3; col++) {
            canvas.drawCircle(
              Offset(
                width * (0.2 + col * 0.3),
                height * (0.25 + row * 0.25),
              ),
              width * 0.06,
              patternPaint,
            );
          }
        }
        break;

      case _BalloonPattern.stripes:
        final stripePaint = Paint()
          ..color = Colors.white.withAlpha(80)
          ..strokeWidth = width * 0.08
          ..style = PaintingStyle.stroke;

        for (var i = 1; i < 4; i++) {
          canvas.drawLine(
            Offset(width * i / 4, height * 0.1),
            Offset(width * i / 4, height * 0.8),
            stripePaint,
          );
        }
        break;

      case _BalloonPattern.checkered:
        for (var row = 0; row < 4; row++) {
          for (var col = 0; col < 4; col++) {
            if ((row + col) % 2 == 0) {
              canvas.drawRect(
                Rect.fromLTWH(
                  width * col / 4,
                  height * (0.1 + row * 0.2),
                  width / 4,
                  height * 0.2,
                ),
                patternPaint,
              );
            }
          }
        }
        break;

      case _BalloonPattern.solid:
        break;
    }
  }

  void _drawStar(Canvas canvas, Offset center, double size) {
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
        ..color = Colors.white.withAlpha(120)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Balloons reward effect widget.
///
/// Displays floating balloons that children can tap to pop.
class BalloonsReward extends StatefulWidget {
  final VoidCallback onComplete;
  final VoidCallback? onAllPopped;
  final int balloonCount;
  final Duration duration;

  const BalloonsReward({
    super.key,
    required this.onComplete,
    this.onAllPopped,
    this.balloonCount = 15,
    this.duration = const Duration(seconds: 8),
  });

  @override
  State<BalloonsReward> createState() => _BalloonsRewardState();
}

class _BalloonsRewardState extends State<BalloonsReward> {
  final List<_BalloonConfig> _balloons = [];
  final _random = Random();
  int _poppedCount = 0;
  bool _isComplete = false;

  @override
  void initState() {
    super.initState();
    _generateBalloons();
    _startCompletionTimer();
  }

  void _generateBalloons() {
    for (var i = 0; i < widget.balloonCount; i++) {
      _balloons.add(_BalloonConfig(
        initialX: 0.05 + _random.nextDouble() * 0.9,
        size: 60 + _random.nextDouble() * 50,
        color: _balloonColors[_random.nextInt(_balloonColors.length)],
        pattern: _BalloonPattern.values[_random.nextInt(_BalloonPattern.values.length)],
        delay: Duration(milliseconds: i * 200 + _random.nextInt(800)),
        floatDuration: widget.duration + Duration(seconds: _random.nextInt(5) - 2),
      ));
    }
  }

  void _startCompletionTimer() {
    final latestArrival = _balloons.fold<Duration>(
      Duration.zero,
      (max, b) {
        final total = b.delay + b.floatDuration;
        return total > max ? total : max;
      },
    );
    final completionDelay = latestArrival + const Duration(seconds: 5);

    Future.delayed(completionDelay, () {
      if (mounted && !_isComplete) {
        setState(() => _isComplete = true);
        widget.onComplete();
      }
    });
  }

  void _onBalloonPopped() {
    RewardSfxProvider.playBalloonPop(context);
    _poppedCount++;
    if (_poppedCount >= widget.balloonCount) {
      if (!_isComplete) {
        setState(() => _isComplete = true);
        widget.onComplete();
      }
      if (widget.onAllPopped != null) {
        widget.onAllPopped!();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: _balloons.map((config) {
        return FutureBuilder(
          future: Future.delayed(config.delay),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox.shrink();
            }
            final screenWidth = MediaQuery.of(context).size.width;
            final maxSize = screenWidth * 0.2;
            final actualSize = config.size > maxSize ? maxSize : config.size;
            return _PoppableBalloon(
              initialX: config.initialX * screenWidth,
              size: actualSize,
              color: config.color,
              pattern: config.pattern,
              floatDuration: config.floatDuration,
              onPopped: _onBalloonPopped,
            );
          },
        );
      }).toList(),
    );
  }
}

/// Configuration for a single balloon
class _BalloonConfig {
  final double initialX;
  final double size;
  final Color color;
  final _BalloonPattern pattern;
  final Duration delay;
  final Duration floatDuration;

  _BalloonConfig({
    required this.initialX,
    required this.size,
    required this.color,
    required this.pattern,
    required this.delay,
    required this.floatDuration,
  });
}

/// Particle explosion effect when balloon is popped
class _PopParticles extends StatefulWidget {
  final double size;
  final Color color;

  const _PopParticles({
    required this.size,
    required this.color,
  });

  @override
  State<_PopParticles> createState() => _PopParticlesState();
}

class _PopParticlesState extends State<_PopParticles>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _particles = List.generate(8, (index) {
      final angle = (index / 8) * 2 * pi;
      final speed = 0.5 + Random().nextDouble() * 0.5;
      return _Particle(
        angle: angle,
        speed: speed,
        size: widget.size * (0.1 + Random().nextDouble() * 0.15),
        color: widget.color,
      );
    });

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
        return SizedBox(
          width: widget.size * 2,
          height: widget.size * 2,
          child: Stack(
            children: _particles.map((particle) {
              final progress = _controller.value;
              final distance = particle.speed * progress * widget.size;
              final x = cos(particle.angle) * distance + widget.size;
              final y = sin(particle.angle) * distance + widget.size;
              final opacity = 1.0 - progress;

              return Positioned(
                left: x - particle.size / 2,
                top: y - particle.size / 2,
                child: Opacity(
                  opacity: opacity,
                  child: Container(
                    width: particle.size,
                    height: particle.size,
                    decoration: BoxDecoration(
                      color: particle.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _Particle {
  final double angle;
  final double speed;
  final double size;
  final Color color;

  _Particle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
  });
}
