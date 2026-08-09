import 'dart:async';
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

/// Outcome of one custom-PIN attempt.
enum ParentPinAttempt {
  correct,

  /// Wrong PIN, tries still available.
  incorrect,

  /// Throttled after too many wrong tries — see
  /// [ParentPinDelegate.lockoutRemaining] for how long.
  lockedOut,
}

/// App-supplied hooks that let [ParentVerificationDialog] challenge with a
/// parent-chosen PIN instead of the on-screen word code.
///
/// This package deliberately knows nothing about storage, accounts, or
/// email; the host app implements those and installs the delegate once at
/// startup via [ParentVerificationDialog.pinDelegate]. When no delegate is
/// installed — or [hasPin] is false — the dialog falls back to the word-code
/// challenge, so callers never have to branch.
abstract class ParentPinDelegate {
  /// True when a custom PIN is configured and should be used.
  bool get hasPin;

  /// Checks [pin]. Implementations own the brute-force throttle.
  Future<ParentPinAttempt> verify(String pin);

  /// Time left on the cooldown, or null when entry is allowed.
  Duration? get lockoutRemaining;

  /// Runs the app's "forgot PIN" recovery flow. Return true when the parent
  /// proved ownership (and the gate should therefore open).
  Future<bool> onForgotPin(BuildContext context);
}

/// A modal dialog that verifies a parent before leaving child mode.
///
/// Two challenge types, chosen by whether a [ParentPinDelegate] with a PIN
/// is installed:
/// - **Word code** (default): a fresh random 4-digit code rendered as English
///   words, typed back on an on-screen numpad. Keeps pre-readers out with
///   nothing for the parent to remember.
/// - **Custom PIN**: a 4-digit PIN the parent chose. Nothing on screen
///   reveals it, so it also holds against a child who can read.
class ParentVerificationDialog extends StatefulWidget {
  const ParentVerificationDialog({super.key});

  /// Installed once at app startup. Null leaves every call site on the
  /// word-code challenge.
  static ParentPinDelegate? pinDelegate;

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
  /// The randomly generated 4-digit code (each digit 0-9). Word-code mode only.
  late final List<int> _code;

  /// The delegate captured at open time, when it has a PIN to check against.
  late final ParentPinDelegate? _pin;

  /// Digits entered by the user via the on-screen numpad.
  String _enteredCode = '';

  /// Error message shown after an incorrect attempt.
  String? _error;

  /// True while an async PIN check is running (numpad disabled).
  bool _checking = false;

  /// Seconds left on the throttle cooldown; null when entry is allowed.
  int? _lockoutSeconds;
  Timer? _lockoutTimer;

  bool get _usesPin => _pin != null;

  @override
  void initState() {
    super.initState();
    final rng = Random();
    _code = List.generate(4, (_) => rng.nextInt(10));

    final delegate = ParentVerificationDialog.pinDelegate;
    _pin = (delegate != null && delegate.hasPin) ? delegate : null;

    // A cooldown may already be running from an earlier attempt — including
    // one in a previous app session, since the throttle is persisted.
    final remaining = _pin?.lockoutRemaining;
    if (remaining != null) _startLockout(remaining);
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }

  void _startLockout(Duration remaining) {
    _lockoutTimer?.cancel();
    _lockoutSeconds = remaining.inSeconds.clamp(1, 3600);
    _enteredCode = '';
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        final left = (_lockoutSeconds ?? 1) - 1;
        if (left <= 0) {
          _lockoutSeconds = null;
          _error = null;
          timer.cancel();
        } else {
          _lockoutSeconds = left;
        }
      });
    });
  }

  bool get _inputDisabled => _checking || _lockoutSeconds != null;

  // ── Numpad callbacks ────────────────────────────────────────────────────

  void _onDigitPressed(int digit) {
    if (_inputDisabled || _enteredCode.length >= 4) return;
    setState(() {
      _enteredCode += digit.toString();
      _error = null;
    });
  }

  void _onBackspace() {
    if (_inputDisabled || _enteredCode.isEmpty) return;
    setState(() {
      _enteredCode = _enteredCode.substring(0, _enteredCode.length - 1);
      _error = null;
    });
  }

  Future<void> _onSubmit() async {
    if (_inputDisabled || _enteredCode.length != 4) return;

    final delegate = _pin;
    if (delegate == null) {
      // Word-code mode: compare against the code shown on screen.
      if (_enteredCode == _code.join()) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _error = 'Incorrect code. Try again.';
          _enteredCode = '';
        });
      }
      return;
    }

    setState(() => _checking = true);
    final outcome = await delegate.verify(_enteredCode);
    if (!mounted) return;

    switch (outcome) {
      case ParentPinAttempt.correct:
        setState(() => _checking = false);
        Navigator.of(context).pop(true);
      case ParentPinAttempt.incorrect:
        setState(() {
          _checking = false;
          _error = 'Incorrect PIN. Try again.';
          _enteredCode = '';
        });
      case ParentPinAttempt.lockedOut:
        setState(() {
          _checking = false;
          _error = null;
          _startLockout(
            delegate.lockoutRemaining ?? const Duration(seconds: 60),
          );
        });
    }
  }

  Future<void> _onForgotPin() async {
    final delegate = _pin;
    if (delegate == null) return;
    final verified = await delegate.onForgotPin(context);
    if (!mounted) return;
    if (verified) Navigator.of(context).pop(true);
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
                    // Left column – code words (or PIN prompt) + dots
                    Expanded(child: _buildLeftColumn()),
                    const SizedBox(width: AppSpacing.md),
                    // Right column – numpad
                    _buildNumpad(),
                  ],
                ),
              ),
            ),

            // ── Cooldown / error message ─────────────────────────────
            if (_lockoutSeconds != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Too many tries. Try again in ${_lockoutSeconds}s.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.destructiveRed,
                ),
              ),
            ] else if (_error != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                _error!,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.destructiveRed,
                ),
              ),
            ],

            if (_usesPin) ...[
              const SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: _checking ? null : _onForgotPin,
                child: Text(
                  'Forgot PIN?',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primaryPurple,
                    fontWeight: FontWeight.w600,
                  ),
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
                _usesPin
                    ? 'Enter your parent PIN:'
                    : 'Enter the code shown below:',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
        // Close / cancel button.
        //
        // The grey circle stays 32dp — it is a quiet control and should not
        // compete with the header — but the *tappable* area is padded out to
        // the 48dp minimum, and the icon is named so it is not just an
        // unlabelled button next to the PIN pad.
        Semantics(
          button: true,
          label: 'Cancel',
          excludeSemantics: true,
          child: InkResponse(
            onTap: () => Navigator.of(context).pop(false),
            radius: kMinInteractiveDimension / 2,
            child: Container(
              width: kMinInteractiveDimension,
              height: kMinInteractiveDimension,
              alignment: Alignment.center,
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
                // Word label — the challenge in word-code mode. In PIN mode
                // there is nothing to show: revealing anything here would
                // hand the PIN to whoever is looking at the screen.
                Text(
                  _usesPin ? '•' : _digitWords[_code[i]],
                  style: AppTextStyles.headlineMedium.copyWith(
                    color: _usesPin
                        ? AppColors.border
                        : AppColors.primaryPurple,
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
                  // PIN mode masks the entry — a child watching over a
                  // shoulder must not be able to read it back.
                  child: i < _enteredCode.length
                      ? Text(
                          _usesPin ? '•' : _enteredCode[i],
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
    // The pad measured 46dp per key, under the 48dp minimum the rest of the
    // app now holds to (and the figure TC-AU-028 tests for).
    const double buttonSize = kMinInteractiveDimension;
    const double gap = 6;

    Widget digitButton(int digit) {
      return _NumpadButton(
        key: ValueKey('numpad_$digit'),
        size: buttonSize,
        semanticLabel: '$digit',
        onTap: _inputDisabled ? null : () => _onDigitPressed(digit),
        color: _inputDisabled
            ? AppColors.disabledFill
            : AppColors.lavenderLight,
        child: Text(
          '$digit',
          style: AppTextStyles.titleLarge.copyWith(
            color: _inputDisabled
                ? AppColors.mutedForeground
                : AppColors.foreground,
          ),
        ),
      );
    }

    Widget backspaceButton() {
      return _NumpadButton(
        key: const ValueKey('numpad_backspace'),
        size: buttonSize,
        semanticLabel: 'Delete last digit',
        onTap: _inputDisabled ? null : _onBackspace,
        color: AppColors.muted,
        child: const Icon(
          Icons.backspace_outlined,
          color: AppColors.mutedForeground,
          size: 20,
        ),
      );
    }

    Widget submitButton() {
      final active = _enteredCode.length == 4 && !_inputDisabled;
      return _NumpadButton(
        key: const ValueKey('numpad_submit'),
        size: buttonSize,
        semanticLabel: _checking ? 'Checking' : 'Confirm',
        onTap: active ? _onSubmit : null,
        color: active ? AppColors.primaryPurple : AppColors.disabledFill,
        child: _checking
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.mutedForeground,
                ),
              )
            : Icon(
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
    super.key,
    required this.size,
    required this.onTap,
    required this.color,
    required this.semanticLabel,
    required this.child,
  });

  final double size;
  final VoidCallback? onTap;
  final Color color;

  /// Spoken name for the key. The digit keys draw their number, but backspace
  /// and submit are bare icons — a screen-reader user got two unnamed buttons
  /// at the end of the pad with no way to tell delete from confirm.
  final String semanticLabel;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel,
      onTap: onTap,
      // The drawn digit would otherwise be published as a second node inside
      // the button, so every key announced its number twice.
      excludeSemantics: true,
      child: GestureDetector(
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
      ),
    );
  }
}
