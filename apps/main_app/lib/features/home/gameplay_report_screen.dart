import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../model/gameplay_session.dart';

/// Parent-facing detail view for one completed gameplay session.
class GameplayReportScreen extends StatelessWidget {
  const GameplayReportScreen({
    super.key,
    required this.session,
    required this.palette,
  });

  final GameplaySession session;
  final GamePalette palette;

  String get _gameName {
    final words = session.gameId.replaceAll('_', ' ').trim();
    if (words.isEmpty) return 'Gameplay session';
    return words[0].toUpperCase() + words.substring(1);
  }

  String _duration(Duration value) {
    if (value.inMinutes > 0) {
      return '${value.inMinutes}m ${value.inSeconds % 60}s';
    }
    return '${value.inSeconds}s';
  }

  String _seconds(double value) => '${value.toStringAsFixed(1)}s';

  String _percent(double value) => '${(value * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: palette.parentBackground),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Material(
                          color: AppColors.white.withValues(alpha: 0.85),
                          shape: const CircleBorder(),
                          child: IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            tooltip: 'Back',
                            icon: Icon(
                              Icons.arrow_back_rounded,
                              color: palette.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Gameplay report',
                            style: AppTextStyles.headlineSmall.copyWith(
                              color: palette.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _gameName,
                            style: AppTextStyles.headlineSmall.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '${session.context.replaceAll('_', ' ')} · '
                            '${_formatDate(session.endedAt)}',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              Expanded(
                                child: _Metric(
                                  label: 'Score',
                                  value:
                                      '${session.score}/${session.totalItems}',
                                  color: palette.primary,
                                ),
                              ),
                              Expanded(
                                child: _Metric(
                                  label: 'Accuracy',
                                  value:
                                      session.totalItems == 0
                                          ? '0%'
                                          : _percent(
                                            session.score / session.totalItems,
                                          ),
                                  color: palette.primary,
                                ),
                              ),
                              Expanded(
                                child: _Metric(
                                  label: 'Duration',
                                  value: _duration(session.duration),
                                  color: palette.primary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _ReportSection(
                      title: 'Response and completion',
                      icon: Icons.speed_rounded,
                      palette: palette,
                      metrics: [
                        (
                          'Total response time',
                          _duration(
                            Duration(milliseconds: session.totalResponseTimeMs),
                          ),
                        ),
                        ('Average response', _seconds(session.avgResponseTime)),
                        (
                          'Average valid response',
                          _seconds(session.avgValidResponseTime),
                        ),
                        if (session.taskCompletionRate != null)
                          (
                            'Task completion',
                            _percent(session.taskCompletionRate!),
                          ),
                        if (session.timeToFirstTouch != null)
                          (
                            'Time to first touch',
                            _seconds(session.timeToFirstTouch!),
                          ),
                        if (session.timeToFirstValidAction != null)
                          (
                            'First valid action',
                            _seconds(session.timeToFirstValidAction!),
                          ),
                        if (session.timeToCompletion != null)
                          (
                            'Time to completion',
                            _seconds(session.timeToCompletion!),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _ReportSection(
                      title: 'Support and task behaviour',
                      icon: Icons.psychology_rounded,
                      palette: palette,
                      metrics: [
                        ('Errors', '${session.errorCount}'),
                        ('Retries', '${session.retryCount}'),
                        ('Hints', '${session.hintCount}'),
                        ('Prompts', '${session.promptCount}'),
                        ('Idle time', _seconds(session.idleTimeSeconds)),
                        ('Off-task actions', '${session.offTaskActionCount}'),
                        ('Random touches', '${session.randomTouchCount}'),
                        if (session.promptDependencyScore != null)
                          (
                            'Prompt dependency',
                            _percent(session.promptDependencyScore!),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _ReportSection(
                      title: 'Improvement and consistency',
                      icon: Icons.trending_up_rounded,
                      palette: palette,
                      metrics: [
                        ('Improvement', _percent(session.improvementScore)),
                        ('Consistency', _percent(session.consistencyScore)),
                        if (session.turnTakingSuccessRate != null)
                          (
                            'Turn-taking success',
                            _percent(session.turnTakingSuccessRate!),
                          ),
                        if (session.interruptionCount != null)
                          ('Interruptions', '${session.interruptionCount}'),
                        if (session.waitingToleranceSeconds != null)
                          (
                            'Waiting tolerance',
                            _seconds(session.waitingToleranceSeconds!),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _ReportSection(
                      title: 'Session context',
                      icon: Icons.tune_rounded,
                      palette: palette,
                      metrics: [
                        if (session.sensoryCondition != null)
                          ('Sensory condition', session.sensoryCondition!),
                        (
                          'Background music',
                          session.bgMusicEnabled ? 'On' : 'Off',
                        ),
                        (
                          'Haptic feedback',
                          session.hapticFeedbackEnabled ? 'On' : 'Off',
                        ),
                      ],
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

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: AppTextStyles.titleLarge.copyWith(color: color)),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _ReportSection extends StatelessWidget {
  const _ReportSection({
    required this.title,
    required this.icon,
    required this.palette,
    required this.metrics,
  });

  final String title;
  final IconData icon;
  final GamePalette palette;
  final List<(String, String)> metrics;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: palette.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final (label, value) in metrics)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      value,
                      textAlign: TextAlign.end,
                      style: AppTextStyles.labelLarge.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
