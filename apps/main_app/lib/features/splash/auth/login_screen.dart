import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/utils/network_errors.dart';
import '../../../providers/child_provider.dart';
import '../loading_screen.dart';
import 'forgot_password_screen.dart';
import 'otp_verification_screen.dart';
import 'credits_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  bool _isLogin = true;
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _musicOn = true;
  bool _hasExistingGuestAccount = false;

  /// Whether the device currently has no network — drives the offline banner
  /// and the visual promotion of guest mode (which works fully offline).
  bool _isOffline = false;
  StreamSubscription<bool>? _connectivitySub;

  /// Whether the parent has accepted the Data Privacy Notice (register only).
  bool _privacyAccepted = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  late final AnimationController _logoAnimController;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;

  VideoPlayerController? _videoController;
  bool _videoInitialized = false;

  @override
  void initState() {
    super.initState();

    lockParentAdaptive();

    _logoAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _logoScale = CurvedAnimation(
      parent: _logoAnimController,
      curve: Curves.elasticOut,
    );
    _logoOpacity = CurvedAnimation(
      parent: _logoAnimController,
      curve: Curves.easeIn,
    );
    _logoAnimController.forward();

    _initVideoPlayer();
    _checkForExistingGuestAccount();
    _watchConnectivity();
    // Music already started by LoadingScreen, just verify it's playing
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verifyMusicPlaying();
      _maybeShowFirstLaunchPrivacyNotice();
    });
  }

  /// On first launch (no consent recorded yet), show the Data Privacy Notice
  /// before the parent can register or proceed to child profile setup. It
  /// re-appears each launch until accepted.
  Future<void> _maybeShowFirstLaunchPrivacyNotice() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyConsented =
        prefs.getString('privacy_consent_accepted_at') != null;
    if (alreadyConsented || _privacyAccepted || !mounted) return;
    await _showPrivacyNotice(dismissible: false);
  }

  /// Records Data Privacy consent (checkbox state + persisted timestamp).
  Future<void> _acceptPrivacy() async {
    setState(() => _privacyAccepted = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'privacy_consent_accepted_at',
      DateTime.now().toIso8601String(),
    );
  }

  /// Tracks connectivity so the UI can steer offline users toward guest mode
  /// (the only path that works with no network).
  void _watchConnectivity() {
    connectivityService.checkConnectivity().then((online) {
      if (mounted) setState(() => _isOffline = !online);
    });
    _connectivitySub = connectivityService.onConnectivityChanged.listen((
      online,
    ) {
      if (mounted) setState(() => _isOffline = !online);
    });
  }

  /// Check SharedPreferences for a stored guest refresh token.
  /// If one exists, an unbound guest account was previously created,
  /// so we show "Continue to previous account" instead of "Continue as Guest".
  Future<void> _checkForExistingGuestAccount() async {
    final prefs = await SharedPreferences.getInstance();
    // A returning guest is either a cloud-backed anonymous account (refresh
    // token) or an established offline guest (persisted locally).
    final hasToken =
        prefs.getString('guest_refresh_token') != null ||
        (prefs.getBool('guest_established') ?? false);
    if (mounted && hasToken != _hasExistingGuestAccount) {
      setState(() => _hasExistingGuestAccount = hasToken);
    }
  }

  void _verifyMusicPlaying() async {
    try {
      final audioService = context.read<AudioService>();
      debugPrint(
        '[LoginScreen] Checking music state: isMusicPlaying=${audioService.isMusicPlaying}',
      );
      if (!audioService.isMusicPlaying) {
        debugPrint('[LoginScreen] Music not playing, starting...');
        await audioService.playCategoryMusic(kDefaultBgmCategory);
      } else {
        debugPrint('[LoginScreen] Music already playing from LoadingScreen');
      }
    } catch (e) {
      debugPrint('[LoginScreen] ✖ Error checking music: $e');
    }
  }

  void _toggleMusic() async {
    final audioService = context.read<AudioService>();
    setState(() => _musicOn = !_musicOn);
    if (_musicOn) {
      await audioService.resumeMusic();
    } else {
      await audioService.pauseMusic();
    }
    // Ensure video is still playing after music toggle
    if (_videoController != null &&
        _videoController!.value.isInitialized &&
        !_videoController!.value.isPlaying) {
      _videoController!.play();
    }
  }

  Future<void> _initVideoPlayer() async {
    // Lower graphics tiers use a static gradient instead of the looping video
    // (lower sensory load and device heat).
    if (await ChildProvider.readUseStaticBackground()) {
      debugPrint('[LoginScreen] Static background — skipping video.');
      return;
    }

    // Try MP4 first (best Android compatibility), then WebM as fallback
    final videoPaths = [
      'assets/videos/login_page_bg.mp4',
      'assets/videos/login_page_bg.webm',
    ];

    for (final path in videoPaths) {
      try {
        // Use mixWithOthers so video doesn't request audio focus and pause background music
        final controller = VideoPlayerController.asset(
          path,
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: true,
            allowBackgroundPlayback: false,
          ),
        );
        await controller.setLooping(true);
        await controller.setVolume(0);
        await controller.initialize();

        if (mounted) {
          setState(() {
            _videoController = controller;
            _videoInitialized = true;
          });
          controller.play();
          // Add listener to auto-resume video if it pauses unexpectedly
          controller.addListener(() {
            if (controller.value.isInitialized &&
                !controller.value.isPlaying &&
                !controller.value.isBuffering) {
              debugPrint(
                '[LoginScreen] Video paused unexpectedly, resuming...',
              );
              controller.play();
            }
          });
          debugPrint('Login background video loaded: $path');
          return;
        } else {
          controller.dispose();
          return;
        }
      } catch (e, stackTrace) {
        debugPrint('Failed to load video $path: $e');
        debugPrint('Stack trace: $stackTrace');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Video error ($path): $e'),
              duration: const Duration(seconds: 5),
              backgroundColor: Colors.red,
            ),
          );
        }
        continue;
      }
    }

    debugPrint('All video formats failed, using gradient background.');
  }

  @override
  void dispose() {
    unlockParentOrientation();
    _connectivitySub?.cancel();
    _logoAnimController.dispose();
    _videoController?.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _navigateAfterAuth() async {
    await _authService.refreshSession();
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoadingScreen()),
      (_) => false,
    );
  }

  void _showError(String message, {String title = 'Something went wrong'}) {
    if (!mounted) return;

    // For long/configuration errors, show a dialog with more space
    if (message.contains('configuration error') || message.length > 100) {
      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(child: Text(message)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.destructiveRed,
      ),
    );
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    // Registration requires explicit Data Privacy consent.
    if (!_isLogin && !_privacyAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please accept the Data Privacy Notice to continue.'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        await _authService.signInWithEmail(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        await _navigateAfterAuth();
      } else {
        final response = await _authService.signUpWithEmail(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          displayName: _nameController.text.trim(),
        );

        // Record proof-of-consent (Data Privacy Act of 2012).
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'privacy_consent_accepted_at',
          DateTime.now().toIso8601String(),
        );

        if (response.session == null) {
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder:
                    (_) => OtpVerificationScreen(
                      email: _emailController.text.trim(),
                    ),
              ),
            );
          }
        } else {
          await _navigateAfterAuth();
        }
      }
    } on AuthException catch (e) {
      debugPrint('AuthException: ${e.message} | statusCode: ${e.statusCode}');
      if (e.message.toLowerCase().contains('email not confirmed')) {
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder:
                  (_) => OtpVerificationScreen(
                    email: _emailController.text.trim(),
                  ),
            ),
          );
        }
      } else {
        _showError(e.message);
      }
    } catch (e) {
      debugPrint('Unexpected error: $e');
      _showError(
        friendly(
          e,
          fallback: 'An unexpected error occurred. Please try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Ensures the Data Privacy Notice has been accepted before continuing.
  /// If not yet accepted, shows the notice; returns whether it is now accepted.
  Future<bool> _ensurePrivacyConsent() async {
    if (_privacyAccepted) return true;
    await _showPrivacyNotice();
    if (_privacyAccepted) {
      // Record proof-of-consent (Data Privacy Act of 2012).
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'privacy_consent_accepted_at',
        DateTime.now().toIso8601String(),
      );
    }
    return _privacyAccepted;
  }

  Future<void> _handleGoogleSignIn() async {
    // Require Data Privacy consent before social sign-in.
    if (!await _ensurePrivacyConsent()) return;
    setState(() => _isLoading = true);

    try {
      await _authService.signInWithGoogle();
      await _navigateAfterAuth();
    } on AuthException catch (e) {
      debugPrint('Google Sign-In AuthException: ${e.message}');
      _showError(e.message);
    } catch (e, stackTrace) {
      debugPrint('Google Sign-In error: $e');
      debugPrint('Stack trace: $stackTrace');
      _showError(friendly(e), title: 'Google Sign-In Error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleFacebookSignIn() async {
    // Require Data Privacy consent before social sign-in.
    if (!await _ensurePrivacyConsent()) return;
    setState(() => _isLoading = true);

    try {
      await _authService.signInWithFacebook();
      await _navigateAfterAuth();
    } on AuthException catch (e) {
      debugPrint('Facebook Sign-In AuthException: ${e.message}');
      _showError(e.message);
    } catch (e, stackTrace) {
      debugPrint('Facebook Sign-In error: $e');
      debugPrint('Stack trace: $stackTrace');
      _showError(friendly(e), title: 'Facebook Sign-In Error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleForgotPassword() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()));
  }

  Future<void> _handleGuestSignIn() async {
    // Require Data Privacy consent before continuing as guest.
    if (!await _ensurePrivacyConsent()) return;
    setState(() => _isLoading = true);

    try {
      // Offline-first: establish a persistent local guest immediately so guest
      // mode works with no network at all and survives app restarts.
      await _authService.continueAsGuest();

      // Best-effort cloud upgrade: when online, back the guest with an anonymous
      // account for sync. A failure here (e.g. offline) never blocks guest use.
      if (_authService.currentUser == null) {
        try {
          await _authService.signInAnonymouslyOrReuse();
        } catch (e) {
          debugPrint('Guest cloud upgrade skipped (offline): $e');
        }
      }
      await _navigateAfterAuth();
    } catch (e, stackTrace) {
      debugPrint('Guest Sign-In error: $e');
      debugPrint('Stack trace: $stackTrace');
      _showError(friendly(e), title: 'Guest Sign-In Error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static const _googleLogoSvg = '''
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
  <path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>
  <path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>
  <path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>
  <path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>
  <path fill="none" d="M0 0h48v48H0z"/>
</svg>
''';

  static const _facebookLogoSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
  <path fill="#1877F2" d="M48 24C48 10.745 37.255 0 24 0S0 10.745 0 24c0 11.975 8.746 21.91 20.25 23.708v-16.77h-6.09V24h6.09v-5.286c0-6.018 3.582-9.338 9.066-9.338 2.626 0 5.37.469 5.37.469v5.91h-3.024c-2.978 0-3.908 1.85-3.908 3.748V24h6.66l-1.064 6.938H27.75v16.77C39.254 45.91 48 35.975 48 24z"/>
  <path fill="#FFF" d="M33.346 30.938 34.41 24h-6.66v-4.497c0-1.898.93-3.748 3.908-3.748h3.024v-5.91s-2.744-.469-5.37-.469c-5.484 0-9.066 3.32-9.066 9.338V24h-6.09v6.938h6.09v16.77a24.13 24.13 0 0 0 7.5 0v-16.77h5.64z"/>
</svg>
''';

  /// Dims online-only controls when offline. They stay tappable — their own
  /// error handling explains the failure — but visually recede so the
  /// guest option reads as the way forward.
  Widget _dimIfOffline(Widget child) =>
      _isOffline ? Opacity(opacity: 0.55, child: child) : child;

  /// Banner shown while offline, steering parents toward guest mode
  /// (which works fully without a network).
  Widget _buildOfflineBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.butterLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.statusWarningDark.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            size: 18,
            color: AppColors.statusWarningDark,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              "You're offline — you can continue as Guest and sign in later.",
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.statusWarningDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    // Landscape (tablets) keeps the form in a left panel over the video.
    // Portrait phones give the form the full width instead.
    final isWide = screenSize.width >= screenSize.height;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Video background ─────────────────────────────────────
          if (_videoInitialized)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _videoController!.value.size.width,
                  height: _videoController!.value.size.height,
                  child: VideoPlayer(_videoController!),
                ),
              ),
            )
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF87CEEB), Color(0xFF98FB98)],
                ),
              ),
            ),

          // ── Semi-transparent overlay for readability ──────────────
          Container(color: Colors.black.withValues(alpha: 0.15)),

          // ── Main layout ──────────────────────────────────────────
          SafeArea(
            child: Row(
              children: [
                // ── Auth form: a left panel when wide, full width in
                //    portrait so the fields are not squeezed. ────────
                SizedBox(
                  width: isWide ? screenSize.width * 0.42 : screenSize.width,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.md,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: AppColors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ── Logo ───────────────────────────────
                            Center(
                              child: FadeTransition(
                                opacity: _logoOpacity,
                                child: ScaleTransition(
                                  scale: _logoScale,
                                  child: Image.asset(
                                    'assets/images/Aumazing_Logo.png',
                                    width: 180,
                                    height: 120,
                                  ),
                                ),
                              ),
                            ),
                            // const SizedBox(height: AppSpacing.xs),

                            // ── Title ──────────────────────────────
                            Center(
                              // Marked as a heading and named distinctly: the
                              // title and the submit button both read "Log In",
                              // which the scanner flagged as two controls
                              // sharing one description.
                              child: Semantics(
                                header: true,
                                child: Text(
                                  _isLogin ? 'Log In' : 'Sign Up!',
                                  semanticsLabel:
                                      _isLogin
                                          ? 'Log in screen'
                                          : 'Sign up screen',
                                  style: AppTextStyles.headlineLarge.copyWith(
                                    color: AppColors.primaryPurple,
                                    fontSize: 22,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Center(
                              child: Text(
                                _isLogin
                                    ? 'Welcome back!'
                                    : 'Create your account',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.mutedForeground,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),

                            // ── Offline banner ─────────────────────
                            if (_isOffline) ...[
                              _buildOfflineBanner(),
                              const SizedBox(height: AppSpacing.sm),
                            ],

                            // ── Form ───────────────────────────────
                            _dimIfOffline(
                              Form(
                                key: _formKey,
                                child: Column(
                                  children: [
                                    if (!_isLogin) ...[
                                      _buildTextField(
                                        controller: _nameController,
                                        label: 'Full Name',
                                        icon: Icons.person_outline,
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'Please enter your name';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: AppSpacing.sm),
                                    ],
                                    _buildTextField(
                                      controller: _emailController,
                                      label: 'Email',
                                      icon: Icons.email_outlined,
                                      keyboardType: TextInputType.emailAddress,
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Please enter your email';
                                        }
                                        if (!RegExp(
                                          r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                                        ).hasMatch(value)) {
                                          return 'Please enter a valid email';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                    _buildTextField(
                                      controller: _passwordController,
                                      label: 'Password',
                                      icon: Icons.lock_outline,
                                      obscureText: _obscurePassword,
                                      suffixIcon: IconButton(
                                        tooltip:
                                            _obscurePassword
                                                ? 'Show password'
                                                : 'Hide password',
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_off
                                              : Icons.visibility,
                                          size: 20,
                                          color: AppColors.mutedForeground,
                                        ),
                                        onPressed: () {
                                          setState(
                                            () =>
                                                _obscurePassword =
                                                    !_obscurePassword,
                                          );
                                        },
                                      ),
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Please enter your password';
                                        }
                                        if (value.length < 6) {
                                          return 'At least 6 characters';
                                        }
                                        return null;
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            if (_isLogin)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed:
                                      _isLoading ? null : _handleForgotPassword,
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                  ),
                                  child: Text(
                                    'Forgot Password?',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.primaryPurple,
                                    ),
                                  ),
                                ),
                              )
                            else ...[
                              const SizedBox(height: AppSpacing.sm),
                              _buildPrivacyConsent(),
                            ],

                            // ── Submit button ──────────────────────
                            _dimIfOffline(
                              AppPrimaryButton(
                                label: _isLogin ? 'Log In' : 'Sign Up',
                                onPressed:
                                    (_isLoading ||
                                            (!_isLogin && !_privacyAccepted))
                                        ? null
                                        : _submitForm,
                                isLoading: _isLoading,
                              ),
                            ),

                            const SizedBox(height: AppSpacing.sm),

                            // ── Divider ────────────────────────────
                            Row(
                              children: [
                                const Expanded(child: Divider()),
                                Padding(
                                  padding: AppSpacing.horizontalMd,
                                  child: Text(
                                    'or',
                                    style: AppTextStyles.bodySmall,
                                  ),
                                ),
                                const Expanded(child: Divider()),
                              ],
                            ),

                            const SizedBox(height: AppSpacing.sm),

                            // ── Google sign-in ─────────────────────
                            _dimIfOffline(
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed:
                                      _isLoading ? null : _handleGoogleSignIn,
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: SvgPicture.string(
                                          _googleLogoSvg,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Continue with Google',
                                        style: AppTextStyles.labelLarge
                                            .copyWith(fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: AppSpacing.xs),

                            // ── Facebook sign-in ───────────────────
                            _dimIfOffline(
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed:
                                      _isLoading ? null : _handleFacebookSignIn,
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    foregroundColor: const Color(0xFF1877F2),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: SvgPicture.string(
                                          _facebookLogoSvg,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Continue with Facebook',
                                        style: AppTextStyles.labelLarge
                                            .copyWith(fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: AppSpacing.sm),

                            // ── Continue as Guest ───────────────────
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed:
                                    _isLoading ? null : _handleGuestSignIn,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  foregroundColor:
                                      _isOffline
                                          ? AppColors.primaryPurple
                                          : AppColors.mutedForeground,
                                  // Offline, guest is the recommended path —
                                  // give it primary-button weight.
                                  backgroundColor:
                                      _isOffline
                                          ? AppColors.lavenderLight
                                          : null,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  side: BorderSide(
                                    color:
                                        _isOffline
                                            ? AppColors.primaryPurple
                                            : AppColors.border,
                                    width: _isOffline ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _hasExistingGuestAccount
                                          ? Icons.restore
                                          : Icons.person_outline,
                                      size: 18,
                                      color:
                                          _hasExistingGuestAccount || _isOffline
                                              ? AppColors.primaryPurple
                                              : AppColors.mutedForeground,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _hasExistingGuestAccount
                                          ? 'Continue to previous account'
                                          : 'Continue as Guest',
                                      style: AppTextStyles.labelLarge.copyWith(
                                        fontSize: 13,
                                        fontWeight:
                                            _isOffline ? FontWeight.w700 : null,
                                        color:
                                            _hasExistingGuestAccount ||
                                                    _isOffline
                                                ? AppColors.primaryPurple
                                                : null,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: AppSpacing.sm),

                            // ── Toggle login / register ────────────
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _isLogin
                                      ? "Don't have an account? "
                                      : 'Already have an account? ',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.mutedForeground,
                                  ),
                                ),
                                // A bare Text in a GestureDetector gave a
                                // 47x18dp tap target. TextButton carries the
                                // 48dp minimum without changing how it looks.
                                TextButton(
                                  onPressed:
                                      _isLoading
                                          ? null
                                          : () {
                                            setState(() {
                                              _isLogin = !_isLogin;
                                              _privacyAccepted = false;
                                              _formKey.currentState?.reset();
                                            });
                                          },
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    minimumSize: const Size(
                                      kMinInteractiveDimension,
                                      kMinInteractiveDimension,
                                    ),
                                  ),
                                  child: Text(
                                    _isLogin ? 'Register' : 'Log In',
                                    semanticsLabel:
                                        _isLogin
                                            ? 'Register a new account'
                                            : 'Go to log in',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.primaryPurple,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            TextButton.icon(
                              onPressed: () => showCreditsDialog(context),
                              icon: const Icon(Icons.auto_awesome, size: 16),
                              label: const Text('Credits'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.primaryPurple,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                if (isWide) const Expanded(child: SizedBox()),
              ],
            ),
          ),

          // ── Music toggle button (bottom right) ─────────────────────
          Positioned(
            bottom: 16,
            right: 16,
            // Was FloatingActionButton.small: a 40dp target with no
            // accessible name, so a screen reader announced an unlabelled
            // button and never said whether music was on or off. The regular
            // FAB is 56dp and the tooltip supplies the name.
            child: FloatingActionButton(
              onPressed: _toggleMusic,
              backgroundColor: AppColors.white.withValues(alpha: 0.9),
              tooltip:
                  _musicOn
                      ? 'Turn background music off'
                      : 'Turn background music on',
              child: Icon(
                _musicOn ? Icons.music_note : Icons.music_off,
                color: AppColors.primaryPurple,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Consent row shown only in register mode: a required checkbox plus a
  /// tappable link to the full Data Privacy Notice.
  Widget _buildPrivacyConsent() {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Checkbox(
              value: _privacyAccepted,
              activeColor: AppColors.primaryPurple,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged:
                  _isLoading
                      ? null
                      : (v) => setState(() => _privacyAccepted = v ?? false),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text.rich(
                TextSpan(
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.mutedForeground,
                  ),
                  children: [
                    const TextSpan(text: 'I have read and agree to the '),
                    TextSpan(
                      text: 'Data Privacy Notice',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.primaryPurple,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer:
                          TapGestureRecognizer()..onTap = _showPrivacyNotice,
                    ),
                    const TextSpan(
                      text:
                          ', and consent to the collection and processing '
                          'of my and my child\'s information.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Full Data Privacy Notice dialog (Data Privacy Act of 2012, RA 10173).
  Future<void> _showPrivacyNotice({bool dismissible = true}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: dismissible,
      builder: (context) {
        return PopScope(
          canPop: dismissible,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
            title: Row(
              children: [
                const Icon(
                  Icons.privacy_tip_outlined,
                  color: AppColors.primaryPurple,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Data Privacy Notice',
                    style: AppTextStyles.titleLarge.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Aumazing respects your privacy and complies with the '
                      'Data Privacy Act of 2012 (RA 10173). By creating an '
                      'account, you consent to our collection and processing of '
                      'the following information:',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _privacySection('What we collect', [
                      'Parent account: your name and email address, for sign-in '
                          'and account recovery.',
                      'Child profile: nickname, birth date or age, sex, and '
                          'chosen avatar.',
                      'Gameplay data: in-game performance such as response time, '
                          'accuracy, errors, and progress, used to personalize '
                          'learning recommendations.',
                      'Comfort settings: music, sound, vibration, animation, and '
                          'background-theme preferences.',
                      'Device location: used only momentarily to find nearby '
                          'therapy centers (Premium) and never stored.',
                    ]),
                    _privacySection('How we use it', [
                      'To deliver assessments, personalize learning modules, '
                          'track your child\'s progress, and improve the app.',
                      'Aumazing is a learning-support tool only. It does not '
                          'provide a medical diagnosis.',
                    ]),
                    _privacySection('Where it is stored', [
                      'Data is saved on your device and securely synced to our '
                          'cloud provider (Supabase) when you are online.',
                    ]),
                    _privacySection('Your rights', [
                      'You may access, correct, or request deletion of your data, '
                          'and withdraw consent at any time, through the app '
                          'settings or by contacting the Aumazing team.',
                      'Children\'s data is collected with your consent and used '
                          'solely to support your child\'s learning.',
                    ]),
                  ],
                ),
              ),
            ),
            actions: [
              if (dismissible)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Close',
                    style: AppTextStyles.labelLarge.copyWith(
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ),
              TextButton(
                onPressed: () {
                  _acceptPrivacy();
                  Navigator.of(context).pop();
                },
                child: Text(
                  'I Agree',
                  style: AppTextStyles.labelLarge.copyWith(
                    color: AppColors.primaryPurple,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _privacySection(String heading, List<String> points) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading,
            style: AppTextStyles.labelLarge.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...points.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '•  ',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.primaryPurple,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      p,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      enabled: !_isLoading,
      style: AppTextStyles.bodyMedium.copyWith(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTextStyles.bodySmall,
        prefixIcon: Icon(icon, size: 20, color: AppColors.mutedForeground),
        suffixIcon: suffixIcon,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.primaryPurple,
            width: 1.5,
          ),
        ),
        filled: true,
        fillColor: AppColors.inputFill,
      ),
      validator: validator,
    );
  }
}
