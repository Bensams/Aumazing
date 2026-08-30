import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:game_core/game_core.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../model/gameplay_session.dart';
import '../../providers/assessment_provider.dart';
import '../../providers/child_provider.dart';
import '../../services/active_games_service.dart';
import '../../services/learning_path_service.dart';
import '../../services/parent_history_service.dart';
import '../../services/report_pdf_service.dart';
import 'history_models.dart';

/// Parent-facing history of a single child: every assessment run (pre and
/// post), their progress comparison, the completed My Path / modules, and
/// the recent practice sessions.
///
/// This is a read-only summary backed by local SQLite rows. The profile and
/// path inputs are passed in from the dashboard (which already knows the
/// active child and the current recommendation) so the screen never has to
/// re-derive them and can default to plain data in widget tests.
class ParentHistoryScreen extends StatefulWidget {
  const ParentHistoryScreen({
    super.key,
    required this.childId,
    this.childName,
    this.historyService,
    this.reportPdfSharer,
  });

  final String childId;
  final String? childName;

  /// Injectable so a widget test can land a canned summary without a
  /// database. Defaults to a real [ParentHistoryService].
  final ParentHistoryService? historyService;
  final ReportPdfSharer? reportPdfSharer;

  @override
  State<ParentHistoryScreen> createState() => _ParentHistoryScreenState();
}

class _ParentHistoryScreenState extends State<ParentHistoryScreen> {
  bool _loading = true;
  String? _error;
  HistorySummary? _summary;

  /// Set when the load ran while the assessment provider was still hydrating
  /// this child (AUM-308); the screen rebuilds once hydration lands so the
  /// My Path section is not stuck empty.
  bool _reloadQueued = false;
  bool _sharingReport = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // If the provider is still hydrating, the My Path section below can be
    // empty; queue a reload once hydration finishes (checked in build).
    _reloadQueued = context.read<AssessmentProvider>().isLoading;
    try {
      // The path filter needs the active-game set. Read the cache first and
      // only hit the network when it has never been fetched, exactly like
      // the assessment result view does.
      var activeIds = ActiveGamesService.instance.cachedActiveGameIds;
      activeIds ??= await ActiveGamesService.instance.activeGameIds;
      if (!mounted) return;

      final path = LearningPathService.fromContext(
        context,
        activeGameIds: activeIds,
      );
      final pathCompleted =
          context.read<AssessmentProvider>().pathCompletedGameIds;

      final summary = await (widget.historyService ?? ParentHistoryService())
          .loadHistory(
            childId: widget.childId,
            path: path,
            pathCompletedGameIds: pathCompleted,
          );
      if (mounted) {
        setState(() {
          _summary = summary;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      debugPrint('[ParentHistoryScreen] loadHistory failed: $e');
      if (mounted) {
        setState(() {
          _error = 'We couldn’t load your child’s history. Please try again.';
          _loading = false;
        });
      }
    }
  }

  void _retry() {
    setState(() {
      _error = null;
      _loading = true;
    });
    _load();
  }

  Future<void> _shareReport({
    required HistorySummary summary,
    required String childDisplayName,
  }) async {
    if (_sharingReport) return;
    setState(() => _sharingReport = true);
    try {
      await (widget.reportPdfSharer ?? ReportPdfService()).shareHistoryReport(
        summary: summary,
        childDisplayName: childDisplayName,
      );
    } catch (error) {
      debugPrint('[ParentHistoryScreen] report share failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'We couldn\u2019t create or share the PDF. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sharingReport = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final assessLoading = context.watch<AssessmentProvider>().isLoading;
    if (_reloadQueued && !assessLoading && !_loading && _error == null) {
      _reloadQueued = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_loading) _load();
      });
    }
    final children = context.watch<ChildProvider>().children;
    final matchingChildren = children.where((c) => c.id == widget.childId);
    final authorized = matchingChildren.isNotEmpty;
    final childName =
        widget.childName ??
        (authorized ? matchingChildren.first.displayName : 'Your child');

    return ParentAdaptiveOrientation(
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: AppGradients.parentLavenderMint,
          ),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(
                        childName: childName,
                        shareEnabled:
                            authorized &&
                            _summary != null &&
                            !_loading &&
                            _error == null,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (!authorized)
                        _buildUnauthorized()
                      else if (_loading)
                        _buildLoading()
                      else if (_error != null)
                        _buildError()
                      else
                        ..._buildSections(_summary!),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Back navigation, title, and the child's name (when supplied).
  Widget _buildHeader({required String childName, required bool shareEnabled}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Material(
          color: AppColors.white.withValues(alpha: 0.85),
          shape: const CircleBorder(),
          child: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Back',
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: AppColors.primaryPurple,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'History & Progress',
                style: AppTextStyles.headlineSmall.copyWith(
                  color: AppColors.primaryPurple,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                childName,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        SizedBox(
          width: 44,
          height: 44,
          child:
              _sharingReport
                  ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : IconButton(
                    key: const ValueKey('share-history-pdf'),
                    tooltip: 'Share as PDF',
                    onPressed:
                        shareEnabled
                            ? () => _shareReport(
                              summary: _summary!,
                              childDisplayName: childName,
                            )
                            : null,
                    icon: const Icon(
                      Icons.picture_as_pdf_rounded,
                      color: AppColors.primaryPurple,
                    ),
                  ),
        ),
      ],
    );
  }

  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Loading history...',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            color: AppColors.destructiveRed,
            size: 40,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppPrimaryButton(
            label: 'Try Again',
            icon: Icons.refresh_rounded,
            onPressed: _retry,
          ),
        ],
      ),
    );
  }

  /// Defensive RLS guard: the entry point always passes an authorized child,
  /// but a stale route or a deleted profile must never surface another
  /// child's rows.
  Widget _buildUnauthorized() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: AppCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.person_off_rounded,
              color: AppColors.mutedForeground,
              size: 40,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'This child is not available on your account.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSections(HistorySummary summary) {
    return [
      _buildAssessmentSection(summary),
      const SizedBox(height: AppSpacing.md),
      if (summary.comparison != null) ...[
        _buildComparisonSection(summary.comparison!),
        const SizedBox(height: AppSpacing.md),
      ],
      _buildCompletedSection(summary),
      const SizedBox(height: AppSpacing.md),
      _buildPracticeSection(summary),
    ];
  }

  // ── Assessment history ───────────────────────────────────────────────

  Widget _buildAssessmentSection(HistorySummary summary) {
    return Column(
      key: const ValueKey('history-assessments'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Assessment History'),
        const SizedBox(height: AppSpacing.sm),
        if (summary.runs.isEmpty)
          _emptyCard(
            'No assessments yet. Complete a pre-assessment to see results '
            'here.',
          )
        else
          for (final run in summary.runs) ...[
            _runCard(run),
            if (run != summary.runs.last) const SizedBox(height: AppSpacing.md),
          ],
      ],
    );
  }

  Widget _runCard(AssessmentRunHistory run) {
    final record = run.run;
    final isPre = record.type == 'pre';
    final date = record.completedAt ?? record.startedAt;

    // Config labels are per game; show each distinct flow once.
    final configLabels =
        <String>{
          for (final game in run.games)
            if (game.configLabel != null) game.configLabel!,
        }.toList();

    return AppCard(
      key: ValueKey('history-run-${record.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final typeBadge = _typeBadge(isPre ? 'PRE' : 'POST', isPre);
              final title = Text(
                isPre ? 'Pre-assessment' : 'Post-assessment',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
              );
              final status = StatusPillBadge(
                label: _statusLabel(record.status),
                level: _statusLevel(record.status),
                compact: true,
              );

              // Keep the title and status pill side by side on normal cards,
              // but stack them before the pill can squeeze the title away.
              if (constraints.maxWidth < 320) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        typeBadge,
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: title),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    status,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  typeBadge,
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: title),
                  const SizedBox(width: AppSpacing.sm),
                  status,
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _formatDate(date),
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.mutedForeground,
            ),
          ),
          if (run.games.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            for (final game in run.games) _gameRow(game),
          ],
          if (configLabels.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _chipWrap([for (final label in configLabels) _configChip(label)]),
          ],
          if (run.skills.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _chipWrap([
              for (final skill in run.skills)
                _skillChip('${skill.area}: ${skill.label}', skill.label),
            ]),
          ],
          if (run.recommendedModule != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Recommended: ${run.recommendedModule}',
              style: AppTextStyles.bodySmallStrong.copyWith(
                color: AppColors.primaryPurple,
              ),
            ),
          ],
          if (run.overallSummary != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              run.overallSummary!,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _typeBadge(String text, bool isPre) {
    final bg = isPre ? AppColors.lavenderLight : AppColors.mintLight;
    final fg = isPre ? AppColors.primaryPurple : AppColors.statusSuccessDark;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.chip,
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Text(text, style: AppTextStyles.statusBadge.copyWith(color: fg)),
    );
  }

  Widget _gameRow(RunGameRecord game) {
    // A run's game may not have an assessment-result row yet (in-progress
    // run): the model then carries totalItems=0, errorCount=0, accuracy=0.0.
    final hasResult = game.totalItems > 0;
    final accuracyPart =
        hasResult ? ' · ${(game.accuracy * 100).round()}% accuracy' : '';
    final errorCount = game.errorCount;
    final errorPart =
        hasResult && errorCount > 0
            ? ' · $errorCount ${errorCount == 1 ? 'error' : 'errors'}'
            : '';
    final scoreLine =
        hasResult
            ? 'Score ${game.score} of ${game.totalItems}'
            : 'Score ${game.score}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.sports_esports_rounded,
            size: 18,
            color: AppColors.mutedForeground,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              '${game.gameName} — $scoreLine$accuracyPart$errorPart',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _configChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.skyLight,
        borderRadius: AppRadius.chip,
        border: Border.all(
          color: AppColors.statusInfoDark.withValues(alpha: 0.2),
        ),
      ),
      child: Text(
        label,
        softWrap: true,
        style: AppTextStyles.statusBadge.copyWith(
          color: AppColors.statusInfoDark,
        ),
      ),
    );
  }

  Widget _skillChip(String label, String skillLabel) {
    final level = _skillLevel(skillLabel);
    final background = switch (level) {
      StatusLevel.success => AppColors.statusSuccessBg,
      StatusLevel.warning => AppColors.statusWarningBg,
      StatusLevel.danger => AppColors.statusDangerBg,
      StatusLevel.info => AppColors.statusInfoBg,
      StatusLevel.neutral => AppColors.muted,
    };
    final foreground = switch (level) {
      StatusLevel.success => AppColors.statusSuccessDark,
      StatusLevel.warning => AppColors.statusWarningDark,
      StatusLevel.danger => AppColors.statusDangerDark,
      StatusLevel.info => AppColors.statusInfoDark,
      StatusLevel.neutral => AppColors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.chip,
        border: Border.all(color: foreground.withAlpha(40)),
      ),
      child: Text(
        label,
        softWrap: true,
        style: AppTextStyles.statusBadge.copyWith(color: foreground),
      ),
    );
  }
  Widget _chipWrap(List<Widget> chips) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final chip in chips)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                child: chip,
              ),
          ],
        );
      },
    );
  }


  // ── Progress comparison ──────────────────────────────────────────────

  Widget _buildComparisonSection(ProgressComparison comparison) {
    final delta = comparison.overallDeltaPoints;
    return Column(
      key: const ValueKey('history-comparison'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Progress Comparison'),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _deltaRow(delta),
              const SizedBox(height: AppSpacing.sm),
              for (final area in comparison.areas) _areaComparisonRow(area),
            ],
          ),
        ),
      ],
    );
  }

  Widget _deltaRow(double delta) {
    final points = delta.round();
    final positive = points > 0;
    final negative = points < 0;
    final sign = positive ? '+' : '';
    final color =
        positive
            ? AppColors.statusSuccessDark
            : negative
            ? AppColors.statusWarningDark
            : AppColors.textSecondary;
    final icon =
        positive
            ? Icons.trending_up_rounded
            : negative
            ? Icons.trending_down_rounded
            : Icons.trending_flat_rounded;

    return Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            '$sign$points points overall',
            style: AppTextStyles.titleMedium.copyWith(color: color),
          ),
        ),
      ],
    );
  }

  Widget _areaComparisonRow(AreaComparisonRow area) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              area.area,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              area.before ?? '—',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.mutedForeground,
              ),
            ),
          ),
          const Icon(
            Icons.arrow_forward_rounded,
            size: 16,
            color: AppColors.primaryPurple,
          ),
          Expanded(
            flex: 2,
            child: Text(
              area.after ?? '—',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Completed My Path & modules ──────────────────────────────────────

  Widget _buildCompletedSection(HistorySummary summary) {
    final modules = summary.completedModules;
    return Column(
      key: const ValueKey('history-completed'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Completed My Path & Modules'),
        const SizedBox(height: AppSpacing.sm),
        if (modules.isEmpty)
          _emptyCard('No completed modules yet.')
        else
          for (final module in modules) ...[
            _completedModuleCard(module),
            if (module != modules.last) const SizedBox(height: AppSpacing.sm),
          ],
      ],
    );
  }

  Widget _completedModuleCard(CompletedModuleRecord module) {
    final completedAt = module.completedAt;
    final dateLine = completedAt != null ? _formatDate(completedAt) : '—';
    final levelLine =
        module.level > 0 ? 'Level ${module.level} of ${module.maxLevel}' : null;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Text(
                module.moduleName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
              );
              const status = StatusPillBadge(
                label: 'Completed',
                level: StatusLevel.success,
                compact: true,
              );

              // Keep the title and completion pill side by side on normal
              // cards, but stack them before the pill can squeeze the title.
              if (constraints.maxWidth < 320) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: AppSpacing.xs),
                    status,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: AppSpacing.sm),
                  status,
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            dateLine,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.mutedForeground,
            ),
          ),
          if (levelLine != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              levelLine,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (module.source == 'my_path' && module.gameCount > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${module.gameCount} '
              '${module.gameCount == 1 ? 'game' : 'games'} on the path',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Practice history ─────────────────────────────────────────────────

  Widget _buildPracticeSection(HistorySummary summary) {
    final sessions = summary.practiceSessions;
    return Column(
      key: const ValueKey('history-practice'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Practice History'),
        const SizedBox(height: AppSpacing.sm),
        if (sessions.isEmpty)
          _emptyCard('No practice sessions yet.')
        else ...[
          for (final session in sessions) ...[
            _practiceRow(session),
            if (session != sessions.last) const SizedBox(height: AppSpacing.xs),
          ],
          if (sessions.length == 20) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Showing the latest 20 sessions.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.mutedForeground,
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _practiceRow(GameplaySession session) {
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _gameName(session.gameId),
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            session.score.toString(),
            style: AppTextStyles.titleMedium.copyWith(
              color: AppColors.primaryPurple,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            _formatDate(session.endedAt),
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared helpers ───────────────────────────────────────────────────

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimary),
    );
  }

  Widget _emptyCard(String message) {
    return AppCard(
      child: Text(
        message,
        style: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.mutedForeground,
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'in_progress':
        return 'In progress';
      default:
        return 'Incomplete';
    }
  }

  StatusLevel _statusLevel(String status) {
    switch (status) {
      case 'completed':
        return StatusLevel.success;
      case 'in_progress':
        return StatusLevel.info;
      default:
        return StatusLevel.warning;
    }
  }

  StatusLevel _skillLevel(String label) {
    switch (label.toLowerCase()) {
      case 'strength':
        return StatusLevel.success;
      case 'emerging':
        return StatusLevel.warning;
      case 'needs support':
        return StatusLevel.danger;
      default:
        return StatusLevel.info;
    }
  }

  String _gameName(String gameId) {
    final entry = GameRegistry.find(gameId);
    if (entry != null) return entry.name;
    final words = gameId.replaceAll('_', ' ').trim();
    if (words.isEmpty) return 'Practice game';
    return words[0].toUpperCase() + words.substring(1);
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = date.toLocal();
    return '${months[local.month - 1]} ${local.day}, ${local.year}';
  }
}
