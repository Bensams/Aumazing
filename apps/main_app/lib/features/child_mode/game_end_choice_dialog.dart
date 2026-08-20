import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:game_core/game_core.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../providers/assessment_provider.dart';
import '../../providers/child_provider.dart';
import '../../providers/stars_provider.dart';
import '../stars/star_catalogue.dart';
import '../stars/widgets/star_earned_overlay.dart';
import '../../services/active_games_service.dart';
import '../../services/learning_path_service.dart';
import '../../services/screen_time_service.dart';
import 'game_launcher.dart';
import 'time_up_dialog.dart';

/// What the child picked on the post-game choice.
enum _EndChoice { lobby, again, next }

/// Post-reward choice for practice (non-assessment) games: play the same game
/// again, play the next game, or go back to the lobby.
///
/// Icon-first and reading-free (the children may not read yet): three large
/// buttons — a home icon for the lobby, the current game's icon with a replay
/// arrow, and the next game's icon with a play arrow. Shown after the reward
/// finishes; never in assessment flows.
class GameEndChoiceDialog {
  GameEndChoiceDialog._();

  /// Shows the choice and performs the navigation:
  /// - Again → replaces the current game screen with a fresh run of the same
  ///   game (same difficulty resolution as the lobby)
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
    // Stars are awarded here rather than inside each game screen: this is the
    // one place all ten of them converge, and it runs AFTER the reward overlay
    // has finished, which is where STAR-B2 requires the star moment to sit —
    // never stacked on top of the celebration.
    //
    // Note that nothing about how the game *went* reaches this call. That is
    // what makes "the payout cannot depend on performance" (STAR-B1)
    // structural rather than a promise someone has to remember to keep.
    await _awardStars(context, currentGameId);
    if (!context.mounted) return;

    // Screen-time enforcement happens here — at the natural boundary after
    // a game finishes (never mid-game). Out of time → gentle break screen
    // instead of offering the next game.
    //
    // Deliberately AFTER the award: a child whose time ran out on this game
    // still earned this game's stars. Withholding them because the session
    // ended would turn the timer into a punishment.
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
    final current = GameRegistry.find(currentGameId);
    final palette = context.read<ChildProvider>().activePalette;

    final choice = await showDialog<_EndChoice>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black26,
      builder: (_) => _GameEndChoiceContent(
        palette: palette,
        currentGameIcon: current?.icon,
        currentGameLogo: current?.logoAsset,
        nextGameIcon: next?.icon,
        nextGameLogo: next?.logoAsset,
        nextGameName: next?.name,
      ),
    );
    if (!context.mounted) return;

    // Which game to launch, if any — the same one again, or the next one.
    final replay = choice == _EndChoice.again;
    final target = replay ? current : (choice == _EndChoice.next ? next : null);
    if (target != null) {
      final override = context.read<ChildProvider>().difficultyOverride;
      int? pathDifficulty = pathNext?.difficulty;
      if (replay) {
        final i = path.indexWhere((e) => e.game.id == currentGameId);
        pathDifficulty = i < 0 ? null : path[i].difficulty;
      }
      final difficulty = override?.clamp(1, 3) ??
          pathDifficulty ??
          GameLauncher.difficultyFor(context, target);
      final screen = GameLauncher.screenFor(target.id, difficulty);
      if (screen != null) {
        // The space world flies a spaceship on to the next round; other worlds
        // keep the plain replacement.
        Navigator.of(context).pushReplacement(
          GameLauncher.routeFor(context, screen),
        );
        return;
      }
    }
    Navigator.of(context).pop(); // Back to the lobby
  }

  /// Grants the fixed payout for the play that just finished and, if anything
  /// was granted, shows the short star moment.
  ///
  /// The play key is built from the child, the game and the **calendar day**
  /// rather than a session row id: the practice path does not create an
  /// assessment session, so there is no id to use.
  ///
  /// The day is what makes each game pay once per day (AUM-284). A replay of
  /// the same game lands on the same key, and `awardForSession` refuses a key
  /// it has already paid — so a second run of a favourite earns nothing, and
  /// tomorrow's run earns again. That also subsumes what the key was for
  /// before: a double-tapped "finish" or a rebuild cannot pay twice either.
  ///
  /// Local date, deliberately: `earnedTodayFor` counts from local midnight, so
  /// keying on anything else would let the two rules roll over at different
  /// moments and leave an hour where a game pays but the cap disagrees.
  static Future<void> _awardStars(
    BuildContext context,
    String currentGameId,
  ) async {
    final childId = context.read<ChildProvider>().profile?.id;
    if (childId == null) return;

    final stars = context.read<StarsProvider>();
    await stars.bind(childId);

    final award = await stars.awardForPlay(
      playKey: starPlayKey(childId: childId, gameId: currentGameId),
    );
    if (!context.mounted) return;

    switch (award.outcome) {
      case StarAwardOutcome.earned:
        await StarEarnedOverlay.show(context, granted: award.granted);

      case StarAwardOutcome.alreadyEarnedToday:
        // Names the game, then points somewhere. A child who has just
        // finished something has done the right thing and should hear so —
        // what changed is only where the remaining stars are (AUM-286).
        await StarEarnedOverlay.showNothingEarned(
          context,
          headline: "You already got today's star for "
              '${GameRegistry.find(currentGameId)?.name ?? 'this game'}!',
          note: stars.atDailyCap
              ? null
              : 'Try another game to earn more!',
        );

      case StarAwardOutcome.dailyCapReached:
        // Word for word what the shop says for this state, so a child meets
        // one sentence for "today is complete" and not two competing ones.
        await StarEarnedOverlay.showNothingEarned(
          context,
          headline: "You've got all of today's stars!",
        );

      case StarAwardOutcome.noChild:
        // Nothing was attempted, or the refusal had no explicable cause.
        // Silence is right here: an invented reason would be worse.
        break;
    }
  }
}

class _GameEndChoiceContent extends StatelessWidget {
  const _GameEndChoiceContent({
    required this.palette,
    required this.currentGameIcon,
    required this.currentGameLogo,
    required this.nextGameIcon,
    required this.nextGameLogo,
    required this.nextGameName,
  });

  final GamePalette palette;
  final IconData? currentGameIcon;
  final String? currentGameLogo;
  final IconData? nextGameIcon;
  final String? nextGameLogo;
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
            Flexible(
              child: _ChoiceButton(
                background: AppColors.white,
                borderColor: palette.primary.withValues(alpha: 0.4),
                iconColor: palette.primary,
                icon: Icons.home_rounded,
                label: 'Lobby',
                labelColor: palette.primary,
                onTap: () => Navigator.of(context).pop(_EndChoice.lobby),
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            // Play the same game again — sits between Lobby and Next so the
            // familiar choice is the easiest one to reach.
            Flexible(
              child: _ChoiceButton(
                background: AppColors.white,
                borderColor: palette.primary,
                iconColor: palette.primary,
                icon: currentGameIcon ?? Icons.replay_rounded,
                logoAsset: currentGameLogo,
                badgeIcon: Icons.replay_rounded,
                label: 'Again',
                labelColor: palette.primary,
                onTap: () => Navigator.of(context).pop(_EndChoice.again),
              ),
            ),
            // Play the next game
            if (nextGameIcon != null) ...[
              const SizedBox(width: AppSpacing.lg),
              Flexible(
                child: _ChoiceButton(
                  background: palette.primary,
                  borderColor: palette.primary,
                  iconColor: palette.onPrimary,
                  icon: nextGameIcon!,
                  logoAsset: nextGameLogo,
                  badgeIcon: Icons.play_arrow_rounded,
                  label: nextGameName ?? 'Next',
                  labelColor: palette.onPrimary,
                  onTap: () => Navigator.of(context).pop(_EndChoice.next),
                ),
              ),
            ],
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
    this.logoAsset,
  });

  /// Illustrated game tile to show instead of [icon], when this button stands
  /// for a specific game.
  final String? logoAsset;

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
                  // "Next" shows the game's own logo so the child recognises
                  // what they are agreeing to play; "Lobby" is a plain icon.
                  if (logoAsset != null)
                    GameLogo(
                      asset: logoAsset,
                      size: 56,
                      fallbackIcon: icon,
                      fallbackColor: iconColor,
                      semanticLabel: label,
                    )
                  else
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
