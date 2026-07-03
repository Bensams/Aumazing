import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:game_core/game_core.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../providers/assessment_provider.dart';
import '../../providers/child_provider.dart';
import '../../services/active_games_service.dart';
import '../../services/learning_path_service.dart';
import '../../services/screen_time_service.dart';
import 'game_launcher.dart';
import 'time_up_dialog.dart';

/// Child Mode Lobby.
///
/// Reached from the parent dashboard's "Enter Child Mode". The child first
/// picks a skill category (Play, Communication, Social Interaction), then sees
/// that category's games in a single horizontally-scrolling row. Games are
/// non-assessment (practice) mode, but difficulty follows the child's current
/// level from the latest assessment.
class ChildModeLobbyScreen extends StatefulWidget {
  const ChildModeLobbyScreen({super.key, this.openPath = false});

  /// When true, opens directly on the "My Path" view (used by the parent
  /// dashboard's Recommended Module card).
  final bool openPath;

  @override
  State<ChildModeLobbyScreen> createState() => _ChildModeLobbyScreenState();
}

class _ChildModeLobbyScreenState extends State<ChildModeLobbyScreen> {
  static const _categoryOrder = [
    SkillCategory.playSkills,
    SkillCategory.communication,
    SkillCategory.socialInteraction,
  ];

  /// The category the child tapped, or null while showing the buttons.
  SkillCategory? _selected;

  /// True when the child tapped "All" (show every game).
  bool _viewingAll = false;

  /// True when the child tapped "My Path" (AI-recommended order).
  bool _viewingPath = false;

  bool get _inView => _selected != null || _viewingAll || _viewingPath;

  /// Admin-enabled game ids; null until loaded (path shown once known).
  Set<String>? _activeGameIds;

  /// Screen-time usage ticker — runs for the whole child-mode session
  /// (this lobby stays mounted underneath the game screens).
  Timer? _screenTimeTicker;
  static const _tickSeconds = 15;

  @override
  void initState() {
    super.initState();
    _viewingPath = widget.openPath;
    ActiveGamesService.instance.activeGameIds.then((ids) {
      if (mounted) setState(() => _activeGameIds = ids);
    });
    _startScreenTimeTracking();
  }

  Future<void> _startScreenTimeTracking() async {
    final childId = context.read<ChildProvider>().profile?.id;
    if (childId == null) return;
    final screenTime = ScreenTimeService.instance;
    await screenTime.load(childId);
    if (!mounted) return;

    // Already out of time when entering child mode → gentle goodbye now.
    if (screenTime.isExhausted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) TimeUpDialog.show(context);
      });
    }

    _screenTimeTicker =
        Timer.periodic(const Duration(seconds: _tickSeconds), (_) async {
      if (!mounted) return;
      // The lock screen is up — stop counting until the parent unlocks.
      if (TimeUpDialog.isShowing) return;
      await screenTime.addUsage(_tickSeconds);
      // Never interrupt a game in progress — a mid-activity cutoff is
      // distressing for ASD children. Only enforce while the lobby itself
      // is visible; game endings are handled by GameEndChoiceDialog.
      if (mounted &&
          screenTime.isExhausted &&
          (ModalRoute.of(context)?.isCurrent ?? true)) {
        TimeUpDialog.show(context);
      }
    });
  }

  @override
  void dispose() {
    _screenTimeTicker?.cancel();
    super.dispose();
  }

  /// The AI-recommended learning path (empty when no assessment yet, all
  /// areas are at Strength, or active games are still loading).
  List<LearningPathEntry> _learningPath() =>
      LearningPathService.fromContext(context, activeGameIds: _activeGameIds);

  /// All supported games, deduplicated (used by the "All" view/button).
  List<GameEntry> _allGames() => GameLauncher.supportedGames();

  void _launch(String gameId, int difficulty) {
    final screen = GameLauncher.screenFor(gameId, difficulty);
    if (screen == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
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
        return const [Color(0xFF9FD3B8), Color(0xFFABD2F0)]; // sage → sky
      case SkillCategory.communication:
        return const [Color(0xFFC7B4EC), Color(0xFFFBE49A)]; // lavender → butter
      case SkillCategory.socialInteraction:
        return const [Color(0xFFABD2F0), Color(0xFFF6C6B4)]; // sky → peach
    }
  }

  List<GameEntry> _gamesFor(SkillCategory cat) =>
      GameRegistry.gamesForCategory(cat)
          .where((g) => GameLauncher.supportedGameIds.contains(g.id))
          .toList();

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<ChildProvider>().activePalette;
    // Watched so difficulty chips refresh when the AI result or the parent's
    // override changes.
    final level = context.watch<AssessmentProvider>().recommendedLevel;
    context.watch<ChildProvider>().difficultyOverride;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: palette.gameBackground),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(palette, level),
              Expanded(
                child: !_inView
                    ? _buildCategoryButtons(palette)
                    : _buildGamesRow(level, palette),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────

  Widget _buildHeader(GamePalette palette, int level) {
    final title = _viewingPath
        ? 'My Path'
        : _viewingAll
            ? 'All Games'
            : (_selected?.displayName ?? 'Choose a Game');
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
      child: Row(
        children: [
          if (_inView)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Material(
                color: AppColors.white.withAlpha(200),
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: () => setState(() {
                    _selected = null;
                    _viewingAll = false;
                    _viewingPath = false;
                  }),
                  icon: Icon(Icons.arrow_back_rounded, color: palette.primary),
                  tooltip: 'Back',
                ),
              ),
            ),
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.white.withAlpha(235),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.displayMedium.copyWith(
                        color: palette.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
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
                ],
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
    final path = _learningPath();
    final buttons = <Widget>[
      // AI-recommended path first — the child's suggested starting point.
      if (path.isNotEmpty)
        _CategoryButton(
          label: 'My Path',
          icon: Icons.route_rounded,
          gradient: const [Color(0xFFC7B4EC), Color(0xFFA9E3CC)], // lavender → mint
          count: path.length,
          onTap: () => setState(() => _viewingPath = true),
        ),
      _CategoryButton(
        label: 'All',
        icon: Icons.apps_rounded,
        gradient: const [Color(0xFFFBD89A), Color(0xFFA9E3CC)], // amber → mint
        count: _allGames().length,
        onTap: () => setState(() => _viewingAll = true),
      ),
      for (final cat in _categoryOrder)
        _CategoryButton(
          label: cat.displayName,
          icon: _iconForCategory(cat),
          gradient: _gradientForCategory(cat),
          count: _gamesFor(cat).length,
          onTap: () => setState(() => _selected = cat),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
      child: Row(
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            Expanded(child: buttons[i]),
            if (i != buttons.length - 1) const SizedBox(width: AppSpacing.md),
          ],
        ],
      ),
    );
  }

  // ── Step 2: games in a single horizontal row ───────────────────────────

  Widget _buildGamesRow(int fallbackLevel, GamePalette palette) {
    if (_viewingPath) return _buildPathRow();

    final games = _viewingAll ? _allGames() : _gamesFor(_selected!);
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
          itemBuilder: (_, i) {
            // Per-game difficulty: parent override → AI per-area → fallback.
            final difficulty = GameLauncher.difficultyFor(
              context,
              games[i],
              fallback: fallbackLevel,
            );
            return _GameCard(
              entry: games[i],
              difficulty: difficulty,
              onTap: () => _launch(games[i].id, difficulty),
            );
          },
        ),
      ),
    );
  }

  /// The AI-recommended path: same cards, in recommended order, numbered,
  /// each starting at the difficulty the assessment suggested. Steps unlock
  /// sequentially — the child must finish a game to open the next one.
  Widget _buildPathRow() {
    final path = _learningPath();
    if (path.isEmpty) {
      return Center(
        child: Text('Finish an assessment to get your path!',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.mutedForeground)),
      );
    }
    // Watched so cards re-render (unlock) when a game completes.
    final completed =
        context.watch<AssessmentProvider>().pathCompletedGameIds;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: SizedBox(
        height: 200,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          itemCount: path.length,
          separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
          itemBuilder: (_, i) {
            final step = path[i];
            final unlocked = LearningPathService.isUnlocked(path, i, completed);
            final done = completed.contains(step.game.id);
            // The parent's manual override still wins over the path level.
            final override =
                context.read<ChildProvider>().difficultyOverride;
            final difficulty = (override ?? step.difficulty).clamp(1, 3);
            return _GameCard(
              entry: step.game,
              difficulty: difficulty,
              stepNumber: i + 1,
              locked: !unlocked,
              completed: done,
              onTap: unlocked
                  ? () => _launch(step.game.id, difficulty)
                  : null,
            );
          },
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
  const _GameCard({
    required this.entry,
    required this.difficulty,
    required this.onTap,
    this.stepNumber,
    this.locked = false,
    this.completed = false,
  });

  final GameEntry entry;

  /// 1 Easy / 2 Medium / 3 Hard — from the child's per-area AI level.
  final int difficulty;

  /// 1-based position on the learning path; shows a numbered badge.
  final int? stepNumber;

  /// Sequential unlock: locked steps are muted and not tappable.
  final bool locked;

  /// Completed steps show a checkmark (still replayable).
  final bool completed;

  final VoidCallback? onTap;

  static const _tierLabels = {1: 'Easy', 2: 'Medium', 3: 'Hard'};
  static const _tierColors = {
    1: Color(0xFF6FAE97), // sage — gentle
    2: Color(0xFFDD9B4A), // amber — moderate
    3: Color(0xFFC96B6B), // clay — challenge
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      child: Opacity(
        // Locked steps are visibly muted (and not tappable).
        opacity: locked ? 0.45 : 1.0,
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.white.withAlpha(200),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                            locked ? Icons.lock_rounded : entry.icon,
                            color: AppColors.primaryPurple,
                            size: 30),
                      ),
                      if (stepNumber != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: completed
                                ? const Color(0xFF43A047) // done — green
                                : AppColors.primaryPurple,
                            shape: BoxShape.circle,
                          ),
                          child: completed
                              ? const Icon(Icons.check_rounded,
                                  size: 18, color: AppColors.white)
                              : Text(
                                  '$stepNumber',
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: AppColors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ],
                      const Spacer(),
                      // Per-game difficulty tier from the child's AI level.
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.white.withAlpha(210),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _tierLabels[difficulty] ?? 'Medium',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: _tierColors[difficulty] ??
                                _tierColors[2],
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
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
      ),
    );
  }
}
