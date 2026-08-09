import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../core/services/auth_service.dart';
import '../../core/utils/network_errors.dart';
import '../../services/parent_pin_service.dart';

/// Recovery for a forgotten parent PIN.
///
/// The PIN itself is never mailed out. Two reasons, both of which bite in
/// this product specifically: the recovery mail usually lands on the very
/// tablet the child is holding, so a mailed PIN would defeat the lock it
/// recovers; and parents reuse 4-digit PINs from phone locks and bank cards,
/// so a plaintext copy sitting in an inbox is a liability we should not
/// create. Instead the parent proves they own the account with a one-time
/// code and then chooses a *new* PIN.
///
/// Requires network. Resets are rare and the alternative — an offline
/// fallback challenge — would just be a second, weaker way past the lock.
class ParentPinResetScreen extends StatefulWidget {
  const ParentPinResetScreen({super.key, required this.email});

  /// The account's confirmed email address.
  final String email;

  /// Pushes the flow. Returns true once the parent has verified their email
  /// and set a new PIN.
  static Future<bool> push(BuildContext context, String email) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ParentPinResetScreen(email: email)),
    );
    return result ?? false;
  }

  @override
  State<ParentPinResetScreen> createState() => _ParentPinResetScreenState();
}

class _ParentPinResetScreenState extends State<ParentPinResetScreen> {
  final _authService = AuthService();

  static const int _codeLength = 6;
  final List<TextEditingController> _otpControllers =
      List.generate(_codeLength, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes =
      List.generate(_codeLength, (_) => FocusNode());

  final _pinFormKey = GlobalKey<FormState>();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  bool _isLoading = false;
  bool _sent = false;
  bool _codeVerified = false;
  bool _canResend = false;
  int _resendCountdown = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    lockParentAdaptive();
  }

  @override
  void dispose() {
    lockParentAdaptive();
    _timer?.cancel();
    _pinController.dispose();
    _confirmPinController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startResendTimer() {
    setState(() {
      _canResend = false;
      _resendCountdown = 60;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown <= 1) {
        timer.cancel();
        if (mounted) setState(() => _canResend = true);
      } else {
        if (mounted) setState(() => _resendCountdown--);
      }
    });
  }

  String get _otpCode => _otpControllers.map((c) => c.text).join();

  Future<void> _sendCode() async {
    setState(() => _isLoading = true);
    try {
      // Reuses the account-recovery OTP: verifying it proves the parent
      // controls the account's mailbox, which is exactly the assurance a PIN
      // reset needs.
      await _authService.sendPasswordResetOTP(widget.email);
      if (mounted) {
        setState(() => _sent = true);
        _startResendTimer();
      }
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError(friendly(
        e,
        fallback: 'Could not send the code. Check your connection and '
            'try again.',
      ));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onDigitChanged(int index, String value) {
    if (value.length == 1 && index < _codeLength - 1) {
      _otpFocusNodes[index + 1].requestFocus();
    }
    if (_otpCode.length == _codeLength) _verifyCode();
  }

  void _onKeyEvent(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _otpControllers[index].text.isEmpty &&
        index > 0) {
      _otpControllers[index - 1].clear();
      _otpFocusNodes[index - 1].requestFocus();
    }
  }

  Future<void> _verifyCode() async {
    final code = _otpCode;
    if (code.length != _codeLength) {
      _showError('Please enter the full $_codeLength-digit code.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _authService.verifyPasswordResetOTP(
        email: widget.email,
        token: code,
      );
      // Owning the mailbox is stronger proof than the PIN, so drop any
      // running cooldown rather than making the parent wait it out.
      await ParentPinService.instance.clearThrottle();
      if (mounted) setState(() => _codeVerified = true);
    } on AuthException catch (e) {
      _showError(e.message);
      _clearOtpFields();
    } catch (e) {
      _showError(friendly(e, fallback: 'Verification failed. Try again.'));
      _clearOtpFields();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _savePin() async {
    if (!_pinFormKey.currentState!.validate()) return;
    await ParentPinService.instance.setPin(_pinController.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Your new parent PIN is saved.'),
        backgroundColor: AppColors.mint,
      ),
    );
    Navigator.of(context).pop(true);
  }

  void _clearOtpFields() {
    for (final c in _otpControllers) {
      c.clear();
    }
    _otpFocusNodes[0].requestFocus();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.destructiveRed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ParentModeTopBar(
        title: '',
        onBack: () => Navigator.of(context).pop(false),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.parentSkyButter),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: AppSpacing.horizontalLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.lg),
                _buildHeader(),
                const SizedBox(height: AppSpacing.xxl),
                if (!_sent)
                  _buildSendStep()
                else if (!_codeVerified)
                  _buildCodeStep()
                else
                  _buildNewPinStep(),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final String title;
    final String subtitle;
    if (!_sent) {
      title = 'Reset Parent PIN';
      subtitle = "We'll email a one-time code to the address on your "
          "account. For your child's safety we never send the PIN itself — "
          "you'll choose a new one after verifying.";
    } else if (!_codeVerified) {
      title = 'Enter Reset Code';
      subtitle = 'We sent a verification code to';
    } else {
      title = 'Set New PIN';
      subtitle = 'Choose a 4-digit PIN your child cannot guess.';
    }

    return Center(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppColors.lavenderLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _codeVerified ? Icons.lock_open : Icons.lock_reset,
              size: 56,
              color: AppColors.primaryPurple,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyles.headlineLarge.copyWith(
              color: AppColors.primaryPurple,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: AppSpacing.horizontalLg,
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.mutedForeground,
              ),
            ),
          ),
          if (_sent && !_codeVerified) ...[
            const SizedBox(height: 4),
            Text(
              widget.email,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleLarge.copyWith(
                color: AppColors.primaryPurple,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSendStep() {
    return AppPrimaryButton(
      label: 'Email Me a Code',
      onPressed: _isLoading ? null : _sendCode,
      isLoading: _isLoading,
    );
  }

  Widget _buildCodeStep() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(_codeLength, (index) {
            return SizedBox(
              width: 48,
              child: KeyboardListener(
                focusNode: FocusNode(),
                onKeyEvent: (event) => _onKeyEvent(index, event),
                child: TextFormField(
                  controller: _otpControllers[index],
                  focusNode: _otpFocusNodes[index],
                  enabled: !_isLoading,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  style: AppTextStyles.headlineMedium,
                  decoration: InputDecoration(
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppColors.primaryPurple,
                        width: 2,
                      ),
                    ),
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (value) => _onDigitChanged(index, value),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppPrimaryButton(
          label: 'Verify Code',
          onPressed: _isLoading ? null : _verifyCode,
          isLoading: _isLoading,
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Didn't receive the code? ",
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.mutedForeground,
              ),
            ),
            TextButton(
              onPressed: (_canResend && !_isLoading) ? _sendCode : null,
              child: Text(
                _canResend ? 'Resend Code' : 'Resend in ${_resendCountdown}s',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNewPinStep() {
    return Form(
      key: _pinFormKey,
      child: Column(
        children: [
          ParentPinField(
            controller: _pinController,
            label: 'New PIN',
            validator: ParentPinService.validatePin,
          ),
          const SizedBox(height: AppSpacing.md),
          ParentPinField(
            controller: _confirmPinController,
            label: 'Confirm New PIN',
            validator: (value) =>
                value == _pinController.text ? null : 'PINs do not match',
          ),
          const SizedBox(height: AppSpacing.xl),
          AppPrimaryButton(
            label: 'Save PIN',
            onPressed: _isLoading ? null : _savePin,
            isLoading: _isLoading,
          ),
        ],
      ),
    );
  }
}

/// A masked 4-digit PIN input for parent-facing configuration screens.
///
/// Only used behind the parent gate (Settings, PIN reset), so a normal
/// keyboard is fine here — the child-facing challenge uses the on-screen
/// numpad in [ParentVerificationDialog].
class ParentPinField extends StatelessWidget {
  const ParentPinField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: ParentPinService.pinLength,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        prefixIcon: const Icon(Icons.pin_outlined),
      ),
      validator: (value) {
        final pin = value ?? '';
        if (pin.isEmpty) return 'Please enter a PIN';
        return validator?.call(pin);
      },
    );
  }
}
