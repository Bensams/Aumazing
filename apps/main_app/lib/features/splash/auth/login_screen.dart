import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../../core/services/auth_service.dart';
import '../../home/home_screen.dart';
import 'child_profile_setup_screen.dart';
import 'forgot_password_screen.dart';
import 'otp_verification_screen.dart';

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

    lockParentLandscape();
    // Restore normal system overlays after the splash screen's
    // immersiveSticky / edgeToEdge mode to prevent ghost touches.
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );

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
    // Music already started by LoadingScreen, just verify it's playing
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verifyMusicPlaying();
    });
  }

  void _verifyMusicPlaying() async {
    try {
      final audioService = context.read<AudioService>();
      debugPrint('[LoginScreen] Checking music state: isMusicPlaying=${audioService.isMusicPlaying}');
      if (!audioService.isMusicPlaying) {
        debugPrint('[LoginScreen] Music not playing, starting...');
        await audioService.playRandomMusic(['bg_music.ogg', 'bg_music1.ogg']);
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
              debugPrint('[LoginScreen] Video paused unexpectedly, resuming...');
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

    final destination = _authService.hasChildProfile
        ? const HomeScreen()
        : const ChildProfileSetupScreen();

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => destination),
      (_) => false,
    );
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

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

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

        if (response.session == null) {
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => OtpVerificationScreen(
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
              builder: (_) => OtpVerificationScreen(
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
      _showError('An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
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
      _showError('Google sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
    );
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

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

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

          // ── Main landscape layout ────────────────────────────────
          SafeArea(
            child: Row(
              children: [
                // ── Left panel: Auth form ──────────────────────────
                SizedBox(
                  width: screenSize.width * 0.42,
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
                              child: Text(
                                _isLogin ? 'Log In' : 'Sign Up!',
                                style: AppTextStyles.headlineLarge.copyWith(
                                  color: AppColors.primaryPurple,
                                  fontSize: 22,
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

                            // ── Form ───────────────────────────────
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
                                              r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                                          .hasMatch(value)) {
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
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                        size: 20,
                                        color: AppColors.mutedForeground,
                                      ),
                                      onPressed: () {
                                        setState(() => _obscurePassword =
                                            !_obscurePassword);
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

                            if (_isLogin)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed:
                                      _isLoading ? null : _handleForgotPassword,
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 4),
                                  ),
                                  child: Text(
                                    'Forgot Password?',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.primaryPurple,
                                    ),
                                  ),
                                ),
                              )
                            else
                              const SizedBox(height: AppSpacing.sm),

                            // ── Submit button ──────────────────────
                            AppPrimaryButton(
                              label: _isLogin ? 'Log In' : 'Sign Up',
                              onPressed: _isLoading ? null : _submitForm,
                              isLoading: _isLoading,
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
                                      child:
                                          SvgPicture.string(_googleLogoSvg),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Continue with Google',
                                      style: AppTextStyles.labelLarge.copyWith(
                                        fontSize: 13,
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
                                GestureDetector(
                                  onTap: _isLoading
                                      ? null
                                      : () {
                                          setState(() {
                                            _isLogin = !_isLogin;
                                            _formKey.currentState?.reset();
                                          });
                                        },
                                  child: Text(
                                    _isLogin ? 'Register' : 'Log In',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.primaryPurple,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const Expanded(child: SizedBox()),
              ],
            ),
          ),

          // ── Music toggle button (bottom right) ─────────────────────
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton.small(
              onPressed: _toggleMusic,
              backgroundColor: AppColors.white.withValues(alpha: 0.9),
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
