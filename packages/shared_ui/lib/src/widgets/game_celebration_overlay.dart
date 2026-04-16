import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// A full-screen celebration overlay with animated stars, emojis,
/// and an encouraging message. ASD-friendly: uses soft colors,
/// gentle animations, and no loud effects.
class GameCelebrationOverlay extends StatefulWidget {
  const GameCelebrationOverlay({
    super.key,
    required this.message,
    this.emoji = '🌟',
    this.subMessage,
    this.isBigCelebration = false,
  });

  final String message;
  final String emoji;
  final String? subMessage;

  /// If true, shows a grander celebration (end of all games).
  final bool isBigCelebration;

  @override
  State<GameCelebrationOverlay> createState() => _GameCelebrationOverlayState();
}

class _GameCelebrationOverlayState extends State<GameCelebrationOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final AnimationController _starsController;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  final _rng = math.Random();
  late final List<_FloatingStar> _stars;

  @override
  void initState() {
    super.initState();

    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );
    _fadeAnim = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeIn,
    );

    _starsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    final count = widget.isBigCelebration ? 20 : 10;
    _stars = List.generate(count, (_) => _FloatingStar(
      emoji: _randomEmoji(),
      x: _rng.nextDouble(),
      delay: _rng.nextDouble() * 0.6,
      speed: 0.3 + _rng.nextDouble() * 0.7,
      size: 18.0 + _rng.nextDouble() * 20,
      wobble: _rng.nextDouble() * 2 - 1,
    ));

    _scaleController.forward();
    _starsController.forward();
  }

  String _randomEmoji() {
    const emojis = ['⭐', '🌟', '✨', '💫', '🎉', '🎈', '🏆', '💖'];
    return emojis[_rng.nextInt(emojis.length)];
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _starsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_scaleController, _starsController]),
      builder: (context, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // Semi-transparent backdrop
            FadeTransition(
              opacity: _fadeAnim,
              child: Container(
                color: Colors.black.withAlpha(60),
              ),
            ),

            // Floating stars/emojis
            ..._stars.map((star) {
              final t = (_starsController.value - star.delay)
                  .clamp(0.0, 1.0) /
                  (1.0 - star.delay).clamp(0.01, 1.0);
              final progress = t.clamp(0.0, 1.0);
              final y = 1.0 - progress * star.speed;
              final x = star.x + math.sin(progress * math.pi * 2) * star.wobble * 0.05;

              return Positioned(
                left: x * MediaQuery.of(context).size.width,
                top: y * MediaQuery.of(context).size.height,
                child: Opacity(
                  opacity: (1.0 - progress).clamp(0.0, 1.0),
                  child: Text(
                    star.emoji,
                    style: TextStyle(fontSize: star.size),
                  ),
                ),
              );
            }),

            // Center content
            Center(
              child: ScaleTransition(
                scale: _scaleAnim,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.emoji,
                      style: TextStyle(
                        fontSize: widget.isBigCelebration ? 72 : 56,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.white.withAlpha(230),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.message,
                            style: AppTextStyles.headlineLarge.copyWith(
                              color: AppColors.primaryPurple,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (widget.subMessage != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              widget.subMessage!,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.mutedForeground,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FloatingStar {
  final String emoji;
  final double x;
  final double delay;
  final double speed;
  final double size;
  final double wobble;

  const _FloatingStar({
    required this.emoji,
    required this.x,
    required this.delay,
    required this.speed,
    required this.size,
    required this.wobble,
  });
}
