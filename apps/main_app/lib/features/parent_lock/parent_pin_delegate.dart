import 'package:flutter/material.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../core/services/auth_service.dart';
import '../../services/parent_pin_service.dart';
import 'parent_pin_reset_screen.dart';

/// Bridges the app's [ParentPinService] and account state into the
/// [ParentVerificationDialog] that lives in `shared_ui`.
///
/// Installed once at startup (see `main.dart`), which is why the eight
/// existing `ParentVerificationDialog.show(context)` call sites needed no
/// changes: the dialog picks the challenge itself, falling back to the word
/// code whenever no PIN is configured.
class AppParentPinDelegate implements ParentPinDelegate {
  const AppParentPinDelegate();

  @override
  bool get hasPin => ParentPinService.instance.hasPin;

  @override
  Duration? get lockoutRemaining => ParentPinService.instance.lockoutRemaining;

  @override
  Future<ParentPinAttempt> verify(String pin) async {
    final result = await ParentPinService.instance.verify(pin);
    switch (result.status) {
      case PinVerifyStatus.correct:
        return ParentPinAttempt.correct;
      case PinVerifyStatus.incorrect:
        return ParentPinAttempt.incorrect;
      case PinVerifyStatus.lockedOut:
        return ParentPinAttempt.lockedOut;
    }
  }

  @override
  Future<bool> onForgotPin(BuildContext context) async {
    final email = AuthService().verifiedEmail;
    if (email == null) {
      // Should be unreachable: a PIN can only be set on an account with a
      // confirmed email. Handled anyway so a changed email can never leave
      // a parent stranded with no visible explanation.
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No confirmed email on this account. Sign in on another '
              'device to reset your PIN.',
            ),
            backgroundColor: AppColors.destructiveRed,
          ),
        );
      }
      return false;
    }
    if (!context.mounted) return false;
    return ParentPinResetScreen.push(context, email);
  }
}
