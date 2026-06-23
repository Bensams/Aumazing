import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Full-screen looping, muted video background — the same one used on the
/// login page.
///
/// Plays `assets/videos/login_page_bg.mp4` (falls back to `.webm`, then a
/// gradient if neither loads), overlays a subtle dark scrim for foreground
/// readability, and renders [child] on top.
class AppVideoBackground extends StatefulWidget {
  const AppVideoBackground({super.key, required this.child});

  final Widget child;

  @override
  State<AppVideoBackground> createState() => _AppVideoBackgroundState();
}

class _AppVideoBackgroundState extends State<AppVideoBackground> {
  VideoPlayerController? _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    const paths = [
      'assets/videos/login_page_bg.mp4',
      'assets/videos/login_page_bg.webm',
    ];
    for (final path in paths) {
      try {
        final controller = VideoPlayerController.asset(
          path,
          videoPlayerOptions: VideoPlayerOptions(
            // Don't grab audio focus, so background music keeps playing.
            mixWithOthers: true,
            allowBackgroundPlayback: false,
          ),
        );
        await controller.setLooping(true);
        await controller.setVolume(0);
        await controller.initialize();

        if (!mounted) {
          controller.dispose();
          return;
        }
        setState(() {
          _controller = controller;
          _initialized = true;
        });
        controller.play();
        // Auto-resume if the video pauses unexpectedly.
        controller.addListener(() {
          if (controller.value.isInitialized &&
              !controller.value.isPlaying &&
              !controller.value.isBuffering) {
            controller.play();
          }
        });
        return;
      } catch (_) {
        continue;
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_initialized && _controller != null)
          SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.size.width,
                height: _controller!.value.size.height,
                child: VideoPlayer(_controller!),
              ),
            ),
          )
        else
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF87CEEB), Color(0xFF98FB98)],
              ),
            ),
          ),
        // Semi-transparent scrim for readability (matches login).
        Container(color: Colors.black.withValues(alpha: 0.15)),
        widget.child,
      ],
    );
  }
}
