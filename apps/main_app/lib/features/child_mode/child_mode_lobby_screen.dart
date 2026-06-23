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
/// Reached from the parent dashboard's "Enter Child Mode". The child first
/// picks a skill category (Play, Communication, Social Interaction), then sees
/// that category's games in a single horizontally-scrolling row. Games are
/// non-assessment (practice) mode, but difficulty follows the child's current
/// level from the latest assessment.
class ChildModeLobbyScreen extends StatefulWidget {
  const ChildModeLobbyScreen({super.key});

  @override
  State<ChildModeLobbyScreen> createState() => _ChildModeLobbyScreenState();
}

class _ChildModeLobbyScreenState extends State<ChildModeLobbyScreen> {
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

  /// The category the child tapped, or null while showing the 3 buttons.
  SkillCategory? _selected;

  int _difficultyFromLevel(int level) => level.clamp(1, 3);

  void _launch(String gameId, int difficulty) {
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

  Future<void> _exitToParent() async {
    final verified = await ParentVerificationDialog.show(context);
    if (verified && mounted) {
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

  List<Color> _gradientForCategory(SkillCategory cat) {
    switch (cat) {
      case SkillCategory.playSkills:
        return const [Color(0xFFD4F4E8), Color(0xFFD4E8FA)];
      case SkillCategory.communication:
        return const [Color(0xFFE8DEFA), Color(0xFFFFF3D4)];
      case SkillCategory.socialInteraction:
        return const [Color(0xFFD4E8FA), Color(0xFFFFDDD4)];
    }
  }

  List<GameEntry> _gamesFor(SkillCategory cat) =>
      GameRegistry.gamesForCategory(cat)
          .where((g) => _supportedGameIds.contains(g.id))
          .toList();

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
              _buildHeader(palette, level),
              Expanded(
                child: _selected == null
                    ? _buildCategoryButtons(palette)
                    : _buildGamesRow(_selected!, difficulty, palette),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────

  Widget _buildHeader(GamePalette palette, int level) {
    final inCategory = _selected != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
      child: Row(
        children: [
          if (inCategory)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Material(
                color: AppColors.white.withAlpha(200),
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: () => setState(() => _selected = null),
                  icon: Icon(Icons.arrow_back_rounded, color: palette.primary),
                  tooltip: 'Back',
                ),
              ),
            ),
          Text(
            inCategory ? _selected!.displayName : 'Choose a Game',
            style: AppTextStyles.displayMedium.copyWith(
              color: palette.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
          Material(
            color: AppColors.white.withAlpha(200),
            shape: const CircleBorder(),
            child: IconButton(
              onPressed: _exitToParent,
              icon: Icon(Icons.lock_rounded, color: palette.primary),
              tooltip: 'Exit (parent only)',
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 1: category buttons ───────────────────────────────────────────

  Widget _buildCategoryButtons(GamePalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
      child: Row(
        children: [
          for (final cat in _categoryOrder) ...[
            Expanded(child: _CategoryButton(
              label: cat.displayName,
              icon: _iconForCategory(cat),
              gradient: _gradientForCategory(cat),
              count: _gamesFor(cat).length,
              onTap: () => setState(() => _selected = cat),
            )),
            if (cat != _categoryOrder.last) const SizedBox(width: AppSpacing.md),
          ],
        ],
      ),
    );
  }

  // ── Step 2: games in a single horizontal row ───────────────────────────

  Widget _buildGamesRow(
      SkillCategory cat, int difficulty, GamePalette palette) {
    final games = _gamesFor(cat);
    if (games.isEmpty) {
      return Center(
        child: Text('No games yet for this category.',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.mutedForeground)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: SizedBox(
        height: 200,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          itemCount: games.length,
          separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
          itemBuilder: (_, i) => _GameCard(
            entry: games[i],
            onTap: () => _launch(games[i].id, difficulty),
          ),
        ),
      ),
    );
  }
}

/// One of the three large skill-category buttons (step 1).
class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.count,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final List<Color> gradient;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradient,
            ),
            boxShadow: [
              BoxShadow(
                color: gradient.first.withAlpha(120),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.white.withAlpha(200),
                  shape: BoxShape.circle,
                ),
                child:
                    Icon(icon, color: AppColors.primaryPurple, size: 38),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                label,
                textAlign: TextAlign.center,
                style: AppTextStyles.titleLarge.copyWith(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$count ${count == 1 ? 'game' : 'games'}',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.mutedForeground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A game card shown in the horizontal row (step 2).
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
            padding: const EdgeInsets.all(AppSpacing.lg),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.white.withAlpha(200),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(entry.icon,
                      color: AppColors.primaryPurple, size: 30),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  entry.name,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(
                    entry.description,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.mutedForeground),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
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
