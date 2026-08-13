import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_animations.dart';
import '../theme/app_colors.dart';
import '../theme/app_gradients.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';
import '../utils/text_fit.dart';
import 'ui_tap_sfx_provider.dart';

/// The app's primary call-to-action.
///
/// The label is never ellipsised: it is centred, wraps across at most
/// [maxLines] lines, and the button grows vertically to hold it. Callers
/// that reserve horizontal space for a CTA — a fixed-width button beside a
/// message, or a breakpoint choosing between a row and a column — should
/// size that space with [minWidthFor] rather than a hand-picked constant,
/// so the reservation tracks the real label and the ambient text scale.
class AppPrimaryButton extends StatefulWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.gradient,
    this.width,
    this.focusNode,
    this.autofocus = false,
    this.maxLines = 2,
    this.textAlign = TextAlign.center,
    this.compact = false,
    this.horizontalPadding,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final LinearGradient? gradient;
  final double? width;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Lines the label may wrap across. Two by default, so a long CTA like
  /// "Start Pre-Assessment" reads in full inside a narrow column.
  final int maxLines;

  final TextAlign textAlign;

  /// Tightens the horizontal padding for buttons in cramped rows. Vertical
  /// padding is untouched, so the touch target is unaffected.
  final bool compact;

  /// Overrides the horizontal padding outright; takes precedence over
  /// [compact].
  final double? horizontalPadding;

  /// Minimum touch target (Material guidance), enforced as a min height.
  static const double minTouchTarget = 48;

  static const double _horizontalPadding = 24;
  static const double _compactHorizontalPadding = 16;
  static const double _iconSize = 20;
  static const double _iconGap = 10;

  static double _paddingFor({bool compact = false, double? horizontalPadding}) {
    return horizontalPadding ??
        (compact ? _compactHorizontalPadding : _horizontalPadding);
  }

  /// Width this button needs for [label] to read in full at the text scale
  /// of [context] — the narrowest width the label still fits [maxLines]
  /// at, plus the icon and the horizontal padding.
  static double minWidthFor(
    BuildContext context, {
    required String label,
    IconData? icon,
    int maxLines = 2,
    bool compact = false,
    double? horizontalPadding,
  }) {
    final textWidth = minWidthToFitLines(
      context,
      text: label,
      style: AppTextStyles.buttonLarge,
      maxLines: maxLines,
    );
    final iconWidth = icon == null ? 0.0 : (_iconSize + _iconGap);
    final padding =
        _paddingFor(compact: compact, horizontalPadding: horizontalPadding) * 2;

    return textWidth + iconWidth + padding;
  }

  @override
  State<AppPrimaryButton> createState() => _AppPrimaryButtonState();
}

class _AppPrimaryButtonState extends State<AppPrimaryButton> {
  bool _pressed = false;
  bool _focused = false;

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space)) {
      final enabled = widget.onPressed != null && !widget.isLoading;
      if (enabled) {
        setState(() => _pressed = true);
        UiTapSfxProvider.play(context);
        widget.onPressed?.call();
        Future.delayed(AppAnimations.tapFeedback, () {
          if (mounted) setState(() => _pressed = false);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.isLoading;

    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (hasFocus) => setState(() => _focused = hasFocus),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          _handleKeyEvent(event);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled
            ? (_) {
                setState(() => _pressed = false);
                UiTapSfxProvider.play(context);
                widget.onPressed?.call();
              }
            : null,
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? AppAnimations.tapScaleFactor : 1.0,
          duration: AppAnimations.tapFeedback,
          curve: AppAnimations.defaultCurve,
          child: AnimatedOpacity(
            opacity: enabled ? 1.0 : 0.6,
            duration: AppAnimations.tapFeedback,
            child: Container(
              width: widget.width ?? double.infinity,
              constraints: const BoxConstraints(
                minHeight: AppPrimaryButton.minTouchTarget,
              ),
              padding: EdgeInsets.symmetric(
                vertical: 18,
                horizontal: AppPrimaryButton._paddingFor(
                  compact: widget.compact,
                  horizontalPadding: widget.horizontalPadding,
                ),
              ),
              decoration: BoxDecoration(
                gradient: enabled
                    ? (widget.gradient ?? AppGradients.primaryCta)
                    : null,
                color: enabled ? null : AppColors.lavender,
                borderRadius: AppRadius.button,
                boxShadow: enabled ? AppShadows.interactive : null,
                border: _focused && enabled
                    ? Border.all(
                        color: AppColors.white,
                        width: 2,
                      )
                    : null,
              ),
              child: Center(
                child: widget.isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.white,
                        ),
                      )
                    // Icon and label stay a single centred group. The label
                    // is Flexible so it wraps to [maxLines] instead of being
                    // ellipsised in a narrow row, and the button grows
                    // vertically to hold the wrapped text.
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (widget.icon != null) ...[
                            Icon(widget.icon,
                                color: AppColors.white,
                                size: AppPrimaryButton._iconSize),
                            const SizedBox(width: AppPrimaryButton._iconGap),
                          ],
                          Flexible(
                            child: Text(
                              widget.label,
                              style: AppTextStyles.buttonLarge,
                              textAlign: widget.textAlign,
                              softWrap: true,
                              maxLines: widget.maxLines,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

