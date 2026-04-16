import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../core/services/auth_service.dart';
import '../home/home_screen.dart';
import 'auth/child_profile_setup_screen.dart';
import 'auth/login_screen.dart';

class AumazingSplashScreen extends StatefulWidget {
  const AumazingSplashScreen({super.key});

  @override
  State<AumazingSplashScreen> createState() => _AumazingSplashScreenState();
}

class _AumazingSplashScreenState extends State<AumazingSplashScreen> {
  VideoPlayerController? _videoController;
  bool _navigated = false;
  bool _videoReady = false;

  @override
  void initState() {
    super.initState();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _initVideo();
  }

  Future<void> _initVideo() async {
    const videoAsset = 'assets/videos/Aumazing_Splash_Screen_Generation.mp4';

    // Verify the asset actually exists before handing it to ExoPlayer.
    try {
      await rootBundle.load(videoAsset);
    } catch (_) {
      // Asset not bundled — skip splash immediately.
      _skipSplash();
      return;
    }

    try {
      final controller = VideoPlayerController.asset(videoAsset);
      _videoController = controller;

      await controller.initialize();
      if (!mounted || _navigated) return;

      controller.addListener(_onVideoProgress);
      _videoReady = true;
      setState(() {});
      controller.play();
    } catch (_) {
      // Initialization or playback failed — skip.
      _skipSplash();
    }
  }

  void _onVideoProgress() {
    if (_navigated) return;
    final ctl = _videoController;
    if (ctl == null) return;

    if (ctl.value.hasError) {
      _skipSplash();
      return;
    }

    final position = ctl.value.position;
    final duration = ctl.value.duration;

    if (duration > Duration.zero && position >= duration) {
      _navigated = true;
      _navigateToNextScreen();
    }
  }

  void _skipSplash() {
    if (_navigated || !mounted) return;
    _navigated = true;
    _navigateToNextScreen();
  }

  Future<void> _navigateToNextScreen() async {
    lockParentLandscape();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    if (!mounted) return;

    final authService = AuthService();
    final Widget destination;

    if (!authService.isLoggedIn) {
      destination = const LoginScreen();
    } else {
      // Refresh the local session so userMetadata is up-to-date
      // before deciding whether the child profile has been set up.
      await authService.refreshSession();
      if (!mounted) return;

      destination = authService.hasChildProfile
          ? const HomeScreen()
          : const ChildProfileSetupScreen();
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => destination),
    );
  }

  @override
  void dispose() {
    _videoController?.removeListener(_onVideoProgress);
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctl = _videoController;
    return Scaffold(
      backgroundColor: Colors.black,
      body: (_videoReady && ctl != null && ctl.value.isInitialized)
          ? SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: ctl.value.size.width,
                  height: ctl.value.size.height,
                  child: VideoPlayer(ctl),
                ),
              ),
            )
          : const SizedBox.expand(
              child: ColoredBox(color: Colors.black),
            ),
    );
  }
}
