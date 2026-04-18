import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:video_player/video_player.dart';

import '../../core/services/auth_service.dart';
import '../home/home_screen.dart';
import 'auth/child_profile_setup_screen.dart';
import 'auth/login_screen.dart';

/// Loading screen with video background and real assets loading progress.
///
/// Pre-loads and initializes:
/// - Background video
/// - Audio files (bg_music.ogg, bg_music1.ogg, ui_tap.wav)
/// - Other critical assets
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  VideoPlayerController? _videoController;
  bool _videoInitialized = false;

  double _progress = 0.0;
  String _status = 'Preparing...';

  final List<String> _assetsToPreload = [
    'packages/shared_audio/assets/audio/bg_music.ogg',
    'packages/shared_audio/assets/audio/bg_music1.ogg',
    'packages/shared_audio/assets/audio/ui_tap.wav',
  ];

  @override
  void initState() {
    super.initState();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _initLoading();
  }

  Future<void> _initLoading() async {
    // Start video initialization
    _initVideo();

    // Pre-load audio assets
    await _preloadAssets();

    // Initialize audio service
    await _initAudio();

    // Ensure video is ready
    await _waitForVideo();

    // Navigate based on auth status
    if (mounted) {
      await _navigateBasedOnAuth();
    }
  }

  Future<void> _initVideo() async {
    final videoPaths = [
      'assets/videos/login_page_bg.mp4',
      'assets/videos/login_page_bg.webm',
    ];

    for (final path in videoPaths) {
      try {
        // Use mixWithOthers so video doesn't request audio focus and pause music
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
          return;
        }
      } catch (_) {
        continue;
      }
    }
  }

  Future<void> _preloadAssets() async {
    final totalAssets = _assetsToPreload.length;

    for (var i = 0; i < totalAssets; i++) {
      final asset = _assetsToPreload[i];
      setState(() {
        _status = 'Loading audio... (${i + 1}/$totalAssets)';
        _progress = (i + 1) / (totalAssets + 2); // +2 for audio init and video wait
      });

      try {
        // Pre-cache the asset in memory
        await rootBundle.load(asset);
        debugPrint('[LoadingScreen] Preloaded: $asset');
      } catch (e) {
        debugPrint('[LoadingScreen] Failed to preload $asset: $e');
      }

      // Small delay to show progress
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<void> _initAudio() async {
    setState(() {
      _status = 'Initializing audio...';
      _progress = (_assetsToPreload.length + 1) / (_assetsToPreload.length + 2);
    });

    final audioService = context.read<AudioService>();
    debugPrint('[LoadingScreen] AudioService config: musicEnabled=${audioService.config.musicEnabled}, volume=${audioService.config.musicVolume}');

    // Wait a moment for AudioPlayer to fully initialize
    await Future.delayed(const Duration(milliseconds: 500));

    // Start music playing - it will continue through to LoginScreen
    try {
      debugPrint('[LoadingScreen] Starting music...');
      await audioService.playRandomMusic(['bg_music.ogg', 'bg_music1.ogg']);
      debugPrint('[LoadingScreen] Music started, will continue to LoginScreen');
    } catch (e, stackTrace) {
      debugPrint('[LoadingScreen] ✖ Music start error: $e');
      debugPrint('[LoadingScreen] Stack: $stackTrace');
    }

    await Future.delayed(const Duration(milliseconds: 300));
  }

  Future<void> _waitForVideo() async {
    setState(() {
      _status = 'Finalizing...';
      _progress = 1.0;
    });

    // Wait for video to be ready
    while (!_videoInitialized && mounted) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Brief pause to show 100% completion
    await Future.delayed(const Duration(milliseconds: 200));
  }

  Future<void> _navigateBasedOnAuth() async {
    final authService = AuthService();

    Widget destination;
    if (!authService.isLoggedIn) {
      destination = const LoginScreen();
    } else {
      await authService.refreshSession();
      if (!mounted) return;
      destination = authService.hasChildProfile
          ? const HomeScreen()
          : const ChildProfileSetupScreen();
    }

    // Use fade transition to avoid audio/video interruptions
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => destination,
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );

    // Keep video playing briefly during transition, then dispose
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  void dispose() {
    // Dispose video controller safely
    if (_videoController != null && _videoController!.value.isInitialized) {
      _videoController!.pause();
      _videoController!.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Video background
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

          // Dark overlay for readability
          Container(color: Colors.black.withValues(alpha: 0.4)),

          // Loading UI at bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 20,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 60),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Status text
                  Text(
                    _status,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Progress bar background
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progress,
                        backgroundColor: Colors.transparent,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF9B7EDC),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Percentage text
                  Text(
                    '${(_progress * 100).toInt()}%',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
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
}
