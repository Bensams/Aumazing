import 'dart:math';
import 'package:flutter/material.dart';

import '../reward_sfx_provider.dart';
import 'sine_curve.dart';

/// Bubble iridescent colors (medium-light for visibility on pastel backgrounds)
final _bubbleColors = [
  const Color(0xFF90CAF9), // Medium blue
  const Color(0xFFA5D6A7), // Medium green
  const Color(0xFFFFCC80), // Medium orange
  const Color(0xFFCE93D8), // Medium purple
  const Color(0xFF80DEEA), // Medium cyan
  const Color(0xFFF48FB1), // Medium pink
  const Color(0xFFC5E1A5), // Medium lime
  const Color(0xFF9FA8DA), // Medium indigo
];

/// Individual bubble that floats up and can be popped
class _PoppableBubble extends StatefulWidget {
  final double initialX;
  final double size;
  final Color baseColor;
  final Duration floatDuration;
  final VoidCallback onPopped;

  const _PoppableBubble({
    required this.initialX,
    required this.size,
    required this.baseColor,
    required this.floatDuration,
    required this.onPopped,
  });

  @override
  State<_PoppableBubble> createState() => _PoppableBubbleState();
}

class _PoppableBubbleState extends State<_PoppableBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _yAnimation;
  late Animation<double> _wobbleAnimation;
  bool _isPopped = false;
  bool _isOffScreen = false;
  double _popX = 0;
  double _popY = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.floatDuration,
    );

    // Float from bottom to top
    _yAnimation = Tween<double>(
      begin: 1.1, // Start below screen
      end: -0.1, // End above screen
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.linear,
    ));

    // Wobble animation (gentle side-to-side)
    _wobbleAnimation = Tween<double>(
      begin: -0.03,
      end: 0.03,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const SineCurve(cycles: 4, amplitude: 0.1),
    ));

    // Listen for when bubble goes off screen (floats past top)
    _controller.addListener(() {
      if (_yAnimation.value <= -0.05 && !_isOffScreen && !_isPopped) {
        setState(() => _isOffScreen = true);
        widget.onPopped(); // Count as gone when off screen
      }
    });

    _controller.forward();
  }

  void _pop() {
    if (_isPopped || _isOffScreen) return;
    
    // Capture current position for pop effect
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    _popX = widget.initialX + _wobbleAnimation.value * screenWidth;
    _popY = _yAnimation.value * screenHeight;
    
    setState(() => _isPopped = true);
    widget.onPopped();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Bubble is gone if popped or floated off screen - don't respawn
    if (_isPopped) {
      // Show pop splash at the exact position where tapped
      return Positioned(
        left: _popX - widget.size,
        top: _popY - widget.size / 2,
        child: _PopSplash(
          size: widget.size,
          color: widget.baseColor,
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

        final x = widget.initialX + _wobbleAnimation.value * screenWidth;
        final y = _yAnimation.value * screenHeight;

        return Positioned(
          left: x - widget.size / 2,
          top: y,
          child: GestureDetector(
            onTap: _pop,
            child: CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _BubblePainter(
                baseColor: widget.baseColor,
                animationValue: _controller.value,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Custom painter for iridescent bubbles
class _BubblePainter extends CustomPainter {
  final Color baseColor;
  final double animationValue;

  _BubblePainter({required this.baseColor, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Create iridescent gradient that shifts with animation
    final shimmerOffset = sin(animationValue * 2 * pi) * 0.2;

    // --- Glow layer: soft colored halo behind the bubble ---
    final glowPaint = Paint()
      ..color = baseColor.withAlpha(90)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(center, radius * 1.05, glowPaint);

    final gradient = RadialGradient(
      center: Alignment(-0.3 + shimmerOffset, -0.3),
      radius: 0.8,
      colors: [
        Colors.white.withAlpha(230),
        baseColor.withAlpha(160),
        baseColor.withAlpha(120),
        baseColor.withAlpha(80),
      ],
      stops: const [0.0, 0.3, 0.7, 1.0],
    );

    // Main bubble body
    final bubblePaint = Paint()
      ..shader = gradient.createShader(
        Rect.fromCircle(center: center, radius: radius),
      )
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, bubblePaint);

    // Bubble border (colored outline for definition)
    final borderPaint = Paint()
      ..color = baseColor.withAlpha(140)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, radius * 0.95, borderPaint);

    // Highlight (shiny reflection)
    final highlightPaint = Paint()
      ..color = Colors.white.withAlpha(210)
      ..style = PaintingStyle.fill;

    // Main highlight
    canvas.drawOval(
      Rect.fromLTWH(
        radius * 0.3,
        radius * 0.25,
        radius * 0.35,
        radius * 0.25,
      ),
      highlightPaint,
    );

    // Secondary small highlight
    canvas.drawCircle(
      Offset(radius * 0.7, radius * 0.6),
      radius * 0.08,
      Paint()
        ..color = Colors.white.withAlpha(140)
        ..style = PaintingStyle.fill,
    );

    // Iridescent rim effect
    final rimGradient = SweepGradient(
      center: Alignment.center,
      colors: [
        baseColor.withAlpha(0),
        baseColor.withAlpha(80),
        baseColor.withAlpha(0),
        baseColor.withAlpha(60),
        baseColor.withAlpha(0),
      ],
    );

    final rimPaint = Paint()
      ..shader = rimGradient.createShader(
        Rect.fromCircle(center: center, radius: radius),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    canvas.drawCircle(center, radius * 0.85, rimPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Pop splash effect when bubble is tapped
class _PopSplash extends StatefulWidget {
  final double size;
  final Color color;

  const _PopSplash({
    required this.size,
    required this.color,
  });

  @override
  State<_PopSplash> createState() => _PopSplashState();
}

class _PopSplashState extends State<_PopSplash>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _scaleAnimation = Tween<double>(
      begin: 0.5,
      end: 1.5,
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
          child: CustomPaint(
            size: Size(widget.size * 2, widget.size * 2),
            painter: _SplashPainter(
              color: widget.color,
              scale: _scaleAnimation.value,
            ),
          ),
        );
      },
    );
  }
}

/// Painter for splash droplets
class _SplashPainter extends CustomPainter {
  final Color color;
  final double scale;

  _SplashPainter({required this.color, required this.scale});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final dropletCount = 6;
    final maxRadius = size.width / 2 * scale;

    for (var i = 0; i < dropletCount; i++) {
      final angle = (i * 2 * pi) / dropletCount;
      final dropletCenter = Offset(
        center.dx + maxRadius * 0.6 * cos(angle) * scale,
        center.dy + maxRadius * 0.6 * sin(angle) * scale,
      );

      // Droplet
      canvas.drawCircle(
        dropletCenter,
        4 * scale,
        Paint()
          ..color = color.withAlpha(150)
          ..style = PaintingStyle.fill,
      );
    }

    // Center ripple
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        center,
        maxRadius * (0.3 + i * 0.2) * scale,
        Paint()
          ..color = color.withAlpha(50 - i * 15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Bubbles reward effect widget.
///
/// Displays gentle floating bubbles that children can tap to pop.
/// This is the "safe default" option for sensory-sensitive children.
class BubblesReward extends StatefulWidget {
  final VoidCallback onComplete;
  final VoidCallback? onAllPopped;
  final int bubbleCount;
  final Duration duration;

  const BubblesReward({
    super.key,
    required this.onComplete,
    this.onAllPopped,
    this.bubbleCount = 20,
    this.duration = const Duration(seconds: 10),
  });

  @override
  State<BubblesReward> createState() => _BubblesRewardState();
}

class _BubblesRewardState extends State<BubblesReward> {
  final List<_BubbleConfig> _bubbles = [];
  final _random = Random();
  int _poppedCount = 0;
  bool _isComplete = false;

  @override
  void initState() {
    super.initState();
    _generateBubbles();
    _startCompletionTimer();
  }

  void _generateBubbles() {
    for (var i = 0; i < widget.bubbleCount; i++) {
      final delay = Duration(milliseconds: i * 250 + _random.nextInt(500));
      _bubbles.add(_BubbleConfig(
        initialX: 0.05 + _random.nextDouble() * 0.9,
        size: 40 + _random.nextDouble() * 60,
        baseColor: _bubbleColors[_random.nextInt(_bubbleColors.length)],
        delay: delay,
        // Create the spawn future ONCE so rebuilds don't restart the bubble.
        spawn: Future<void>.delayed(delay),
        floatDuration: widget.duration + Duration(seconds: _random.nextInt(4) - 2),
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

  void _onBubblePopped() {
    RewardSfxProvider.playBubblePop(context);
    _poppedCount++;
    if (_poppedCount >= widget.bubbleCount && widget.onAllPopped != null) {
      widget.onAllPopped!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: _bubbles.map((config) {
        return FutureBuilder(
          key: ObjectKey(config),
          future: config.spawn,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox.shrink();
            }
            return _PoppableBubble(
              initialX: config.initialX * MediaQuery.of(context).size.width,
              size: config.size,
              baseColor: config.baseColor,
              floatDuration: config.floatDuration,
              onPopped: _onBubblePopped,
            );
          },
        );
      }).toList(),
    );
  }
}

/// Configuration for a single bubble
class _BubbleConfig {
  final double initialX;
  final double size;
  final Color baseColor;
  final Duration delay;

  /// Spawn-delay future, created once so rebuilds don't restart the bubble.
  final Future<void> spawn;
  final Duration floatDuration;

  _BubbleConfig({
    required this.initialX,
    required this.size,
    required this.baseColor,
    required this.delay,
    required this.spawn,
    required this.floatDuration,
  });
}
