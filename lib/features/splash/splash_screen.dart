import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services/auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_gradients.dart';
import '../../core/theme/app_text_styles.dart';
import '../home/home_screen.dart';
import 'auth/login_screen.dart';

class AumazingSplashScreen extends StatefulWidget {
  const AumazingSplashScreen({super.key});

  @override
  State<AumazingSplashScreen> createState() => _AumazingSplashScreenState();
}

class _AumazingSplashScreenState extends State<AumazingSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _controller.forward();

    Timer(const Duration(seconds: 3, milliseconds: 500), () {
      if (mounted) {
        final isLoggedIn = AuthService().isLoggedIn;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                isLoggedIn ? const HomeScreen() : const LoginScreen(),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.parentLavenderMint),
        child: Stack(
          children: [
            Positioned(
              top: -50,
              right: -50,
              child: _buildDecorativeCircle(
                AppColors.peach.withAlpha(40),
                150,
              ),
            ),
            Positioned(
              bottom: -30,
              left: -30,
              child: _buildDecorativeCircle(
                AppColors.lavender.withAlpha(50),
                120,
              ),
            ),
            Center(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/Aumazing_Logo.png',
                        width: MediaQuery.of(context).size.width * 0.7,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Column(
                            children: [
                              const Icon(
                                Icons.auto_awesome,
                                size: 100,
                                color: AppColors.primaryPurple,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'AUMAZING',
                                style: AppTextStyles.displayLarge.copyWith(
                                  color: AppColors.primaryPurple,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 40),
                      const SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: AppColors.primaryPurple,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40.0),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Text(
                    'Where Learning Meets Fun!',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.mutedForeground,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDecorativeCircle(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
