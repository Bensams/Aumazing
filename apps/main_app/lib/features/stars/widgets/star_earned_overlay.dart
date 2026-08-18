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
  const StarEarnedOverlay({
    super.key,
    required this.granted,
    this.headline,
    this.note,
  });

  final int granted;

  /// Replaces the "you earned N stars" line. Set when nothing was earned and
  /// the moment is explaining why instead (AUM-286).
  final String? headline;

  /// An optional quieter second line under [headline], for what to do next.
  final String? note;

  /// True when this is the earning moment rather than the explaining one.
  bool get _isEarning => granted > 0;

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

  /// The same moment, for a game that finished without earning (AUM-286).
  ///
  /// Same card, same timing, same gentle settle — and deliberately no chime,
  /// because the chime means stars arrived and nothing arrived here. What it
  /// must not be is a warning: the child finished a game, which is the thing
  /// the app wants, and is simply being told where today's remaining stars
  /// are. Showing nothing at all was the alternative, and "do the thing,
  /// receive silence" is the shape this app avoids everywhere else.
  static Future<void> showNothingEarned(
    BuildContext context, {
    required String headline,
    String? note,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black26,
      builder: (_) => StarEarnedOverlay(
        granted: 0,
        headline: headline,
        note: note,
      ),
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

      // The chime is the sound of stars arriving, so it only plays when some
      // did. A reward sound for no reward teaches the sound means nothing.
      if (widget._isEarning && (profile?.sfxVolume ?? 0) > 0) {
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
                if (widget._isEarning)
                  Text(
                    '⭐' * widget.granted,
                    style: const TextStyle(fontSize: 44),
                  )
                else
                  // One star with a tick, matching the lobby card's badge for
                  // the same state (AUM-285) — a child meets one symbol for
                  // "already got this one", not two.
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('⭐', style: TextStyle(fontSize: 44)),
                      SizedBox(width: AppSpacing.xs),
                      Icon(
                        Icons.check_rounded,
                        size: 36,
                        color: Color(0xFF6FAE97),
                      ),
                    ],
                  ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  widget.headline ??
                      (widget.granted == 1
                          ? 'You earned 1 star!'
                          : 'You earned ${widget.granted} stars!'),
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                if (widget.note != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    widget.note!,
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
