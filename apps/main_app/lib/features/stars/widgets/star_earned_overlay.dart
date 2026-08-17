import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../providers/child_provider.dart';

/// The short "you earned stars" moment (STAR-B2).
///
/// Sits *after* the celebration overlay, never on top of it. The celebration
/// is about the game the child just finished; this is about what it earned
/// them. Stacking the two would make both unreadable and the screen loud —
/// which for this audience is not a style problem but a sensory one.
///
/// Everything here is deliberately calm and brief:
///
///  * under two seconds, then it leaves on its own;
///  * a single fade and a small settle — nothing flashes, strobes or zooms;
///  * scaled by the child's `animationIntensity`, and effectively still at 0;
///  * silent when SFX volume is 0.
class StarEarnedOverlay extends StatefulWidget {
  const StarEarnedOverlay({super.key, required this.granted});

  final int granted;

  /// Shows the moment and completes when it has gone. Awaiting this keeps the
  /// end-of-game sequence in order: celebration → stars → what next?
  static Future<void> show(BuildContext context, {required int granted}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black26,
      builder: (_) => StarEarnedOverlay(granted: granted),
    );
  }

  @override
  State<StarEarnedOverlay> createState() => _StarEarnedOverlayState();
}

class _StarEarnedOverlayState extends State<StarEarnedOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      final profile = context.read<ChildProvider>().profile;
      final intensity = profile?.animationIntensity ?? 1.0;

      // Reduced motion is honoured by skipping the animation, not by speeding
      // it up: a faster flash is worse for a child sensitive to movement, not
      // better. At zero the card simply appears.
      if (intensity <= 0 ||
          MediaQuery.maybeOf(context)?.disableAnimations == true) {
        _controller.value = 1;
      } else {
        _controller.animateTo(1, curve: AppAnimations.gentleCurve);
      }

      if ((profile?.sfxVolume ?? 0) > 0) {
        // The star chime already ships in every dialect's asset bundle, so the
        // currency needed no new audio.
        unawaited(context.read<AudioService>().playSfx('3_star'));
      }

      await Future<void>.delayed(const Duration(milliseconds: 1800));
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: FadeTransition(
        opacity: _controller,
        child: ScaleTransition(
          // A small settle from 96% — not a pop from zero. The difference is
          // the difference between "noticed" and "startled".
          scale: Tween<double>(begin: 0.96, end: 1).animate(_controller),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.lg,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: AppRadius.extraLargeBorder,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '⭐' * widget.granted,
                  style: const TextStyle(fontSize: 44),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  widget.granted == 1
                      ? 'You earned 1 star!'
                      : 'You earned ${widget.granted} stars!',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
