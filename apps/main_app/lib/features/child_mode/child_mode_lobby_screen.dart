import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:game_core/game_core.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../providers/assessment_provider.dart';
import '../../providers/child_provider.dart';
import '../games/copy_me/copy_me_screen.dart';
import '../games/do_what_i_say/do_what_i_say_screen.dart';
import '../games/match_it/match_it_screen.dart';
import '../games/my_turn_your_turn/my_turn_your_turn_screen.dart';

/// Child Mode Lobby.
///
/// Reached from the parent dashboard's "Enter Child Mode". The child picks a
/// non-assessment (practice) game, grouped by skill category: Play,
/// Communication, and Social Interaction. Games are practice-mode (no
/// assessment), but their difficulty follows the child's current level from
/// the latest assessment.
class ChildModeLobbyScreen extends StatelessWidget {
  const ChildModeLobbyScreen({super.key});

  /// Games that have a main_app practice screen wired up.
  static const _supportedGameIds = {
    'match_it',
    'copy_me',
    'do_what_i_say',
    'my_turn_your_turn',
  };

  static const _categoryOrder = [
    SkillCategory.playSkills,
    SkillCategory.communication,
    SkillCategory.socialInteraction,
  ];

  int _difficultyFromLevel(int level) => level.clamp(1, 3);

  void _launch(BuildContext context, String gameId, int difficulty) {
    Widget? screen;
    switch (gameId) {
      case 'match_it':
        screen = MatchItScreen(
            assessmentContext: 'practice', difficulty: difficulty);
      case 'copy_me':
        screen =
            CopyMeScreen(assessmentContext: 'practice', difficulty: difficulty);
      case 'do_what_i_say':
        screen = DoWhatISayScreen(
            assessmentContext: 'practice', difficulty: difficulty);
      case 'my_turn_your_turn':
        screen = MyTurnYourTurnScreen(
            assessmentContext: 'practice', difficulty: difficulty);
    }
    if (screen == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen!));
  }

  Future<void> _exitToParent(BuildContext context) async {
    final verified = await ParentVerificationDialog.show(context);
    if (verified && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  IconData _iconForCategory(SkillCategory cat) {
    switch (cat) {
      case SkillCategory.playSkills:
        return Icons.extension_rounded;
      case SkillCategory.communication:
        return Icons.record_voice_over_rounded;
      case SkillCategory.socialInteraction:
        return Icons.people_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<ChildProvider>().activePalette;
    final level = context.watch<AssessmentProvider>().recommendedLevel;
    final difficulty = _difficultyFromLevel(level);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: palette.gameBackground),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
                child: Row(
                  children: [
                    Text(
                      'Choose a Game',
                      style: AppTextStyles.displayMedium.copyWith(
                        color: palette.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: palette.primary.withAlpha(30),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Level $level',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: palette.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Parent lock to exit child mode.
                    Material(
                      color: AppColors.white.withAlpha(200),
                      shape: const CircleBorder(),
                      child: IconButton(
                        onPressed: () => _exitToParent(context),
                        icon: Icon(Icons.lock_rounded, color: palette.primary),
                        tooltip: 'Exit (parent only)',
                      ),
                    ),
                  ],
                ),
              ),

              // ── Categorized games ───────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final cat in _categoryOrder)
                        _buildCategorySection(
                            context, cat, difficulty, palette),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategorySection(
    BuildContext context,
    SkillCategory cat,
    int difficulty,
    GamePalette palette,
  ) {
    final games = GameRegistry.gamesForCategory(cat)
        .where((g) => _supportedGameIds.contains(g.id))
        .toList();
    if (games.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconForCategory(cat), color: palette.primary, size: 22),
              const SizedBox(width: 8),
              Text(
                cat.displayName,
                style: AppTextStyles.titleLarge.copyWith(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              for (final g in games)
                _GameCard(
                  entry: g,
                  onTap: () => _launch(context, g.id, difficulty),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.entry, required this.onTap});

  final GameEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: entry.gradientColors,
              ),
              boxShadow: [
                BoxShadow(
                  color: entry.gradientColors.first.withAlpha(90),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.white.withAlpha(190),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(entry.icon,
                      color: AppColors.primaryPurple, size: 28),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.name,
                        style: AppTextStyles.titleMedium.copyWith(
                          color: AppColors.foreground,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.description,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.mutedForeground),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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
