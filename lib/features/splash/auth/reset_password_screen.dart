import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_primary_button.dart';
import '../../../core/widgets/parent_mode_top_bar.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String email;

  const ResetPasswordScreen({super.key, required this.email});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _authService = AuthService();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _passwordFormKey = GlobalKey<FormState>();

  static const int _codeLength = 6;
  final List<TextEditingController> _otpControllers =
      List.generate(_codeLength, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes =
      List.generate(_codeLength, (_) => FocusNode());

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _codeVerified = false;
  bool _canResend = false;
  int _resendCountdown = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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

  void _onDigitChanged(int index, String value) {
    if (value.length == 1 && index < _codeLength - 1) {
      _otpFocusNodes[index + 1].requestFocus();
    }
    if (_otpCode.length == _codeLength) {
      _verifyCode();
    }
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
      if (mounted) {
        setState(() => _codeVerified = true);
        _showSuccess('Code verified! Now set your new password.');
      }
    } on AuthException catch (e) {
      _showError(e.message);
      _clearOtpFields();
    } catch (e) {
      _showError('Verification failed. Please try again.');
      _clearOtpFields();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updatePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await _authService.updatePassword(_passwordController.text);
      if (mounted) {
        _showSuccess('Password updated successfully!');
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Failed to update password. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendCode() async {
    setState(() => _isLoading = true);
    try {
      await _authService.sendPasswordResetOTP(widget.email);
      _showSuccess('A new code has been sent to your email.');
      _startResendTimer();
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Failed to resend code. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
        backgroundColor: AppColors.destructiveSoftRed,
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.mint,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ParentModeTopBar(
        title: '',
        onBack: () => Navigator.of(context).pop(),
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

                Center(
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
                        _codeVerified
                            ? 'Set New Password'
                            : 'Enter Reset Code',
                        style: AppTextStyles.headlineLarge.copyWith(
                          color: AppColors.primaryPurple,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Padding(
                        padding: AppSpacing.horizontalLg,
                        child: Text(
                          _codeVerified
                              ? 'Choose a strong new password for your account.'
                              : 'We sent a verification code to',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.mutedForeground,
                          ),
                        ),
                      ),
                      if (!_codeVerified) ...[
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
                ),

                const SizedBox(height: AppSpacing.xxl),

                if (!_codeVerified) ...[
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
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: AppColors.primaryPurple,
                                  width: 2,
                                ),
                              ),
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onChanged: (value) =>
                                _onDigitChanged(index, value),
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
                        onPressed:
                            (_canResend && !_isLoading) ? _resendCode : null,
                        child: Text(
                          _canResend
                              ? 'Resend Code'
                              : 'Resend in ${_resendCountdown}s',
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Form(
                    key: _passwordFormKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          enabled: !_isLoading,
                          decoration: InputDecoration(
                            labelText: 'New Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () {
                                setState(() =>
                                    _obscurePassword = !_obscurePassword);
                              },
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter a new password';
                            }
                            if (value.length < 6) {
                              return 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirm,
                          enabled: !_isLoading,
                          decoration: InputDecoration(
                            labelText: 'Confirm New Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirm
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () {
                                setState(
                                    () => _obscureConfirm = !_obscureConfirm);
                              },
                            ),
                          ),
                          validator: (value) {
                            if (value != _passwordController.text) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  AppPrimaryButton(
                    label: 'Update Password',
                    onPressed: _isLoading ? null : _updatePassword,
                    isLoading: _isLoading,
                  ),
                ],

                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
