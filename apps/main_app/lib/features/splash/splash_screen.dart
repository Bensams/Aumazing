import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'package:shared_ui/shared_ui.dart';

import 'loading_screen.dart';

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

    // Matches the orientation of the login screen this leads into, so a
    // phone does not rotate to landscape and straight back on launch. The
    // splash video is BoxFit.cover, so it fills either shape.
    lockParentAdaptive();
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
    lockParentAdaptive();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    if (!mounted) return;

    // Always go to LoadingScreen first to preload assets
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoadingScreen()),
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
      // Matches the native launch background (white), so the letterbox around
      // a wide video on a portrait phone is invisible and there is no flash
      // between the OS splash and this one.
      backgroundColor: Colors.white,
      body: (_videoReady && ctl != null && ctl.value.isInitialized)
          ? LayoutBuilder(
              builder: (context, constraints) {
                final viewAspect = constraints.maxWidth / constraints.maxHeight;
                // Cropping the wide splash video to fill a portrait phone cuts
                // the logo off at both edges, so show the whole frame when the
                // screen is narrower than the video. Wider screens still fill.
                final fit = viewAspect < ctl.value.aspectRatio
                    ? BoxFit.contain
                    : BoxFit.cover;

                return SizedBox.expand(
                  child: FittedBox(
                    fit: fit,
                    child: SizedBox(
                      width: ctl.value.size.width,
                      height: ctl.value.size.height,
                      child: VideoPlayer(ctl),
                    ),
                  ),
                );
              },
            )
          : const SizedBox.expand(
              child: ColoredBox(color: Colors.white),
            ),
    );
  }
}
