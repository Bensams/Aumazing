import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../core/child_profile_policy.dart';
import '../../core/services/auth_service.dart';
import '../../providers/assessment_provider.dart';
import '../../providers/child_provider.dart';
import '../../providers/progress_provider.dart';
import '../../services/active_games_service.dart';
import '../../services/learning_path_service.dart';
import '../../services/screen_time_service.dart';
import '../settings/settings_screen.dart';
import '../child_mode/child_mode_lobby_screen.dart';
import '../post_assessment/post_assessment_progress_screen.dart';
import '../pre_assessment/assessment_dashboard_screen.dart';
import '../pre_assessment/pre_assessment_intro_screen.dart';
import '../splash/auth/child_profile_setup_screen.dart';
import '../splash/auth/login_screen.dart';

/// Parent Dashboard — the main hub after login.
///
/// Shows child summary, assessment status, progress, and action buttons
/// for starting pre-assessment or entering child mode.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.authService});

  final AuthService? authService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final AuthService _authService;
  bool _isLeftPanelExpanded = true;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
    lockParentLandscape();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        await _loadData();
        if (mounted) {
          await _verifyMusicPlaying();
        }
      }
    });
  }

  Future<void> _verifyMusicPlaying() async {
    try {
      // Longer delay to ensure navigation transition is fully complete
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;

      final audioService = context.read<AudioService>();
      final childProvider = context.read<ChildProvider>();
      debugPrint('[HomeScreen] Checking music state: isMusicPlaying=${audioService.isMusicPlaying}, musicEnabled=${childProvider.musicEnabled}');

      if (!childProvider.musicEnabled) {
        // User has music disabled — stop any music that may have started
        // during LoadingScreen before the profile was loaded.
        if (audioService.isMusicPlaying) {
          debugPrint('[HomeScreen] Music disabled but playing — stopping...');
          await audioService.stopMusic();
        } else {
          debugPrint('[HomeScreen] Music disabled and not playing — OK');
        }
      } else if (!audioService.isMusicPlaying) {
        debugPrint('[HomeScreen] Music enabled but not playing, trying to resume...');
        await audioService.resumeMusic();

        // Double-check if music is playing after resume attempt
        await Future.delayed(const Duration(milliseconds: 200));
        if (!audioService.isMusicPlaying) {
          debugPrint('[HomeScreen] Resume failed, starting fresh track...');
          await audioService.playRandomMusic(['bg_music.ogg', 'bg_music1.ogg']);
        }
      } else {
        debugPrint('[HomeScreen] Music already playing and enabled — OK');
      }
    } catch (e, stackTrace) {
      debugPrint('[HomeScreen] Error checking music: $e');
      debugPrint('[HomeScreen] Stack trace: $stackTrace');
    }
  }

  @override
  void dispose() {
    unlockParentOrientation();
    super.dispose();
  }

  Future<void> _loadData() async {
    final childProvider = context.read<ChildProvider>();
    await childProvider.loadProfile();

    if (!mounted) return;

    // Sync AudioConfig from the child's persisted settings so that
    // lifecycle callbacks (pause/resume) and playMusic() respect them.
    if (childProvider.hasProfile) {
      final audioService = context.read<AudioService>();
      audioService.updateConfig(AudioConfig(
        musicEnabled: childProvider.musicEnabled,
        musicVolume: childProvider.musicVolume,
        sfxEnabled: true,
        sfxVolume: childProvider.sfxVolume,
      ));
      debugPrint('[HomeScreen] Synced AudioConfig from profile: '
          'musicEnabled=${childProvider.musicEnabled}, '
          'musicVolume=${childProvider.musicVolume}');
    }

    final profile = childProvider.profile;
    if (profile == null ||
        validateBirthDate(profile.birthDate) !=
            ChildBirthDateValidation.valid) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder:
              (_) => const ChildProfileSetupScreen(
                initialErrorMessage:
                    'Aumazing currently supports children ages 2 to 6.',
              ),
        ),
        (_) => false,
      );
      return;
    }

    final childId = profile.id;

    context.read<AssessmentProvider>().loadAssessments(childId);
    context.read<ProgressProvider>().loadProgress(childId);
  }

  Future<void> _signOut() async {
    await _authService.signOut();
    if (mounted) {
      context.read<ChildProvider>().clear();
      context.read<AssessmentProvider>().clear();
      context.read<ProgressProvider>().clear();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  void _startPreAssessment() {
    final hasAssessment = context.read<AssessmentProvider>().hasPreAssessment;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => hasAssessment
            ? const AssessmentDashboardScreen()
            : const PreAssessmentIntroScreen(),
      ),
    );
  }

  void _enterChildMode() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ChildModeLobbyScreen(),
      ),
    );
  }

  /// True when the child has finished every step of the learning path and
  /// hasn't taken the post-assessment yet — time to measure improvement.
  bool _postAssessmentReady(AssessmentProvider assessProv) {
    if (assessProv.aiPrediction == null) return false;
    if (assessProv.hasPostAssessment) return false;
    final path = LearningPathService.fromContext(
      context,
      activeGameIds: ActiveGamesService.instance.cachedActiveGameIds,
    );
    if (path.isEmpty) return false;
    final done = assessProv.pathCompletedGameIds;
    return path.every((e) => done.contains(e.game.id));
  }

  /// Opens the child lobby directly on the AI-recommended learning path
  /// (from the Recommended Module card).
  void _openLearningPath() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ChildModeLobbyScreen(openPath: true),
      ),
    );
  }

  void _toggleLeftPanel() {
    setState(() {
      _isLeftPanelExpanded = !_isLeftPanelExpanded;
    });
  }

  void _showSettingsModal() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(authService: _authService),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient:
              context.watch<ChildProvider>().activePalette.parentBackground,
        ),
        child: Row(
          children: [
            // ── Left Panel: Child Summary (no SafeArea, sticks to edge) ─────────────────────────
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              width: _isLeftPanelExpanded ? 280 : 56,
              child: _buildChildPanel(),
            ),

            // ── Main Content ──────────────────────────────────────
            Expanded(
              child: SafeArea(
                left: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: AppSpacing.md),
                      _buildActionButtons(),
                      _buildScreenTimeStatus(),
                      const SizedBox(height: AppSpacing.md),
                      _buildAssessmentStatus(),
                      const SizedBox(height: AppSpacing.md),
                      _buildProgressSection(),
                      const SizedBox(height: AppSpacing.md),
                      _buildRecentActivity(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Consumer<ChildProvider>(
      builder: (context, childProv, _) {
        final profile = childProv.profile;
        final name = profile?.displayName ?? 'Child';
        final age = profile?.birthDate != null ? profile!.ageYears() : '?';
        final avatar = profile?.avatarEmoji ?? '🐻';
        final email = _authService.currentUser?.email ?? '';

        return Row(
          children: [
            // Avatar
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.lavenderLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(avatar, style: const TextStyle(fontSize: 28)),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Child info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "$name's Dashboard",
                    style: AppTextStyles.headlineSmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'Age $age',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.end,
                  children: [
                    if (email.isNotEmpty)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 240),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.white.withAlpha(180),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.email_outlined,
                                size: 16,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.settings_rounded),
                      tooltip: 'Settings',
                      onPressed: _showSettingsModal,
                      color: AppColors.textSecondary,
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout_rounded),
                      tooltip: 'Sign Out',
                      onPressed: _signOut,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Left Panel: Child Info ──────────────────────────────────────────

  Widget _buildChildPanel() {
    return Consumer<ChildProvider>(
      builder: (context, childProv, _) {
        final profile = childProv.profile;
        final name = profile?.displayName ?? 'Child';
        final age = profile?.birthDate != null ? profile!.ageYears() : '?';
        final avatar = profile?.avatarEmoji ?? '🐻';

        return Container(
          decoration: BoxDecoration(
            color: AppColors.white.withAlpha(200),
            border: Border(
              right: BorderSide(color: AppColors.border, width: 1),
            ),
          ),
          child: Column(
            children: [
              // Toggle button (always visible, right-aligned)
              SizedBox(
                height: 48,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: Icon(
                      _isLeftPanelExpanded
                          ? Icons.chevron_left_rounded
                          : Icons.chevron_right_rounded,
                    ),
                    onPressed: _toggleLeftPanel,
                    tooltip: _isLeftPanelExpanded ? 'Collapse' : 'Expand',
                  ),
                ),
              ),
              const Divider(height: 1),

              // Collapsed view - just avatar
              if (!_isLeftPanelExpanded)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            color: AppColors.lavenderLight,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              avatar,
                              style: const TextStyle(fontSize: 20),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Expanded view - full content
              if (_isLeftPanelExpanded) ...[
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: Column(
                      children: [
                        // Avatar
                        Container(
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                            color: AppColors.lavenderLight,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              avatar,
                              style: const TextStyle(fontSize: 32),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),

                        // Name
                        Text(
                          name.toString(),
                          style: AppTextStyles.titleLarge.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Age $age',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),

                        const SizedBox(height: AppSpacing.sm),
                        const Divider(indent: 24, endIndent: 24, height: 1),
                        const SizedBox(height: AppSpacing.sm),

                        // Quick stats
                        _buildQuickStat(
                          Icons.games_rounded,
                          'Sessions',
                          context
                              .watch<ProgressProvider>()
                              .totalSessions
                              .toString(),
                        ),
                        _buildQuickStat(
                          Icons.trending_up_rounded,
                          'Modules',
                          '${context.watch<ProgressProvider>().completedModules} done',
                        ),
                        _buildQuickStat(
                          Icons.assessment_rounded,
                          'Assessment',
                          context.watch<AssessmentProvider>().hasPreAssessment
                              ? 'Completed'
                              : 'Pending',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickStat(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 6,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: AppTextStyles.labelLarge.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Action Buttons ──────────────────────────────────────────────────

  Widget _buildActionButtons() {
    return Consumer<AssessmentProvider>(
      builder: (context, assessProv, _) {
        return Row(
          children: [
            Expanded(
              child: AppPrimaryButton(
                label:
                    assessProv.hasPreAssessment
                        ? 'Assessment'
                        : 'Start Pre-Assessment',
                onPressed: _startPreAssessment,
                icon: assessProv.hasPreAssessment
                    ? Icons.assessment_rounded
                    : Icons.play_circle_filled_rounded,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _ActionCard(
                icon: Icons.child_care_rounded,
                label: 'Enter Child Mode',
                subtitle: 'Hand device to child',
                color: AppColors.mint,
                onTap: _enterChildMode,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Compact "screen time today" monitor for the parent (FR: parents
  /// monitor screen time from the dashboard). Hidden when no limit is set.
  Widget _buildScreenTimeStatus() {
    final childId = context.watch<ChildProvider>().profile?.id;
    final screenTime = ScreenTimeService.instance;
    if (childId != null && screenTime.loadedChildId != childId) {
      screenTime.load(childId);
    }
    return ListenableBuilder(
      listenable: screenTime,
      builder: (context, _) {
        final limit = screenTime.limitMinutes;
        if (limit == null) return const SizedBox.shrink();
        final usedMin = (screenTime.usedTodaySeconds / 60).ceil();
        final fraction = (usedMin / limit).clamp(0.0, 1.0);
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Row(
            children: [
              const Icon(Icons.timer_rounded,
                  size: 16, color: AppColors.mutedForeground),
              const SizedBox(width: 6),
              Text(
                'Screen time today: $usedMin / $limit min',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.mutedForeground),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 6,
                    backgroundColor: AppColors.lavenderLight,
                    valueColor: AlwaysStoppedAnimation(
                      fraction >= 1.0
                          ? AppColors.statusWarningDark
                          : AppColors.mint,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Assessment Status ───────────────────────────────────────────────

  Widget _buildAssessmentStatus() {
    return Consumer<AssessmentProvider>(
      builder: (context, assessProv, _) {
        if (!assessProv.hasPreAssessment) {
          return AppCard(
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.statusWarningBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.statusWarningDark,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Pre-Assessment Needed',
                              style: AppTextStyles.titleMedium.copyWith(
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          const StatusPillBadge(
                            label: 'Pre-Assessment Needed',
                            level: StatusLevel.warning,
                            compact: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Start the pre-assessment to determine your child\'s starting level and get a recommended learning module.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        // Show recommendation — tapping opens the child lobby directly on
        // the AI-recommended learning path.
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _openLearningPath,
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.statusSuccessBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.recommend_rounded,
                        color: AppColors.statusSuccessDark,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recommended Module',
                            style: AppTextStyles.titleMedium.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            assessProv.recommendedModuleName ?? 'Basic Skills',
                            style: AppTextStyles.headlineSmall.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    StatusPillBadge(
                      label: 'Level ${assessProv.recommendedLevel}',
                      level: StatusLevel.info,
                      compact: true,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
              if (assessProv.hasPostAssessment) ...[
                const SizedBox(height: AppSpacing.sm),
                const Divider(),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    const Icon(
                      Icons.trending_up_rounded,
                      size: 18,
                      color: AppColors.statusSuccessDark,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Post-assessment completed — view progress below',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.statusSuccessDark,
                      ),
                    ),
                  ],
                ),
              ],
              // Learning path finished → offer the post-assessment so the
              // improvement can be measured (Use Case 7).
              if (_postAssessmentReady(assessProv)) ...[
                const SizedBox(height: AppSpacing.sm),
                const Divider(),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    const Icon(
                      Icons.emoji_events_rounded,
                      size: 18,
                      color: AppColors.primaryPurple,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Learning path complete! Measure the progress with '
                        'a post-assessment.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    AppPrimaryButton(
                      label: 'Start Post-Assessment',
                      icon: Icons.play_arrow_rounded,
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const PostAssessmentProgressScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ── Progress Section ────────────────────────────────────────────────

  Widget _buildProgressSection() {
    return Consumer<AssessmentProvider>(
      builder: (context, assessProv, _) {
        if (assessProv.preResults.isEmpty) {
          return const SizedBox.shrink();
        }

        final results = assessProv.preResults;
        final barGroups = <BarChartGroupData>[];

        for (var i = 0; i < results.length && i < 4; i++) {
          barGroups.add(
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: results[i].adjustedAccuracy * 100,
                  color: AppColors.primaryPurple,
                  width: 20,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                ),
              ],
            ),
          );
        }

        final gameLabels =
            results.take(4).map((r) => r.gameId.replaceAll('_', ' ')).toList();

        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Assessment Scores',
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 160,
                child: BarChart(
                  BarChartData(
                    maxY: 100,
                    barGroups: barGroups,
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 32,
                          getTitlesWidget: (value, meta) {
                            if (value % 25 == 0) {
                              return Text(
                                '${value.toInt()}%',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final idx = value.toInt();
                            if (idx < gameLabels.length) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  gameLabels[idx],
                                  style: AppTextStyles.bodySmall.copyWith(
                                    fontSize: 10,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Recent Activity ─────────────────────────────────────────────────

  Widget _buildRecentActivity() {
    return Consumer<ProgressProvider>(
      builder: (context, progressProv, _) {
        final sessions = progressProv.recentSessions;

        if (sessions.isEmpty) {
          return AppCard(
            child: Center(
              child: Padding(
                padding: AppSpacing.paddingMd,
                child: Column(
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 36,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'No activity yet',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Start a pre-assessment or enter child mode to begin!',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recent Activity',
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ...sessions.take(5).map((session) {
                final gameName = session.gameId.replaceAll('_', ' ');
                final time = _formatDuration(session.duration);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.lavenderLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.games_rounded,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              gameName[0].toUpperCase() + gameName.substring(1),
                              style: AppTextStyles.labelLarge.copyWith(
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              '${session.score}/${session.totalItems} correct · $time',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _formatDate(session.endedAt),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds % 60}s';
    }
    return '${d.inSeconds}s';
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ── Supporting Widgets ────────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white.withAlpha(230),
      borderRadius: AppRadius.card,
      child: InkWell(
        borderRadius: AppRadius.card,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadius.card,
            border: Border.all(color: color.withAlpha(80)),
            boxShadow: AppShadows.card,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withAlpha(40),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
