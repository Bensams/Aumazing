import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../core/services/auth_service.dart';
import '../home/home_screen.dart';
import 'auth/login_screen.dart';

class AumazingSplashScreen extends StatefulWidget {
  const AumazingSplashScreen({super.key});

  @override
  State<AumazingSplashScreen> createState() => _AumazingSplashScreenState();
}

class _AumazingSplashScreenState extends State<AumazingSplashScreen> {
  late VideoPlayerController _videoController;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _videoController = VideoPlayerController.asset(
      'assets/videos/Aumazing_Splash_Screen_Generation.webm',
    );

    _videoController.addListener(_onVideoProgress);

    _videoController.initialize().then((_) {
      if (mounted) {
        setState(() {});
        _videoController.play();
      }
    });
  }

  void _onVideoProgress() {
    if (_navigated) return;

    final position = _videoController.value.position;
    final duration = _videoController.value.duration;

    if (duration > Duration.zero && position >= duration) {
      _navigated = true;
      _navigateToNextScreen();
    }
  }

  void _navigateToNextScreen() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    if (!mounted) return;

    final isLoggedIn = AuthService().isLoggedIn;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            isLoggedIn ? const HomeScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _videoController.removeListener(_onVideoProgress);
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _videoController.value.isInitialized
          ? SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _videoController.value.size.width,
                  height: _videoController.value.size.height,
                  child: VideoPlayer(_videoController),
                ),
              ),
            )
          : const SizedBox.expand(
              child: ColoredBox(color: Colors.black),
            ),
    );
  }
}
