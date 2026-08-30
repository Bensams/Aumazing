import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../reward_sfx_provider.dart';

/// Warm palette for the popping stars: golds, ambers and oranges with
/// occasional pink/cyan accents. Matches the milestone scene's golden stage.
final _starColors = <Color>[
  const Color(0xFFFFD54F), // gold
  const Color(0xFFFFC14D), // warm amber
  const Color(0xFFFF9800), // orange
  const Color(0xFFFFE082), // warm yellow
  const Color(0xFFFFB74D), // apricot
  const Color(0xFFF06292), // pink accent
  const Color(0xFF4DD0E1), // cyan accent
];

/// Where a star starts its rise, as a fraction of screen height: below the
/// bottom edge, so it travels *into* the scene rather than blinking into it.
const double _kStarRiseFrom = 1.15;

/// How long a star takes to rise from below the screen to its resting spot.
/// Matched in spirit to the balloons' own float: slow enough for a child who
/// processes movement slowly to follow one star all the way up.
const Duration kStarRiseDuration = Duration(milliseconds: 1200);

/// Trace a hand-drawn five-point star centred at [center].
Path _starPath(Offset center, double radius) {
  final path = Path();
  const points = 5;
  final outer = radius;
  final inner = radius * 0.45;
  for (var i = 0; i < points * 2; i++) {
    final r = i.isEven ? outer : inner;
    final angle = i * pi / points - pi / 2;
    final x = center.dx + r * cos(angle);
    final y = center.dy + r * sin(angle);
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  path.close();
  return path;
}

/// Individual star that rises in from below, then drifts gently (no linear
/// fall) and can be popped.
///
/// It never simply appears: it travels up from under the bottom edge to its
/// resting spot, the way the balloons and bubbles do, so the child sees it
/// arrive and can track it. It is poppable the whole way up.
///
/// Under [reducedMotion] there is no travel — the star is at its base spot from
/// the start and only fades in — no drift, rotation or scale pulse, and it
/// merely fades out on pop.
class _CollectibleStar extends StatefulWidget {
  final Offset baseFraction;
  final double size;
  final Color color;
  final double driftPhase;
  final bool reducedMotion;
  final VoidCallback onPopped;

  const _CollectibleStar({
    super.key,
    required this.baseFraction,
    required this.size,
    required this.color,
    required this.driftPhase,
    required this.reducedMotion,
    required this.onPopped,
  });

  @override
  State<_CollectibleStar> createState() => _CollectibleStarState();
}

class _CollectibleStarState extends State<_CollectibleStar>
    with TickerProviderStateMixin {
  late final AnimationController _controller;

  /// The one-way rise from below the bottom edge to the resting spot. Under
  /// reduced motion it drives a plain fade-in instead of any travel.
  late final AnimationController _rise;

  bool _isPopped = false;
  Offset _popCenter = Offset.zero;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    );
    _rise = AnimationController(vsync: this, duration: kStarRiseDuration);
    // Gentle continuous drift; static (never started) under reduced motion.
    if (!widget.reducedMotion) _controller.repeat();
    _rise.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _rise.dispose();
    super.dispose();
  }

  /// Progress of the rise, eased. 1 means the star has arrived.
  double get _riseProgress => Curves.easeOutCubic.transform(_rise.value);

  /// Current centre of the star on screen, honouring reduced motion.
  ///
  /// Two movements combine: the one-way rise into the scene, and the endless
  /// gentle drift once there. The drift is scaled by the rise so the star does
  /// not wobble its way up — it travels, then it breathes.
  Offset _computePosition(Size screen) {
    final reduced = widget.reducedMotion;
    final t = reduced ? 0.0 : _controller.value;
    final phase = t * 2 * pi;
    // Small, slow, non-linear bob — never a straight candy fall.
    final driftX = reduced
        ? 0.0
        : sin(phase + widget.driftPhase) * 0.012 * screen.width;
    final driftY = reduced
        ? 0.0
        : sin(phase * 0.7 + widget.driftPhase) * 0.02 * screen.height;
    // Reduced motion places the star at rest immediately: no travel at all.
    final rise = reduced ? 1.0 : _riseProgress;
    final y = _kStarRiseFrom + (widget.baseFraction.dy - _kStarRiseFrom) * rise;
    return Offset(
      widget.baseFraction.dx * screen.width + driftX * rise,
      y * screen.height + driftY * rise,
    );
  }

  /// Pops this star if [globalPosition] is within its current bounds.
  bool tryPopAt(Offset globalPosition) {
    if (_isPopped || !mounted) return false;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    final local = box.globalToLocal(globalPosition);
    // A small hit slop (+8) keeps the target toddler-friendly.
    if (local.dx >= -8 &&
        local.dy >= -8 &&
        local.dx <= box.size.width + 8 &&
        local.dy <= box.size.height + 8) {
      _pop();
      return true;
    }
    return false;
  }

  void _pop() {
    if (_isPopped) return;
    final screen = MediaQuery.of(context).size;
    _popCenter = _computePosition(screen);
    setState(() => _isPopped = true);
    widget.onPopped();
  }

  @override
  Widget build(BuildContext context) {
    if (_isPopped) {
      // Reduced motion: a simple in-place fade; otherwise a radial burst.
      final Widget effect = widget.reducedMotion
          ? _StarFadeOut(size: widget.size, color: widget.color)
          : RewardPopBurst(size: widget.size, color: widget.color);
      return Positioned(
        left: _popCenter.dx - widget.size * 0.8,
        top: _popCenter.dy - widget.size * 0.8,
        child: SizedBox(
          width: widget.size * 1.6,
          height: widget.size * 1.6,
          child: Center(child: effect),
        ),
      );
    }

    return AnimatedBuilder(
      animation: Listenable.merge([_controller, _rise]),
      builder: (context, child) {
        final screen = MediaQuery.of(context).size;
        final center = _computePosition(screen);
        final reduced = widget.reducedMotion;
        final phase = (reduced ? 0.0 : _controller.value) * 2 * pi;
        final rotation = reduced ? 0.0 : sin(phase + widget.driftPhase) * 0.18;
        final scale = reduced
            ? 1.0
            : 1.0 + 0.06 * sin(phase * 2 + widget.driftPhase);
        // The rise is the entrance under full motion; under reduced motion the
        // same progress is spent on a gentle fade instead.
        final opacity = reduced ? _riseProgress.clamp(0.0, 1.0) : 1.0;
        return Positioned(
          left: center.dx - widget.size / 2,
          top: center.dy - widget.size / 2,
          child: Opacity(
            opacity: opacity,
            child: Transform.rotate(
              angle: rotation,
              child: Transform.scale(
                scale: scale,
                child: CustomPaint(
                  size: Size(widget.size, widget.size),
                  painter: _StarPainter(color: widget.color),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Painter for a single hand-drawn five-point star.
class _StarPainter extends CustomPainter {
  final Color color;

  _StarPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.46;

    // Soft warm glow.
    canvas.drawCircle(
      center,
      radius * 1.02,
      Paint()..color = color.withValues(alpha: 0.22),
    );

    final star = _starPath(center, radius);
    canvas.drawPath(
      star,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
    // Friendly white outline so it reads as drawn, not a flat glyph.
    canvas.drawPath(
      star,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.045
        ..strokeJoin = StrokeJoin.round,
    );
    // A small highlight on the top-left arm.
    canvas.drawCircle(
      Offset(center.dx - radius * 0.22, center.dy - radius * 0.3),
      radius * 0.12,
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(covariant _StarPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Radial sparkle burst of small stars, shown wherever a reward is popped.
///
/// Public so the milestone scene can burst its trophy with the same gesture
/// the stars use — one popped reward should look like another, whichever it is.
/// Plays once on build and leaves nothing behind; the caller owns removing it.
class RewardPopBurst extends StatefulWidget {
  /// Width/height of the burst, in logical pixels.
  final double size;

  /// The popped reward's own colour, so the sparks match what burst.
  final Color color;

  const RewardPopBurst({super.key, required this.size, required this.color});

  @override
  State<RewardPopBurst> createState() => _RewardPopBurstState();
}

class _RewardPopBurstState extends State<RewardPopBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = Tween<double>(
      begin: 0.6,
      end: 1.3,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _fade = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
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
          opacity: _fade.value,
          child: Transform.scale(
            scale: _scale.value,
            child: CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _StarPopBurstPainter(color: widget.color),
            ),
          ),
        );
      },
    );
  }
}

/// Painter for the star pop burst: a bright core surrounded by small stars
/// radiating outward.
class _StarPopBurstPainter extends CustomPainter {
  final Color color;

  _StarPopBurstPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // Small stars scattering outward.
    const count = 8;
    for (var i = 0; i < count; i++) {
      final angle = i * 2 * pi / count;
      final distance = maxRadius * (0.35 + 0.4 * sin(i * 1.7).abs());
      final starCenter = Offset(
        center.dx + distance * cos(angle),
        center.dy + distance * sin(angle),
      );
      canvas.drawPath(
        _starPath(starCenter, maxRadius * 0.24),
        Paint()
          ..color = color.withValues(alpha: 0.9)
          ..style = PaintingStyle.fill,
      );
    }

    // Bright centre.
    canvas.drawCircle(
      center,
      maxRadius * 0.28,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      maxRadius * 0.4,
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _StarPopBurstPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Simple opacity fade of a star, used for pops under reduced motion.
class _StarFadeOut extends StatefulWidget {
  final double size;
  final Color color;

  const _StarFadeOut({required this.size, required this.color});

  @override
  State<_StarFadeOut> createState() => _StarFadeOutState();
}

class _StarFadeOutState extends State<_StarFadeOut>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _opacity = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
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
        if (_opacity.value <= 0) return const SizedBox.shrink();
        return Opacity(
          opacity: _opacity.value,
          child: CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _StarPainter(color: widget.color),
          ),
        );
      },
    );
  }
}

/// Interactive star field exclusive to the milestone victory scene.
///
/// Stars rise in from below the bottom edge after [appearDelay], staggered so
/// they arrive as a stream rather than a wall, then drift gently with a subtle
/// rotation and scale pulse. Tapping or dragging across
/// a star pops it, playing the star-pop SFX (via [RewardSfxProvider]) and
/// sending out a radial sparkle burst. Under reduced motion stars sit static
/// and pops are a simple fade — but the SFX still plays.
///
/// Count scales with [effectScale] (the game's [GraphicsQuality.effectScale]):
/// base 20 stars. The widget is purely additive; the scene owns its lifecycle.
class StarReward extends StatefulWidget {
  final bool reducedMotion;
  final double effectScale;
  final Duration appearDelay;

  /// Fired once, when the last remaining star has been popped — the child has
  /// cleared the field and has nothing left to collect. A container uses this
  /// to let an eager child move on before the celebration's minimum hold is up.
  /// Never fires more than once, and never fires if a star is still on screen.
  final VoidCallback? onAllPopped;

  const StarReward({
    super.key,
    required this.reducedMotion,
    required this.effectScale,
    this.appearDelay = const Duration(milliseconds: 800),
    this.onAllPopped,
  });

  @override
  State<StarReward> createState() => _StarRewardState();
}

class _StarConfig {
  final GlobalKey<_CollectibleStarState> key;
  final Offset baseFraction;
  final double size;
  final Color color;
  final double driftPhase;

  /// Spawn-delay future, created once so rebuilds don't restart a star.
  final Future<void> spawn;

  /// Backing timer for [spawn], cancelled on dispose so the field never leaks
  /// pending timers into a torn-down tree.
  final Timer? timer;

  const _StarConfig({
    required this.key,
    required this.baseFraction,
    required this.size,
    required this.color,
    required this.driftPhase,
    required this.spawn,
    required this.timer,
  });
}

class _StarRewardState extends State<StarReward> {
  final List<_StarConfig> _stars = [];
  final _random = Random();

  int get _starCount {
    final base = 20;
    return (base * widget.effectScale).round().clamp(3, base);
  }

  @override
  void initState() {
    super.initState();
    _generateStars();
  }

  @override
  void dispose() {
    for (final config in _stars) {
      config.timer?.cancel();
    }
    super.dispose();
  }

  void _generateStars() {
    final count = _starCount;
    _remaining = count;
    for (var i = 0; i < count; i++) {
      final delay = widget.appearDelay + Duration(milliseconds: i * 60);
      final completer = Completer<void>();
      final timer = Timer(delay, completer.complete);
      _stars.add(
        _StarConfig(
          key: GlobalKey<_CollectibleStarState>(),
          baseFraction: Offset(
            0.08 + _random.nextDouble() * 0.84,
            0.12 + _random.nextDouble() * 0.55,
          ),
          size: 34 + _random.nextDouble() * 30,
          color: _starColors[_random.nextInt(_starColors.length)],
          driftPhase: _random.nextDouble() * 2 * pi,
          // Create the spawn future ONCE so rebuilds don't restart the star.
          spawn: completer.future,
          timer: timer,
        ),
      );
    }
  }

  /// How many stars are still waiting to be popped. Counts every generated
  /// star, spawned or not, so a pop landing before the last star has appeared
  /// cannot be mistaken for a cleared field.
  int _remaining = 0;

  /// Guards [StarReward.onAllPopped] against a second dispatch.
  bool _announcedAllPopped = false;

  void _onStarPopped() {
    RewardSfxProvider.playStarPop(context);
    if (_remaining > 0) _remaining--;
    if (_remaining == 0 && !_announcedAllPopped) {
      _announcedAllPopped = true;
      widget.onAllPopped?.call();
    }
  }

  /// Pops any star under the pointer — drag across to pop many smoothly.
  void _handlePointer(PointerEvent event) {
    for (final config in _stars) {
      config.key.currentState?.tryPopAt(event.position);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointer,
      onPointerMove: _handlePointer,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: _stars.map((config) {
          return FutureBuilder(
            key: ObjectKey(config),
            future: config.spawn,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox.shrink();
              }
              return _CollectibleStar(
                key: config.key,
                baseFraction: config.baseFraction,
                size: config.size,
                color: config.color,
                driftPhase: config.driftPhase,
                reducedMotion: widget.reducedMotion,
                onPopped: _onStarPopped,
              );
            },
          );
        }).toList(),
      ),
    );
  }
}
