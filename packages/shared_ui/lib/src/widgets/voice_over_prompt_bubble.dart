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
    this.onPlayVoiceOver,
    this.autoPlayOnAppear = true,
  });

  final String text;
  final bool isVisible;

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
      child: widget.isVisible
          ? Container(
              key: const ValueKey('voice_over_prompt_bubble_visible'),
              constraints: const BoxConstraints(maxWidth: 400),
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
                  GestureDetector(
                    onTap: widget.onPlayVoiceOver,
                    child: const Icon(
                      Icons.volume_up_rounded,
                      color: AppColors.primaryPurple,
                      size: 22,
                    ),
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
            )
          : const SizedBox(
              key: ValueKey('voice_over_prompt_bubble_hidden'),
            ),
    );
  }
}
