import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// A soft bubble that displays a voice-over prompt text. Positioned at the
/// bottom of child screens, transparent enough not to block gameplay.
///
/// Optionally plays a voice-over audio cue when the bubble appears or when
/// the speaker icon is tapped via [onPlayVoiceOver].
class VoiceOverPromptBubble extends StatefulWidget {
  const VoiceOverPromptBubble({
    super.key,
    required this.text,
    this.isVisible = true,
    this.showText = true,
    this.onPlayVoiceOver,
    this.autoPlayOnAppear = true,
  });

  final String text;

  /// Whether the prompt is *active*. This drives the voice-over, so it stays
  /// true even when the caption itself is turned off.
  final bool isVisible;

  /// Whether the caption is drawn. Turning this off hides the text but leaves
  /// [isVisible] — and therefore the spoken prompt — untouched, so a child who
  /// can't read still hears the instruction.
  final bool showText;

  /// Optional callback to play voice-over audio. Called when the bubble
  /// appears (if [autoPlayOnAppear] is true) and when the speaker icon
  /// is tapped.
  final VoidCallback? onPlayVoiceOver;

  /// Whether to automatically play voice-over when the bubble becomes visible.
  /// Defaults to true.
  final bool autoPlayOnAppear;

  @override
  State<VoiceOverPromptBubble> createState() => _VoiceOverPromptBubbleState();
}

class _VoiceOverPromptBubbleState extends State<VoiceOverPromptBubble> {
  bool _wasVisible = false;

  @override
  void didUpdateWidget(covariant VoiceOverPromptBubble oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Auto-play voice-over when bubble transitions from hidden → visible
    if (widget.autoPlayOnAppear &&
        widget.isVisible &&
        !_wasVisible &&
        widget.onPlayVoiceOver != null) {
      widget.onPlayVoiceOver!();
    }
    _wasVisible = widget.isVisible;
  }

  @override
  void initState() {
    super.initState();
    _wasVisible = widget.isVisible;

    // Auto-play on first build if visible
    if (widget.autoPlayOnAppear &&
        widget.isVisible &&
        widget.onPlayVoiceOver != null) {
      // Use post-frame callback to avoid calling during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onPlayVoiceOver?.call();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            axis: Axis.vertical,
            child: child,
          ),
        );
      },
      child: (widget.isVisible && widget.showText)
          ? Semantics(
              // The speaker icon used to be the only thing that replayed the
              // prompt: a 22dp tap target with no accessible name, on the one
              // control a child who missed the instruction needs most. The
              // whole bubble is the button now — far easier to hit with
              // developing fine motor control — and it carries a single named
              // node instead of an unlabelled inner one.
              button: true,
              label: widget.text,
              hint: 'Plays the instruction again',
              excludeSemantics: true,
              onTap: widget.onPlayVoiceOver,
              child: GestureDetector(
                onTap: widget.onPlayVoiceOver,
                child: Container(
                  key: const ValueKey('voice_over_prompt_bubble_visible'),
                  // Capped against the screen as well as an absolute maximum:
                  // the bubble sits in the upper-left of a bar whose centre
                  // holds the progress dots, and a fixed 400 would reach them
                  // on a narrow landscape phone. The minimum height keeps the
                  // bubble at or above the 48dp touch target minimum.
                  constraints: BoxConstraints(
                    minHeight: kMinInteractiveDimension,
                    maxWidth: math.min(
                      400,
                      MediaQuery.sizeOf(context).width * 0.38,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.white.withAlpha(230),
                    borderRadius: AppRadius.largeBorder,
                    boxShadow: AppShadows.card,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.volume_up_rounded,
                        color: AppColors.primaryPurple,
                        size: 22,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          widget.text,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.foreground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : const SizedBox(
              key: ValueKey('voice_over_prompt_bubble_hidden'),
            ),
    );
  }
}
