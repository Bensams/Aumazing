import 'package:flutter/material.dart';

import 'package:game_core/game_core.dart';
import 'package:shared_ui/shared_ui.dart';

/// The goal of My Turn, Your Turn, shown once before the first round of
/// practice play: "Let's take turns." — the words the voice says at the
/// start, in the child's language — with Buddy's piece, an arrow, and the
/// child's own piece, so a child who cannot read still sees who goes first
/// and who goes next.
///
/// Tapping anywhere starts the game; the screen also starts it on its own
/// after a few seconds so no child is left waiting on a card.
class TurnGoalCard extends StatelessWidget {
  const TurnGoalCard({
    super.key,
    required this.buddyEmoji,
    required this.childEmoji,
    required this.strings,
    required this.onStart,
  });

  final String buddyEmoji;
  final String childEmoji;
  final AppStrings strings;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('mtyt.goalCard'),
      behavior: HitTestBehavior.opaque,
      onTap: onStart,
      child: Container(
        color: const Color(0x33000000),
        alignment: Alignment.center,
        padding: AppSpacing.paddingMd,
        child: Semantics(
          button: true,
          label: '${strings.turnGoalTitle} ${strings.turnGoalOrder}',
          excludeSemantics: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.lg,
                ),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: AppRadius.card,
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      strings.turnGoalTitle,
                      style: AppTextStyles.headlineSmall.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Side(
                          emoji: buddyEmoji,
                          color: MyTurnYourTurnGame.buddyColor,
                          label: 'Buddy',
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 40,
                            color: AppColors.mutedForeground,
                          ),
                        ),
                        _Side(
                          emoji: childEmoji,
                          color: MyTurnYourTurnGame.childColor,
                          label: strings.turnGoalYou,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      strings.turnGoalOrder,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.textPrimary,
                        borderRadius: AppRadius.button,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.play_arrow_rounded,
                            color: AppColors.white,
                            size: 28,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            strings.letsPlay,
                            style: AppTextStyles.buttonMedium.copyWith(
                              color: AppColors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One player's piece, drawn like the game's tray tokens, with its name.
class _Side extends StatelessWidget {
  const _Side({required this.emoji, required this.color, required this.label});

  final String emoji;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 76,
          height: 76,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x55000000), width: 3),
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 38)),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: AppTextStyles.labelLarge.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
