import 'dart:math';
import 'package:flutter/material.dart';

import 'sine_curve.dart';

/// Candy colors
final _candyColors = [
  const Color(0xFFFF6B6B), // Red
  const Color(0xFF4ECDC4), // Teal
  const Color(0xFFFFE66D), // Yellow
  const Color(0xFFDDA0DD), // Plum
  const Color(0xFF87CEEB), // Sky blue
  const Color(0xFFFFB6C1), // Light pink
  const Color(0xFF98D8C8), // Seafoam
  const Color(0xFFFFA07A), // Salmon
];

/// Candy types
enum CandyType { lollipop, jellyBean, wrapped, gummyBear }

/// Individual candy that falls and can be collected
class _CollectibleCandy extends StatefulWidget {
  final double initialX;
  final double size;
  final Color color;
  final CandyType type;
  final Duration fallDuration;
  final VoidCallback onCollected;

  const _CollectibleCandy({
    required this.initialX,
    required this.size,
    required this.color,
    required this.type,
    required this.fallDuration,
    required this.onCollected,
  });

  @override
  State<_CollectibleCandy> createState() => _CollectibleCandyState();
}

class _CollectibleCandyState extends State<_CollectibleCandy>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _yAnimation;
  late Animation<double> _rotationAnimation;
  late Animation<double> _swayAnimation;
  bool _isCollected = false;
  bool _isOffScreen = false;
  double _collectX = 0;
  double _collectY = 0;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.fallDuration,
    );

    // Fall from top to bottom
    _yAnimation = Tween<double>(
      begin: -0.2, // Start above screen
      end: 1.1, // End below screen
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.linear,
    ));

    // Rotation while falling
    _rotationAnimation = Tween<double>(
      begin: -0.5 + _random.nextDouble(),
      end: 2 * pi * (_random.nextInt(3) - 1),
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.linear,
    ));

    // Gentle sway while falling
    _swayAnimation = Tween<double>(
      begin: -0.02,
      end: 0.02,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const SineCurve(cycles: 3, amplitude: 0.3),
    ));

    // Listen for when candy goes off screen (falls past bottom)
    _controller.addListener(() {
      if (_yAnimation.value >= 1.05 && !_isOffScreen && !_isCollected) {
        setState(() => _isOffScreen = true);
        widget.onCollected(); // Count as gone when off screen
      }
    });

    _controller.forward();
  }

  void _collect() {
    if (_isCollected || _isOffScreen) return;
    
    // Capture current position for sparkle effect
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    _collectX = widget.initialX + _swayAnimation.value * screenWidth;
    _collectY = _yAnimation.value * screenHeight;
    
    setState(() => _isCollected = true);
    widget.onCollected();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Candy is gone if collected or fell off screen - don't respawn
    if (_isCollected) {
      // Show sparkle at the exact position where collected
      return Positioned(
        left: _collectX - widget.size,
        top: _collectY - widget.size / 2,
        child: _SparkleEffect(
          size: widget.size,
          color: widget.color,
        ),
      );
    }
    if (_isOffScreen) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final screenHeight = MediaQuery.of(context).size.height;
        final screenWidth = MediaQuery.of(context).size.width;

        final x = widget.initialX + _swayAnimation.value * screenWidth;
        final y = _yAnimation.value * screenHeight;

        return Positioned(
          left: x - widget.size / 2,
          top: y,
          child: GestureDetector(
            onTap: _collect,
            child: Transform.rotate(
              angle: _rotationAnimation.value,
              child: CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _CandyPainter(
                  color: widget.color,
                  type: widget.type,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Custom painter for different candy types
class _CandyPainter extends CustomPainter {
  final Color color;
  final CandyType type;

  _CandyPainter({required this.color, required this.type});

  @override
  void paint(Canvas canvas, Size size) {
    switch (type) {
      case CandyType.lollipop:
        _drawLollipop(canvas, size);
        break;
      case CandyType.jellyBean:
        _drawJellyBean(canvas, size);
        break;
      case CandyType.wrapped:
        _drawWrappedCandy(canvas, size);
        break;
      case CandyType.gummyBear:
        _drawGummyBear(canvas, size);
        break;
    }
  }

  void _drawLollipop(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final candyRadius = size.width * 0.35;

    // Stick
    final stickPaint = Paint()
      ..color = Colors.white.withAlpha(200)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(center.dx, center.dy + candyRadius),
      Offset(center.dx, size.height),
      stickPaint,
    );

    // Swirl candy
    final candyPaint = Paint()
      ..style = PaintingStyle.fill;

    // Base circle
    canvas.drawCircle(center, candyRadius, candyPaint..color = color);

    // White swirl
    final swirlPaint = Paint()
      ..color = Colors.white.withAlpha(180)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke;

    final path = Path();
    final spirals = 3;
    for (var i = 0; i < spirals * 20; i++) {
      final angle = i * 0.5;
      final r = candyRadius * (0.1 + i / (spirals * 20) * 0.8);
      final x = center.dx + r * cos(angle);
      final y = center.dy + r * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, swirlPaint);

    // Shine
    canvas.drawCircle(
      Offset(center.dx - candyRadius * 0.3, center.dy - candyRadius * 0.3),
      candyRadius * 0.15,
      Paint()
        ..color = Colors.white.withAlpha(150)
        ..style = PaintingStyle.fill,
    );
  }

  void _drawJellyBean(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      size.width * 0.15,
      size.height * 0.3,
      size.width * 0.7,
      size.height * 0.5,
    );

    // Main body
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(rect.left + rect.height / 2, rect.top);
    path.lineTo(rect.right - rect.height / 2, rect.top);
    path.cubicTo(
      rect.right, rect.top,
      rect.right, rect.bottom,
      rect.right - rect.height / 2, rect.bottom,
    );
    path.lineTo(rect.left + rect.height / 2, rect.bottom);
    path.cubicTo(
      rect.left, rect.bottom,
      rect.left, rect.top,
      rect.left + rect.height / 2, rect.top,
    );

    canvas.drawPath(path, paint);

    // Highlight
    final highlightPath = Path();
    highlightPath.moveTo(rect.left + rect.height / 3, rect.top + 5);
    highlightPath.lineTo(rect.right - rect.height / 3, rect.top + 5);
    highlightPath.cubicTo(
      rect.right - 5, rect.top + 5,
      rect.right - 10, rect.bottom - 10,
      rect.right - rect.height / 3, rect.bottom - 10,
    );

    canvas.drawPath(
      highlightPath,
      Paint()
        ..color = Colors.white.withAlpha(100)
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawWrappedCandy(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final width = size.width * 0.5;
    final height = size.height * 0.6;

    // Wrapper ends (twisted)
    final wrapperPaint = Paint()
      ..color = color.withAlpha(150)
      ..style = PaintingStyle.fill;

    // Left twisted wrapper
    final leftPath = Path();
    leftPath.moveTo(center.dx - width / 2, center.dy - height / 4);
    leftPath.lineTo(center.dx - width / 2 - 10, center.dy - height / 2 - 5);
    leftPath.lineTo(center.dx - width / 2 - 5, center.dy - height / 2 + 5);
    leftPath.lineTo(center.dx - width / 2, center.dy - height / 6);
    leftPath.close();
    canvas.drawPath(leftPath, wrapperPaint);

    // Right twisted wrapper
    final rightPath = Path();
    rightPath.moveTo(center.dx + width / 2, center.dy - height / 4);
    rightPath.lineTo(center.dx + width / 2 + 10, center.dy - height / 2 - 5);
    rightPath.lineTo(center.dx + width / 2 + 5, center.dy - height / 2 + 5);
    rightPath.lineTo(center.dx + width / 2, center.dy - height / 6);
    rightPath.close();
    canvas.drawPath(rightPath, wrapperPaint);

    // Main candy body
    final bodyRect = Rect.fromCenter(
      center: center,
      width: width,
      height: height,
    );

    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        color.withAlpha(230),
        color,
        color.withAlpha(180),
      ],
    );

    final bodyPaint = Paint()
      ..shader = gradient.createShader(bodyRect)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(8)),
      bodyPaint,
    );

    // Wrapper stripes
    final stripePaint = Paint()
      ..color = Colors.white.withAlpha(80)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < 3; i++) {
      canvas.drawLine(
        Offset(center.dx - width / 2 + 8 + i * 15, center.dy - height / 2 + 5),
        Offset(center.dx - width / 2 + 8 + i * 15, center.dy + height / 2 - 5),
        stripePaint,
      );
    }

    // Shine
    canvas.drawOval(
      Rect.fromLTWH(
        center.dx - width * 0.2,
        center.dy - height * 0.25,
        width * 0.3,
        height * 0.2,
      ),
      Paint()
        ..color = Colors.white.withAlpha(120)
        ..style = PaintingStyle.fill,
    );
  }

  void _drawGummyBear(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale = size.width * 0.4;

    final paint = Paint()
      ..color = color.withAlpha(200)
      ..style = PaintingStyle.fill;

    // Body (oval)
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + scale * 0.1),
        width: scale * 1.2,
        height: scale * 1.0,
      ),
      paint,
    );

    // Head (circle)
    canvas.drawCircle(
      Offset(center.dx, center.dy - scale * 0.5),
      scale * 0.45,
      paint,
    );

    // Ears
    canvas.drawCircle(
      Offset(center.dx - scale * 0.35, center.dy - scale * 0.8),
      scale * 0.18,
      paint,
    );
    canvas.drawCircle(
      Offset(center.dx + scale * 0.35, center.dy - scale * 0.8),
      scale * 0.18,
      paint,
    );

    // Arms
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx - scale * 0.6, center.dy),
        width: scale * 0.35,
        height: scale * 0.6,
      ),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx + scale * 0.6, center.dy),
        width: scale * 0.35,
        height: scale * 0.6,
      ),
      paint,
    );

    // Legs
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx - scale * 0.3, center.dy + scale * 0.7),
        width: scale * 0.35,
        height: scale * 0.6,
      ),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx + scale * 0.3, center.dy + scale * 0.7),
        width: scale * 0.35,
        height: scale * 0.6,
      ),
      paint,
    );

    // Eyes
    final eyePaint = Paint()
      ..color = Colors.black.withAlpha(150)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(center.dx - scale * 0.15, center.dy - scale * 0.55),
      scale * 0.06,
      eyePaint,
    );
    canvas.drawCircle(
      Offset(center.dx + scale * 0.15, center.dy - scale * 0.55),
      scale * 0.06,
      eyePaint,
    );

    // Nose
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy - scale * 0.4),
        width: scale * 0.1,
        height: scale * 0.06,
      ),
      eyePaint,
    );

    // Shine on head
    canvas.drawCircle(
      Offset(center.dx - scale * 0.15, center.dy - scale * 0.65),
      scale * 0.08,
      Paint()
        ..color = Colors.white.withAlpha(120)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Sparkle effect when candy is collected
class _SparkleEffect extends StatefulWidget {
  final double size;
  final Color color;

  const _SparkleEffect({
    required this.size,
    required this.color,
  });

  @override
  State<_SparkleEffect> createState() => _SparkleEffectState();
}

class _SparkleEffectState extends State<_SparkleEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _scaleAnimation = Tween<double>(
      begin: 0.5,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
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
              size: Size(widget.size * 1.5, widget.size * 1.5),
              painter: _SparklePainter(color: widget.color),
            ),
          ),
        );
      },
    );
  }
}

/// Painter for sparkle effect
class _SparklePainter extends CustomPainter {
  final Color color;

  _SparklePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final sparkleCount = 8;

    for (var i = 0; i < sparkleCount; i++) {
      final angle = (i * 2 * pi) / sparkleCount;
      final length = size.width * 0.4;
      final thickness = size.width * 0.06;

      final start = Offset(
        center.dx + length * 0.2 * cos(angle),
        center.dy + length * 0.2 * sin(angle),
      );
      final end = Offset(
        center.dx + length * cos(angle),
        center.dy + length * sin(angle),
      );

      // Draw 4-pointed star line
      canvas.drawLine(
        start,
        end,
        Paint()
          ..color = color.withAlpha(200)
          ..strokeWidth = thickness
          ..strokeCap = StrokeCap.round,
      );
    }

    // Center glow
    canvas.drawCircle(
      center,
      size.width * 0.15,
      Paint()
        ..color = Colors.white.withAlpha(180)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Candy reward effect widget.
///
/// Displays falling candy that children can tap to collect.
class CandyReward extends StatefulWidget {
  final VoidCallback onComplete;
  final VoidCallback? onAllCollected;
  final int candyCount;
  final Duration duration;

  const CandyReward({
    super.key,
    required this.onComplete,
    this.onAllCollected,
    this.candyCount = 18,
    this.duration = const Duration(seconds: 8),
  });

  @override
  State<CandyReward> createState() => _CandyRewardState();
}

class _CandyRewardState extends State<CandyReward> {
  final List<_CandyConfig> _candies = [];
  final _random = Random();
  int _collectedCount = 0;
  bool _isComplete = false;

  @override
  void initState() {
    super.initState();
    _generateCandies();
    _startCompletionTimer();
  }

  void _generateCandies() {
    for (var i = 0; i < widget.candyCount; i++) {
      _candies.add(_CandyConfig(
        initialX: 0.08 + _random.nextDouble() * 0.84,
        size: 50 + _random.nextDouble() * 50,
        color: _candyColors[_random.nextInt(_candyColors.length)],
        type: CandyType.values[_random.nextInt(CandyType.values.length)],
        delay: Duration(milliseconds: i * 200 + _random.nextInt(600)),
        fallDuration: widget.duration + Duration(seconds: _random.nextInt(4) - 2),
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

  void _onCandyCollected() {
    _collectedCount++;
    if (_collectedCount >= widget.candyCount && widget.onAllCollected != null) {
      widget.onAllCollected!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: _candies.map((config) {
        return FutureBuilder(
          future: Future.delayed(config.delay),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox.shrink();
            }
            return _CollectibleCandy(
              initialX: config.initialX * MediaQuery.of(context).size.width,
              size: config.size,
              color: config.color,
              type: config.type,
              fallDuration: config.fallDuration,
              onCollected: _onCandyCollected,
            );
          },
        );
      }).toList(),
    );
  }
}

/// Configuration for a single candy
class _CandyConfig {
  final double initialX;
  final double size;
  final Color color;
  final CandyType type;
  final Duration delay;
  final Duration fallDuration;

  _CandyConfig({
    required this.initialX,
    required this.size,
    required this.color,
    required this.type,
    required this.delay,
    required this.fallDuration,
  });
}
