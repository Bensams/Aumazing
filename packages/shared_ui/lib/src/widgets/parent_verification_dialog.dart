import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Digit-to-English-word mapping.
const _digitWords = [
  'zero',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
];

/// A modal dialog that requires a parent to type a 4-digit code shown as
/// English words, using an on-screen numpad (no keyboard).
class ParentVerificationDialog extends StatefulWidget {
  const ParentVerificationDialog({super.key});

  /// Shows the dialog and returns `true` if the parent verified successfully.
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: AppColors.foreground.withAlpha(120),
      builder: (_) => const ParentVerificationDialog(),
    );
    return result ?? false;
  }

  @override
  State<ParentVerificationDialog> createState() =>
      _ParentVerificationDialogState();
}

class _ParentVerificationDialogState extends State<ParentVerificationDialog> {
  /// The randomly generated 4-digit code (each digit 0-9).
  late final List<int> _code;

  /// Digits entered by the user via the on-screen numpad.
  String _enteredCode = '';

  /// Error message shown after an incorrect attempt.
  String? _error;

  @override
  void initState() {
    super.initState();
    final rng = Random();
    _code = List.generate(4, (_) => rng.nextInt(10));
  }

  // ── Numpad callbacks ────────────────────────────────────────────────────

  void _onDigitPressed(int digit) {
    if (_enteredCode.length >= 4) return;
    setState(() {
      _enteredCode += digit.toString();
      _error = null;
    });
  }

  void _onBackspace() {
    if (_enteredCode.isEmpty) return;
    setState(() {
      _enteredCode = _enteredCode.substring(0, _enteredCode.length - 1);
      _error = null;
    });
  }

  void _onSubmit() {
    if (_enteredCode.length != 4) return;
    final expected = _code.join();
    if (_enteredCode == expected) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _error = 'Incorrect code. Try again.';
        _enteredCode = '';
      });
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    // Constrain dialog to fit within the screen with some margin
    final maxDialogHeight = screenSize.height * 0.88;
    final maxDialogWidth = min(480.0, screenSize.width * 0.85);

    return Dialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Container(
        padding: AppSpacing.paddingMd,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: AppRadius.card,
          boxShadow: AppShadows.modal,
        ),
        constraints: BoxConstraints(
          maxWidth: maxDialogWidth,
          maxHeight: maxDialogHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header (compact, single row) ─────────────────────────
            _buildHeader(),
            const SizedBox(height: AppSpacing.sm),

            // ── Two-column body ──────────────────────────────────────
            Flexible(
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Left column – code words + indicator dots
                    Expanded(child: _buildLeftColumn()),
                    const SizedBox(width: AppSpacing.md),
                    // Right column – numpad
                    _buildNumpad(),
                  ],
                ),
              ),
            ),

            // ── Error message ────────────────────────────────────────
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                _error!,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.destructiveSoftRed,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Row(
      children: [
        // Lock icon (compact)
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.lavenderLight,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.lock_outline_rounded,
            color: AppColors.primaryPurple,
            size: 18,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        // Title + subtitle
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Parent Verification',
                style: AppTextStyles.titleLarge,
              ),
              Text(
                'Enter the code shown below:',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
        // Close / cancel button
        GestureDetector(
          onTap: () => Navigator.of(context).pop(false),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.muted,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.close_rounded,
              color: AppColors.mutedForeground,
              size: 18,
            ),
          ),
        ),
      ],
    );
  }

  // ── Left column: digit words (horizontal) + input indicators ────────────

  Widget _buildLeftColumn() {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.md),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Word label
                Text(
                  _digitWords[_code[i]],
                  style: AppTextStyles.headlineMedium.copyWith(
                    color: AppColors.primaryPurple,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                // Indicator circle directly below its word
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: i < _enteredCode.length
                        ? AppColors.primaryPurple
                        : AppColors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: i < _enteredCode.length
                          ? AppColors.primaryPurple
                          : AppColors.border,
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: i < _enteredCode.length
                      ? Text(
                          _enteredCode[i],
                          style: AppTextStyles.titleMedium.copyWith(
                            color: AppColors.white,
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Right column: numpad ────────────────────────────────────────────────

  Widget _buildNumpad() {
    const double buttonSize = 46;
    const double gap = 6;

    Widget digitButton(int digit) {
      return _NumpadButton(
        size: buttonSize,
        onTap: () => _onDigitPressed(digit),
        color: AppColors.lavenderLight,
        child: Text(
          '$digit',
          style: AppTextStyles.titleLarge.copyWith(
            color: AppColors.foreground,
          ),
        ),
      );
    }

    Widget backspaceButton() {
      return _NumpadButton(
        size: buttonSize,
        onTap: _onBackspace,
        color: AppColors.muted,
        child: const Icon(
          Icons.backspace_outlined,
          color: AppColors.mutedForeground,
          size: 20,
        ),
      );
    }

    Widget submitButton() {
      final active = _enteredCode.length == 4;
      return _NumpadButton(
        size: buttonSize,
        onTap: active ? _onSubmit : null,
        color: active ? AppColors.primaryPurple : AppColors.disabledFill,
        child: Icon(
          Icons.check_rounded,
          color: active ? AppColors.white : AppColors.mutedForeground,
          size: 22,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Row 1: 1 2 3
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            digitButton(1),
            SizedBox(width: gap),
            digitButton(2),
            SizedBox(width: gap),
            digitButton(3),
          ],
        ),
        SizedBox(height: gap),
        // Row 2: 4 5 6
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            digitButton(4),
            SizedBox(width: gap),
            digitButton(5),
            SizedBox(width: gap),
            digitButton(6),
          ],
        ),
        SizedBox(height: gap),
        // Row 3: 7 8 9
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            digitButton(7),
            SizedBox(width: gap),
            digitButton(8),
            SizedBox(width: gap),
            digitButton(9),
          ],
        ),
        SizedBox(height: gap),
        // Row 4: ⌫ 0 ✓
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            backspaceButton(),
            SizedBox(width: gap),
            digitButton(0),
            SizedBox(width: gap),
            submitButton(),
          ],
        ),
      ],
    );
  }
}

// ── Reusable numpad button ──────────────────────────────────────────────────

class _NumpadButton extends StatelessWidget {
  const _NumpadButton({
    required this.size,
    required this.onTap,
    required this.color,
    required this.child,
  });

  final double size;
  final VoidCallback? onTap;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: onTap != null ? AppShadows.card : null,
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}
