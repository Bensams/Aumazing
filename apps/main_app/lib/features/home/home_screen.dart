import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_haptic/shared_haptic.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../core/child_profile_policy.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/sync_service.dart';
import '../../providers/assessment_provider.dart';
import '../../providers/child_provider.dart';
import '../../providers/progress_provider.dart';
import '../rewards/widgets/reward_preference_selector.dart';
import '../games/match_it/match_it_screen.dart';
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
        builder: (_) => const MatchItScreen(assessmentContext: 'practice'),
      ),
    );
  }

  void _toggleLeftPanel() {
    setState(() {
      _isLeftPanelExpanded = !_isLeftPanelExpanded;
    });
  }

  void _showSettingsModal() {
    showDialog(
      context: context,
      builder: (context) => SettingsModal(authService: _authService),
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

        // Show recommendation
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                ],
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

/// Settings modal with music/vibration controls, sensory preferences,
/// and account binding option.
class SettingsModal extends StatelessWidget {
  const SettingsModal({super.key, required this.authService});

  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    final isGuest = authService.isGuestMode;
    final mediaQuery = MediaQuery.of(context);
    final availableHeight =
        mediaQuery.size.height - mediaQuery.viewInsets.vertical;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 360,
          maxHeight: availableHeight * 0.9,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.lavenderLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.settings_rounded,
                      color: AppColors.primaryPurple,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Flexible(
                    child: Text(
                      'Settings',
                      style: AppTextStyles.headlineSmall.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.md),

              Text(
                'Sensory & Comfort Settings',
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              Consumer<ChildProvider>(
                builder: (context, childProv, _) {
                  return Column(
                    children: [
                      // Music toggle
                      _buildSettingToggle(
                        Icons.music_note_rounded,
                        'Music',
                        childProv.musicEnabled,
                        (val) {
                          childProv.updateComfortSettings(musicEnabled: val);
                          final audioService = context.read<AudioService>();
                          // Sync AudioConfig so lifecycle callbacks respect the setting
                          audioService.updateConfig(audioService.config.copyWith(
                            musicEnabled: val,
                          ));
                          if (val) {
                            audioService.playRandomMusic(['bg_music.ogg', 'bg_music1.ogg']);
                          } else {
                            audioService.stopMusic();
                          }
                        },
                      ),
                      // Music volume slider (only when music is enabled)
                      if (childProv.musicEnabled)
                        _buildSettingSlider(
                          'Music Volume',
                          childProv.musicVolume,
                          (val) {
                            childProv.updateComfortSettings(musicVolume: val);
                            final audioService = context.read<AudioService>();
                            audioService.updateConfig(audioService.config.copyWith(
                              musicVolume: val,
                            ));
                          },
                        ),
                      // SFX volume slider
                      _buildSettingSlider(
                        'Sound Effects',
                        childProv.sfxVolume,
                        (val) {
                          childProv.updateComfortSettings(sfxVolume: val);
                          final audioService = context.read<AudioService>();
                          audioService.updateConfig(audioService.config.copyWith(
                            sfxVolume: val,
                          ));
                        },
                      ),
                      // Vibration toggle
                      _buildSettingToggle(
                        Icons.vibration_rounded,
                        'Vibration',
                        childProv.vibrationEnabled,
                        (val) {
                          childProv.updateComfortSettings(vibrationEnabled: val);
                          final hapticService = context.read<HapticService>();
                          hapticService.updateConfig(hapticService.config.copyWith(
                            enabled: val,
                          ));
                        },
                      ),
                      // Animation intensity slider
                      _buildSettingSlider(
                        'Animation Intensity',
                        childProv.animationIntensity,
                        (val) => childProv.updateComfortSettings(
                          animationIntensity: val,
                        ),
                      ),
                      // Prompt speed slider
                      _buildSettingSlider(
                        'Prompt Speed',
                        childProv.promptSpeed,
                        (val) => childProv.updateComfortSettings(
                          promptSpeed: val,
                        ),
                      ),
                    ],
                  );
                },
              ),

              // Reward Preferences Section
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Reward Celebration',
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              Consumer<ChildProvider>(
                builder: (context, childProv, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Reward type dropdown
                      RewardPreferenceDropdown(
                        selectedPreference: childProv.rewardPreference,
                        useRandomReward: childProv.useRandomReward,
                        onPreferenceChanged: (preference) {
                          childProv.updateRewardPreferences(
                            rewardPreference: preference,
                            useRandomReward: false,
                          );
                        },
                        onRandomChanged: (useRandom) {
                          childProv.updateRewardPreferences(
                            useRandomReward: useRandom,
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      // Random toggle
                      _buildSettingToggle(
                        Icons.shuffle_rounded,
                        'Use Random Rewards',
                        childProv.useRandomReward,
                        (val) => childProv.updateRewardPreferences(
                          useRandomReward: val,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Padding(
                        padding: const EdgeInsets.only(left: 32),
                        child: Text(
                          'A different celebration every time!',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),

              // Background Theme Section
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Background Theme',
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Some children are sensitive to colors. Pick a calmer theme '
                'if the current one is overstimulating.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Consumer<ChildProvider>(
                builder: (context, childProv, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          for (final theme in GameTheme.values)
                            Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: _buildThemeOption(theme, childProv),
                              ),
                            ),
                        ],
                      ),
                      if (childProv.isThemeOverridden)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => childProv.clearThemeOverride(),
                            icon: const Icon(Icons.restart_alt_rounded,
                                size: 16),
                            label: const Text('Auto from gender'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),

              // Language Section
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.md),
              Consumer<ChildProvider>(
                builder: (context, childProv, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        childProv.strings.languageLabel,
                        style: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: 8,
                        children: GameLanguage.values.map((lang) {
                          final selected = childProv.language == lang;
                          return ChoiceChip(
                            label: Text(lang.label),
                            selected: selected,
                            selectedColor: AppColors.primaryPurple,
                            labelStyle: AppTextStyles.bodySmall.copyWith(
                              color: selected
                                  ? AppColors.white
                                  : AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                            onSelected: (_) => childProv.setLanguage(lang),
                          );
                        }).toList(),
                      ),
                    ],
                  );
                },
              ),

              if (isGuest) ...[
                const SizedBox(height: AppSpacing.md),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Account',
                  style: AppTextStyles.labelLarge.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildBindAccountButton(context),
              ],

              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Close',
                    style: AppTextStyles.labelLarge.copyWith(
                      color: AppColors.primaryPurple,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A tappable swatch for one background theme, showing its dashboard
  /// gradient and primary color. Highlights when it is the active theme.
  Widget _buildThemeOption(GameTheme theme, ChildProvider childProv) {
    final palette = GamePalettes.of(theme);
    final selected = childProv.activeTheme == theme;
    return GestureDetector(
      onTap: () => childProv.setThemeOverride(theme),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? palette.primary : AppColors.border,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              height: 40,
              decoration: BoxDecoration(
                gradient: palette.parentBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: palette.primary.withAlpha(60)),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: palette.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              theme.label,
              style: AppTextStyles.labelSmall.copyWith(
                color: selected ? palette.primary : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingToggle(
    IconData icon,
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.primaryPurple,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingSlider(
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              onChanged: onChanged,
              activeColor: AppColors.primaryPurple,
              inactiveColor: AppColors.lavenderLight,
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '${(value * 100).round()}%',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBindAccountButton(BuildContext context) {
    return Material(
      color: AppColors.butterLight,
      borderRadius: AppRadius.chip,
      child: InkWell(
        borderRadius: AppRadius.chip,
        onTap: () {
          Navigator.of(context).pop();
          showDialog(
            context: context,
            builder: (_) => BindAccountModal(authService: authService),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.butterYellow.withAlpha(60),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.link_rounded,
                  color: AppColors.statusWarningDark,
                  size: 18,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bind Account',
                      style: AppTextStyles.labelLarge.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Save your progress permanently',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bind Account modal for guest users to link their progress
class BindAccountModal extends StatefulWidget {
  const BindAccountModal({super.key, required this.authService});

  final AuthService authService;

  @override
  State<BindAccountModal> createState() => _BindAccountModalState();
}

enum _BindAccountStep { options, email }

class _BindAccountModalState extends State<BindAccountModal> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  _BindAccountStep _step = _BindAccountStep.options;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _bindAccount() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _errorMessage = 'Please enter email and password');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Ensure we have a valid Supabase session before binding.
      // If user only has local guest mode (no Supabase session), sign in anonymously first.
      if (widget.authService.currentUser == null) {
        await widget.authService.signInAnonymously();
      }

      // Convert anonymous/guest to permanent account
      await widget.authService.convertAnonymousToPermanent(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      // Clear stored guest session so a new guest account will be created
      // on the next guest sign-in (this account is now bound).
      await widget.authService.clearStoredGuestSession();

      // Backfill guest data and sync to Supabase
      final newUserId = widget.authService.currentUser?.id;
      if (newUserId != null) {
        await syncService.onUserAuthenticated(newUserId);
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account bound successfully!'),
            backgroundColor: AppColors.mint,
          ),
        );
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _bindWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Ensure we have a valid Supabase session before binding.
      // If user only has local guest mode (no Supabase session), sign in anonymously first.
      if (widget.authService.currentUser == null) {
        await widget.authService.signInAnonymously();
      }

      await widget.authService.bindAnonymousWithGoogle();

      // Clear stored guest session so a new guest account will be created
      // on the next guest sign-in (this account is now bound).
      await widget.authService.clearStoredGuestSession();

      // Backfill guest data and sync to Supabase
      final newUserId = widget.authService.currentUser?.id;
      if (newUserId != null) {
        await syncService.onUserAuthenticated(newUserId);
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google account linked successfully!'),
            backgroundColor: AppColors.mint,
          ),
        );
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showEmailStep() {
    setState(() {
      _step = _BindAccountStep.email;
      _errorMessage = null;
    });
  }

  void _showOptionStep() {
    setState(() {
      _step = _BindAccountStep.options;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final availableHeight =
        mediaQuery.size.height - mediaQuery.viewInsets.vertical;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 340,
          maxHeight: availableHeight * 0.9,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child:
              _step == _BindAccountStep.options
                  ? _buildOptionStep(context)
                  : _buildEmailStep(context),
        ),
      ),
    );
  }

  Widget _buildOptionStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader('Bind Account'),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Choose how you want to save this guest account permanently.',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_errorMessage != null) ...[
          _buildErrorBanner(),
          const SizedBox(height: AppSpacing.md),
        ],
        _buildBindOption(
          icon: Icons.g_mobiledata_rounded,
          title: 'Bind with Google',
          subtitle: 'Link this guest account to your Google sign-in',
          onTap: _isLoading ? null : _bindWithGoogle,
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildBindOption(
          icon: Icons.email_outlined,
          title: 'Bind with Email',
          subtitle: 'Create login details with email and password',
          onTap: _isLoading ? null : _showEmailStep,
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ),
      ],
    );
  }

  Widget _buildEmailStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader('Bind with Email'),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Create an email and password for this guest account.',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_errorMessage != null) ...[
          _buildErrorBanner(),
          const SizedBox(height: AppSpacing.md),
        ],
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'Email',
            prefixIcon: const Icon(Icons.email_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _passwordController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: _isLoading ? null : _showOptionStep,
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ElevatedButton(
                onPressed: _isLoading ? null : _bindAccount,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child:
                    _isLoading
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : const Text('Bind with Email'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeader(String title) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.butterLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.link_rounded, color: AppColors.statusWarningDark),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            title,
            style: AppTextStyles.headlineSmall.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.statusDangerBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.statusDangerDark, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              _errorMessage!,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.statusDangerDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBindOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: AppColors.white,
      borderRadius: AppRadius.chip,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.chip,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: AppRadius.chip,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.lavenderLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primaryPurple),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.labelLarge.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isLoading && title == 'Bind with Google')
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
