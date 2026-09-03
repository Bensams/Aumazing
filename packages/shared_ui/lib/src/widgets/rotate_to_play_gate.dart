import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../utils/parent_screen_orientation.dart';

/// Web-only overlay that asks the player to rotate their device when a
/// landscape-designed screen (a game, the assessments) is shown in portrait.
///
/// The web can't force orientation the way Android does with
/// `SystemChrome.setPreferredOrientations` (and iOS Safari can't lock at all),
/// so instead of a broken sideways layout we prompt for a rotate. On native
/// platforms this is a pure pass-through — it returns [child] untouched and
/// never subscribes to anything — so the Android/iOS apps are unaffected.
class RotateToPlayGate extends StatelessWidget {
  const RotateToPlayGate({super.key, required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final content = child ?? const SizedBox.shrink();
    if (!kIsWeb) return content;

    return ValueListenableBuilder<bool>(
      valueListenable: childWantsLandscape,
      builder: (context, wantsLandscape, _) {
        if (!wantsLandscape) return content;
        final media = MediaQuery.of(context);
        final isPortrait = media.orientation == Orientation.portrait;
        // Only prompt on phone/small-tablet screens — desktop windows can't be
        // physically rotated and rarely sit in portrait anyway.
        final isSmall = media.size.shortestSide < 600;
        if (!isPortrait || !isSmall) return content;
        return Stack(
          children: [content, const _RotatePrompt()],
        );
      },
    );
  }
}

class _RotatePrompt extends StatelessWidget {
  const _RotatePrompt();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: const Color(0xFF0B0920),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 1400),
                  curve: Curves.easeInOut,
                  builder: (context, t, child) => Transform.rotate(
                    // Gentle rock between upright and sideways.
                    angle: (t <= 0.5 ? t * 2 : (1 - t) * 2) * 1.5708,
                    child: child,
                  ),
                  onEnd: () {},
                  child: const Icon(
                    Icons.screen_rotation_rounded,
                    size: 72,
                    color: Color(0xFF00E5FF),
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Please rotate your device',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'This part of Aumazing is best played in landscape. '
                  'Turn your device sideways to continue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF8A7FB5),
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
