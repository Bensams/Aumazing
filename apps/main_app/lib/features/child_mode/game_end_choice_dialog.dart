import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../providers/assessment_provider.dart';
import '../../providers/child_provider.dart';
import '../../services/active_games_service.dart';
import '../../services/learning_path_service.dart';
import '../../services/screen_time_service.dart';
import 'game_launcher.dart';
import 'time_up_dialog.dart';

/// Post-reward choice for practice (non-assessment) games: play the next
/// game or go back to the lobby.
///
/// Icon-first and reading-free (the children may not read yet): two large
/// buttons — the next game's icon with a play arrow, and a home icon for the
/// lobby. Shown after the reward finishes; never in assessment flows.
class GameEndChoiceDialog {
  GameEndChoiceDialog._();

  /// Shows the choice and performs the navigation:
  /// - Next → replaces the current game screen with the next game
  ///   (difficulty resolved like the lobby: override → per-area AI level)
  /// - Lobby → pops back to the lobby
  ///
  /// Call with the game screen still on the navigation stack (after popping
  /// only the reward overlay).
  static Future<void> show(
    BuildContext context, {
    required String currentGameId,
  }) async {
    // Screen-time enforcement happens here — at the natural boundary after
    // a game finishes (never mid-game). Out of time → gentle break screen
    // instead of offering the next game.
    if (ScreenTimeService.instance.isExhausted) {
      await TimeUpDialog.show(context);
      return;
    }

    // Prefer the AI learning path's order; fall back to registry order when
    // the child isn't on a path (no assessment yet, or game not on it).
    final activeIds = await ActiveGamesService.instance.activeGameIds;
    if (!context.mounted) return;
    final path =
        LearningPathService.fromContext(context, activeGameIds: activeIds);
    var pathNext = LearningPathService.nextOnPath(path, currentGameId);
    if (pathNext != null) {
      // Sequential unlock: only offer the next step if it's actually open
      // (it normally is — finishing the current game just unlocked it).
      final completed =
          context.read<AssessmentProvider>().pathCompletedGameIds;
      final nextIndex =
          path.indexWhere((e) => e.game.id == pathNext!.game.id);
      if (!LearningPathService.isUnlocked(path, nextIndex, completed)) {
        pathNext = null;
      }
    }
    final next = pathNext?.game ??
        (path.isEmpty ? GameLauncher.nextEntry(currentGameId) : null);
    final palette = context.read<ChildProvider>().activePalette;

    final playNext = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black26,
      builder: (_) => _GameEndChoiceContent(
        palette: palette,
        nextGameIcon: next?.icon,
        nextGameName: next?.name,
      ),
    );
    if (!context.mounted) return;

    if (playNext == true && next != null) {
      final override = context.read<ChildProvider>().difficultyOverride;
      final difficulty = override?.clamp(1, 3) ??
          pathNext?.difficulty ??
          GameLauncher.difficultyFor(context, next);
      final screen = GameLauncher.screenFor(next.id, difficulty);
      if (screen != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => screen),
        );
        return;
      }
    }
    Navigator.of(context).pop(); // Back to the lobby
  }
}

class _GameEndChoiceContent extends StatelessWidget {
  const _GameEndChoiceContent({
    required this.palette,
    required this.nextGameIcon,
    required this.nextGameName,
  });

  final GamePalette palette;
  final IconData? nextGameIcon;
  final String? nextGameName;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Back to the lobby
            _ChoiceButton(
              background: AppColors.white,
              borderColor: palette.primary.withValues(alpha: 0.4),
              iconColor: palette.primary,
              icon: Icons.home_rounded,
              label: 'Lobby',
              labelColor: palette.primary,
              onTap: () => Navigator.of(context).pop(false),
            ),
            const SizedBox(width: AppSpacing.lg),
            // Play the next game
            if (nextGameIcon != null)
              _ChoiceButton(
                background: palette.primary,
                borderColor: palette.primary,
                iconColor: palette.onPrimary,
                icon: nextGameIcon!,
                badgeIcon: Icons.play_arrow_rounded,
                label: nextGameName ?? 'Next',
                labelColor: palette.onPrimary,
                onTap: () => Navigator.of(context).pop(true),
              ),
          ],
        ),
      ),
    );
  }
}

/// One big, icon-first choice button (ASD-friendly: large target, minimal
/// text, high contrast).
class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.background,
    required this.borderColor,
    required this.iconColor,
    required this.icon,
    required this.label,
    required this.labelColor,
    required this.onTap,
    this.badgeIcon,
  });

  final Color background;
  final Color borderColor;
  final Color iconColor;
  final IconData icon;
  final IconData? badgeIcon;
  final String label;
  final Color labelColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          width: 148,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 2.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 56, color: iconColor),
                  if (badgeIcon != null)
                    Positioned(
                      right: -14,
                      bottom: -6,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: iconColor.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(badgeIcon, size: 22, color: iconColor),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.titleMedium.copyWith(
                  color: labelColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
