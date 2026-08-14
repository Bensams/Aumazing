import 'package:flutter/material.dart';

import 'developer_automation_registry.dart';
import 'developer_autoplay_controller.dart';
import 'developer_tools_config.dart';

/// The debug-only bar pinned to the top of the screen while automation is
/// running, or while a game that automation can drive is open.
///
/// Two independent halves:
///  * the auto-play status line with pause / resume / stop, shown whenever a
///    run is active;
///  * the per-game skip controls, shown whenever a game screen has registered
///    itself — the developer can reach for them mid-game without opening the
///    toolbox.
///
/// Renders nothing at all when developer tools are unavailable, and nothing
/// when there is neither a run nor a game.
class DeveloperAutomationBar extends StatelessWidget {
  const DeveloperAutomationBar({super.key, required this.onSkipRemaining});

  /// Asks for confirmation and then skips the rest of the flow. Supplied by
  /// the overlay, which owns a navigator that can show the dialog.
  final Future<void> Function() onSkipRemaining;

  @override
  Widget build(BuildContext context) {
    if (!DeveloperToolsConfig.isAvailable) return const SizedBox.shrink();

    final controller = DeveloperAutoPlayController.instance;
    final registry = DeveloperAutomationRegistry.instance;

    return ListenableBuilder(
      listenable: Listenable.merge([controller, registry]),
      builder: (context, _) {
        final statusLine = controller.statusLine;
        final game = registry.activeGame;
        final canSkip = game != null && !game.isComplete;

        if (statusLine == null && !canSkip) return const SizedBox.shrink();

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (statusLine != null) _statusChip(controller, statusLine),
                if (statusLine != null && canSkip) const SizedBox(height: 6),
                if (canSkip) _skipControls(context, controller),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statusChip(
      DeveloperAutoPlayController controller, String statusLine) {
    final paused = controller.status == AutoPlayStatus.paused;
    return _bar(
      key: const Key('developerAutoPlayStatus'),
      children: [
        Flexible(
          child: Text(
            statusLine,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ),
        _iconAction(
          key: const Key('developerAutoPlayPauseResume'),
          icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
          tooltip: paused ? 'Resume auto-play' : 'Pause auto-play',
          onPressed: paused ? controller.resume : controller.pause,
        ),
        _iconAction(
          key: const Key('developerAutoPlayStop'),
          icon: Icons.stop_rounded,
          tooltip: 'Stop auto-play',
          onPressed: controller.stop,
        ),
      ],
    );
  }

  Widget _skipControls(
      BuildContext context, DeveloperAutoPlayController controller) {
    final busy = controller.isActive;
    return _bar(
      key: const Key('developerSkipControls'),
      children: [
        _textAction(
          key: const Key('developerSkipCurrentGame'),
          label: 'Skip Game',
          // Skipping is auto-play with the brakes off: the same valid actions
          // through the same pipeline, just without the pauses.
          onPressed: busy
              ? null
              : () => controller.playCurrentGame(
                    speed: AutoPlaySpeed.veryFast,
                  ),
        ),
        _textAction(
          key: const Key('developerSkipRemainingGames'),
          label: 'Skip Rest',
          onPressed: busy ? null : onSkipRemaining,
        ),
        _textAction(
          key: const Key('developerAutoPlayCurrentGame'),
          label: 'Auto-play',
          onPressed: busy ? null : () => controller.playCurrentGame(),
        ),
      ],
    );
  }

  Widget _bar({required Key key, required List<Widget> children}) => Material(
        key: key,
        color: const Color(0xE61B1B1F),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      );

  Widget _iconAction({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) =>
      IconButton(
        key: key,
        tooltip: tooltip,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 18, color: Colors.white),
      );

  Widget _textAction({
    required Key key,
    required String label,
    required Future<void> Function()? onPressed,
  }) =>
      TextButton(
        key: key,
        onPressed: onPressed == null ? null : () => onPressed(),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          visualDensity: VisualDensity.compact,
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white38,
        ),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      );
}
