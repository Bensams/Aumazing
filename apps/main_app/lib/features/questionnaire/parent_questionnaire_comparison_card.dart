import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/services/local_db_service.dart';
import 'parent_questionnaire.dart';
import 'home_observation_context.dart';

/// Loads every stored questionnaire row for a child. Injectable for tests.
typedef QuestionnaireLoader =
    Future<List<Map<String, dynamic>>> Function(String childId);

/// "What you noticed at home" — the parent's own before/after answers, shown
/// on the post-assessment results next to the change the games measured.
///
/// Compares compatible questions within the post run's assessment cycle.
/// A skipped questionnaire never borrows an answer from an older cycle.
class ParentQuestionnaireComparisonCard extends StatefulWidget {
  const ParentQuestionnaireComparisonCard({
    super.key,
    required this.childId,
    this.assessmentRunId,
    this.loader,
  });

  final String childId;
  final String? assessmentRunId;
  final QuestionnaireLoader? loader;

  @override
  State<ParentQuestionnaireComparisonCard> createState() =>
      _ParentQuestionnaireComparisonCardState();
}

class _ParentQuestionnaireComparisonCardState
    extends State<ParentQuestionnaireComparisonCard> {
  Map<String, double?>? _pre;
  Map<String, double?>? _post;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await (widget.loader ??
          localDbService.getCaregiverQuestionnaires)(widget.childId);
      List<HomeObservation> reports;
      if (widget.assessmentRunId != null) {
        final runs = await localDbService.getAssessmentRuns(
          childId: widget.childId,
        );
        reports =
            HomeObservationContext.fromRows(
              rows: rows,
              runs: [
                for (final r in runs)
                  if (r.isCompleted)
                    (
                      id: r.id,
                      type: r.type,
                      completedAt: r.completedAt ?? r.startedAt,
                    ),
              ],
              childId: widget.childId,
              currentRunId: widget.assessmentRunId,
            ).observations;
      } else {
        reports = [
          for (final r in rows)
            if (HomeObservation.fromRow(r) case final HomeObservation report)
              report,
        ]..sort((a, b) => a.completedAt.compareTo(b.completedAt));
      }
      final before = reports.where((r) => r.type == 'pre').lastOrNull;
      final after = reports.where((r) => r.type == 'post').lastOrNull;
      final compatible =
          before != null &&
          after != null &&
          before.completedAt.isBefore(after.completedAt) &&
          after.comparableTo(before);
      if (!mounted) return;
      setState(() {
        _pre = compatible ? before.scores : null;
        _post = compatible ? after.scores : null;
      });
    } catch (e) {
      debugPrint('[QuestionnaireComparison] load failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pre = _pre;
    final post = _post;
    if (pre == null || post == null) return const SizedBox.shrink();

    return AppCard(
      key: const Key('questionnaireComparison'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What you noticed at home',
            style: AppTextStyles.titleMedium.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your questionnaire answers before and after, per area '
            '(0–100, higher means you saw it more often).',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.mutedForeground,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final domain in QuestionnaireDomain.values)
            _Row(
              key: Key('questionnaireComparison.${domain.key}'),
              label: domain.label,
              before: pre[domain.key],
              after: post[domain.key],
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.label,
    required this.before,
    required this.after,
  });

  final String label;
  final double? before;
  final double? after;

  @override
  Widget build(BuildContext context) {
    String fmt(double? v) => v == null ? '—' : v.round().toString();
    final b = before;
    final a = after;
    final delta = (b == null || a == null) ? null : a - b;
    final (IconData icon, Color color) = switch (delta) {
      null => (Icons.remove_rounded, AppColors.mutedForeground),
      > 0 => (Icons.trending_up_rounded, AppColors.statusSuccessDark),
      < 0 => (Icons.trending_down_rounded, AppColors.mutedForeground),
      _ => (Icons.trending_flat_rounded, AppColors.mutedForeground),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            '${fmt(b)} → ${fmt(a)}',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 6),
          Icon(icon, size: 18, color: color),
        ],
      ),
    );
  }
}
