import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../core/services/auth_service.dart';
import '../../providers/assessment_provider.dart';
import '../../providers/child_provider.dart';
import '../../providers/progress_provider.dart';
import '../games/match_it/match_it_screen.dart';
import '../splash/auth/login_screen.dart';

/// Parent Dashboard — the main hub after login.
///
/// Shows child summary, assessment status, progress, and action buttons
/// for starting pre-assessment or entering child mode.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _authService = AuthService();

  @override
  void initState() {
    super.initState();
    lockParentLandscape();
    _loadData();
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
    final childId = childProvider.profile?.id;
    if (childId == null) return;

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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MatchItScreen(
          assessmentContext: 'pre_assessment',
        ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ParentModeTopBar(
        title: 'Aumazing',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign Out',
            onPressed: _signOut,
          ),
        ],
      ),
      body: Container(
        decoration:
            const BoxDecoration(gradient: AppGradients.parentLavenderMint),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              // ── Left Panel: Child Summary ─────────────────────────
              SizedBox(
                width: 280,
                child: _buildChildPanel(),
              ),

              // ── Main Content ──────────────────────────────────────
              Expanded(
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
            ],
          ),
        ),
      ),
    );
  }

  // ── Left Panel: Child Info ──────────────────────────────────────────

  Widget _buildChildPanel() {
    return Consumer<ChildProvider>(
      builder: (context, childProv, _) {
        final profile = childProv.profile;
        final meta = _authService.childProfile;

        final name = profile?.name ?? meta?['name'] ?? 'Child';
        final age = profile?.age ?? meta?['age'] ?? '?';
        final avatar = profile?.avatar ?? meta?['avatar'] ?? '🐻';

        return Container(
          decoration: BoxDecoration(
            color: AppColors.white.withAlpha(200),
            border: Border(
              right: BorderSide(color: AppColors.border, width: 1),
            ),
          ),
          child: Column(
            children: [
              // Scrollable top section
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
                          child: Text(avatar,
                              style: const TextStyle(fontSize: 32)),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),

                      // Name
                      Text(
                        name.toString(),
                        style: AppTextStyles.titleLarge.copyWith(
                          color: AppColors.primaryPurple,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Age $age',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.mutedForeground,
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

              // Pinned comfort settings at bottom
              const Divider(indent: 24, endIndent: 24, height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: Column(
                  children: [
                    _buildToggle(
                      Icons.music_note_rounded,
                      'Music',
                      childProv.musicEnabled,
                      (val) => childProv.updateComfortSettings(
                        musicEnabled: val,
                      ),
                    ),
                    _buildToggle(
                      Icons.vibration_rounded,
                      'Vibration',
                      childProv.vibrationEnabled,
                      (val) => childProv.updateComfortSettings(
                        vibrationEnabled: val,
                      ),
                    ),
                  ],
                ),
              ),
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
          Icon(icon, size: 20, color: AppColors.primaryPurple),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(label, style: AppTextStyles.bodyMedium),
          ),
          Text(
            value,
            style: AppTextStyles.labelLarge.copyWith(
              color: AppColors.primaryPurple,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggle(
    IconData icon,
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.mutedForeground),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: AppTextStyles.bodySmall),
        ),
        Transform.scale(
          scale: 0.8,
          child: Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primaryPurple,
          ),
        ),
      ],
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
                label: assessProv.hasPreAssessment
                    ? 'Retake Pre-Assessment'
                    : 'Start Pre-Assessment',
                onPressed: _startPreAssessment,
                icon: Icons.play_circle_filled_rounded,
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
                    color: AppColors.butterLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFFD4A017),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pre-Assessment Needed',
                        style: AppTextStyles.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Start the pre-assessment to determine your child\'s starting level and get a recommended learning module.',
                        style: AppTextStyles.bodySmall,
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
                      color: AppColors.mintLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.recommend_rounded,
                      color: AppColors.mint,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recommended Module',
                          style: AppTextStyles.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          assessProv.recommendedModuleName ?? 'Basic Skills',
                          style: AppTextStyles.headlineSmall.copyWith(
                            color: AppColors.primaryPurple,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.lavenderLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Level ${assessProv.recommendedLevel}',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.primaryPurple,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (assessProv.hasPostAssessment) ...[
                const SizedBox(height: AppSpacing.sm),
                const Divider(),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    const Icon(Icons.trending_up_rounded,
                        size: 18, color: AppColors.mint),
                    const SizedBox(width: 6),
                    Text(
                      'Post-assessment completed — view progress below',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.mint,
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
                  toY: results[i].accuracy * 100,
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

        final gameLabels = results
            .take(4)
            .map((r) => r.gameId.replaceAll('_', ' '))
            .toList();

        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Assessment Scores', style: AppTextStyles.titleMedium),
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
                                style: AppTextStyles.bodySmall,
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
                                  style: AppTextStyles.bodySmall
                                      .copyWith(fontSize: 10),
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
                      color: AppColors.muted,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'No activity yet',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Start a pre-assessment or enter child mode to begin!',
                      style: AppTextStyles.bodySmall,
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
              Text('Recent Activity', style: AppTextStyles.titleMedium),
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
                          color: AppColors.primaryPurple,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              gameName[0].toUpperCase() +
                                  gameName.substring(1),
                              style: AppTextStyles.labelLarge,
                            ),
                            Text(
                              '${session.score}/${session.totalItems} correct · $time',
                              style: AppTextStyles.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _formatDate(session.endedAt),
                        style: AppTextStyles.bodySmall,
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
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withAlpha(80)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTextStyles.titleMedium),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
