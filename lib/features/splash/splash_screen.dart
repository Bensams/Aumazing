import 'dart:async';
import 'package:flutter/material.dart';
import 'auth/login_screen.dart'; // Import the new LoginScreen

/// A vibrant, animated splash screen for the Aumazing Gamified Learning App.
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

    // Initialize animation controller
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Scale animation (starts small, grows to full size)
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );

    // Fade animation (gradual appearance)
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    // Start the animation
    _controller.forward();

    // Navigate to the Login Screen after 3.5 seconds
    Timer(const Duration(seconds: 3, milliseconds: 500), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
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
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Subtle background decorative elements
          Positioned(
            top: -50,
            right: -50,
            child: _buildDecorativeCircle(Colors.orange.withOpacity(0.1), 150),
          ),
          Positioned(
            bottom: -30,
            left: -30,
            child: _buildDecorativeCircle(Colors.blue.withOpacity(0.1), 120),
          ),

          // Main Logo Content
          Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The Aumazing Logo
                    Image.asset(
                      'assets/images/Aumazing_Logo.png',
                      width: MediaQuery.of(context).size.width * 0.8,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        // Fallback if image isn't found
                        return Column(
                          children: [
                            const Icon(Icons.auto_awesome, size: 100, color: Colors.blue),
                            const SizedBox(height: 20),
                            Text(
                              "AUMAZING",
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade900,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 40),
                    // Loading indicator with Aumazing colors
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Footer text
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 40.0),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Text(
                  "Where Learning Meets Fun!",
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDecorativeCircle(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
