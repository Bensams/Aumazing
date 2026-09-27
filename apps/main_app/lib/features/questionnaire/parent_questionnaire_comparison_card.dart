import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/services/local_db_service.dart';
import 'parent_questionnaire.dart';

/// Loads every stored questionnaire row for a child. Injectable for tests.
typedef QuestionnaireLoader =
    Future<List<Map<String, dynamic>>> Function(String childId);

/// "What you noticed at home" — the parent's own before/after answers, shown
/// on the post-assessment results next to the change the games measured.
///
/// Uses the most recent pre and post questionnaire for the child. Shows
/// nothing unless both exist: half a comparison is not a comparison, and a
/// parent who skipped either questionnaire should not see an empty card.
class ParentQuestionnaireComparisonCard extends StatefulWidget {
  const ParentQuestionnaireComparisonCard({
    super.key,
    required this.childId,
    this.loader,
  });

  final String childId;
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
      final pre = _latestScores(rows, 'pre');
      final post = _latestScores(rows, 'post');
      if (!mounted) return;
      setState(() {
        _pre = pre;
        _post = post;
      });
    } catch (e) {
      debugPrint('[QuestionnaireComparison] load failed: $e');
    }
  }

  /// Domain scores of the newest row of [type], or null when there is none.
  static Map<String, double?>? _latestScores(
    List<Map<String, dynamic>> rows,
    String type,
  ) {
    final ofType =
        rows.where((r) => r['questionnaire_type'] == type).toList()..sort(
          (a, b) => '${b['completed_at']}'.compareTo('${a['completed_at']}'),
        );
    for (final row in ofType) {
      try {
        final decoded = jsonDecode(row['responses'] as String? ?? '{}');
        final scores = decoded is Map ? decoded['domain_scores'] : null;
        if (scores is Map) {
          return {
            for (final d in QuestionnaireDomain.values)
              d.key: (scores[d.key] as num?)?.toDouble(),
          };
        }
      } catch (_) {
        // A malformed row is skipped; an older valid one may still serve.
      }
    }
    return null;
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
