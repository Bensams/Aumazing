import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/sync_service.dart';
import '../../core/utils/network_errors.dart';
import '../../providers/child_provider.dart';

/// Bind Account modal for guest users to link their progress
class BindAccountModal extends StatefulWidget {
  const BindAccountModal({super.key, required this.authService});

  final AuthService authService;

  @override
  State<BindAccountModal> createState() => _BindAccountModalState();
}

enum _BindAccountStep { options, email, emailVerification }

class _BindAccountState {
  const _BindAccountState({required this.previousUserId, required this.email});

  final String? previousUserId;
  final String email;
}

class _BindAccountModalState extends State<BindAccountModal> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _verificationCodeController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  _BindAccountStep _step = _BindAccountStep.options;
  _BindAccountState? _pendingEmailBinding;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _verificationCodeController.dispose();
    super.dispose();
  }

  Future<void> _bindAccount() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _errorMessage = 'Please enter email and password');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final previousUserId = widget.authService.effectiveUserId;
      if (widget.authService.currentUser == null) {
        await widget.authService.signInAnonymously();
      }

      final email = _emailController.text.trim();
      final response = await widget.authService.convertAnonymousToPermanent(
        email: email,
        password: _passwordController.text,
      );
      if (!mounted) return;
      if (response.user?.isAnonymous == false) {
        await _finishBinding(
          response,
          previousUserId,
          'Account bound successfully!',
        );
        return;
      }
      setState(() {
        _pendingEmailBinding = _BindAccountState(
          previousUserId: previousUserId,
          email: email,
        );
        _step = _BindAccountStep.emailVerification;
      });
    } catch (e) {
      if (mounted) setState(() => _errorMessage = friendly(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _bindWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Capture the source before anonymous sign-in can replace the effective
      // identity. Local records and active-child state still use this ID.
      final previousUserId = widget.authService.effectiveUserId;
      if (widget.authService.currentUser == null) {
        await widget.authService.signInAnonymously();
      }

      final response = await widget.authService.bindAnonymousWithGoogle();
      await _finishBinding(
        response,
        previousUserId,
        'Google account linked successfully!',
      );
    } catch (e) {
      if (mounted) setState(() => _errorMessage = friendly(e));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _verifyEmailBinding() async {
    final pending = _pendingEmailBinding;
    final code = _verificationCodeController.text.trim();
    if (pending == null || code.isEmpty) {
      setState(() => _errorMessage = 'Enter the verification code from your email');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await widget.authService.verifyEmailChange(
        email: pending.email,
        token: code,
      );
      if (!mounted) return;
      if (response.session == null || response.user?.isAnonymous == true) {
        _verificationCodeController.clear();
        setState(() {
          _errorMessage =
              'The first code was accepted. Enter the second code sent to '
              '${pending.email}.';
        });
        return;
      }
      await _finishBinding(
        response,
        pending.previousUserId,
        'Account bound successfully!',
      );
    } catch (e) {
      if (mounted) setState(() => _errorMessage = friendly(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendEmailBindingCode() async {
    final email = _pendingEmailBinding?.email;
    if (email == null) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await widget.authService.resendEmailChange(email);
      if (mounted) {
        setState(() => _errorMessage = 'A new verification code was sent.');
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = friendly(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _finishBinding(
    AuthResponse response,
    String? previousUserId,
    String successMessage,
  ) async {
    if (response.user == null || response.user?.isAnonymous == true) {
      throw AuthException('Binding verification is not complete yet.');
    }

    final newUserId = response.user?.id;

    await widget.authService.clearStoredGuestSession();
    widget.authService.clearGuestMode();

    if (newUserId != null) {
      if (previousUserId != null) {
        await ChildProvider.migrateSavedActiveChild(
          fromUserId: previousUserId,
          toUserId: newUserId,
        );
      }
      await syncService.onUserAuthenticated(
        newUserId,
        previousGuestUserId: previousUserId,
      );
    }

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          backgroundColor: AppColors.mint,
        ),
      );
    }
  }

  void _showEmailStep() {
    setState(() {
      _step = _BindAccountStep.email;
      _errorMessage = null;
    });
  }

  void _showOptionStep() {
    setState(() {
      _step = _BindAccountStep.options;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final availableHeight =
        mediaQuery.size.height - mediaQuery.viewInsets.vertical;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 340,
          maxHeight: availableHeight * 0.9,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child:
          _step == _BindAccountStep.options
              ? _buildOptionStep(context)
              : _step == _BindAccountStep.email
                  ? _buildEmailStep(context)
                  : _buildEmailVerificationStep(context),
        ),
      ),
    );
  }

  Widget _buildOptionStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader('Bind Account'),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Choose how you want to save this guest account permanently.',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_errorMessage != null) ...[
          _buildErrorBanner(),
          const SizedBox(height: AppSpacing.md),
        ],
        _buildBindOption(
          icon: Icons.g_mobiledata_rounded,
          title: 'Bind with Google',
          subtitle: 'Link this guest account to your Google sign-in',
          onTap: _isLoading ? null : _bindWithGoogle,
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildBindOption(
          icon: Icons.email_outlined,
          title: 'Bind with Email',
          subtitle: 'Create login details with email and password',
          onTap: _isLoading ? null : _showEmailStep,
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ),
      ],
    );
  }

  Widget _buildEmailStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader('Bind with Email'),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Create an email and password for this guest account.',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_errorMessage != null) ...[
          _buildErrorBanner(),
          const SizedBox(height: AppSpacing.md),
        ],
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'Email',
            prefixIcon: const Icon(Icons.email_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _passwordController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: _isLoading ? null : _showOptionStep,
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ElevatedButton(
                onPressed: _isLoading ? null : _bindAccount,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  alignment: Alignment.center,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child:
                    _isLoading
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : const Text('Bind with Email'),
              ),
            ),
          ],
        ),
      ],
    );
  }
  Widget _buildEmailVerificationStep(BuildContext context) {
    final email = _pendingEmailBinding?.email ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader('Verify your email'),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Enter the verification code sent to $email. Secure email changes '
          'require two codes; submit the second code after the first is accepted.',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_errorMessage != null) ...[
          _buildErrorBanner(),
          const SizedBox(height: AppSpacing.md),
        ],
        TextField(
          controller: _verificationCodeController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Verification code',
            prefixIcon: Icon(Icons.verified_outlined),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: _isLoading ? null : _resendEmailBindingCode,
                child: const Text('Resend code'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ElevatedButton(
                onPressed: _isLoading ? null : _verifyEmailBinding,
                child: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Verify'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeader(String title) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.butterLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.link_rounded,
            color: AppColors.statusWarningDark,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            title,
            style: AppTextStyles.headlineSmall.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.statusDangerBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.statusDangerDark,
            size: 18,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              _errorMessage!,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.statusDangerDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBindOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: AppColors.white,
      borderRadius: AppRadius.chip,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.chip,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: AppRadius.chip,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.lavenderLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primaryPurple),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.labelLarge.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isLoading && title == 'Bind with Google')
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
