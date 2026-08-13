import 'package:flutter/material.dart';

import '../assessment_result_data.dart';
import 'assessment_section_card.dart';

/// Per-game results: adjusted accuracy as a percentage, with the raw
/// correct/error counts as a caption underneath.
class AssessmentGameResultsCard extends StatelessWidget {
  const AssessmentGameResultsCard({
    super.key,
    required this.games,
    this.dense = false,
  });

  final List<ResultGameScore> games;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return AssessmentSectionCard(
      label: AssessmentLabels.gameResults,
      emoji: '🎮',
      dense: dense,
      children: assessmentWithDividers([
        for (final game in games)
          AssessmentMeterRow(
            label: '${game.emoji} ${game.name}',
            secondaryLabel: '${game.correctCount} ${AssessmentLabels.correct} · '
                '${game.errorCount} ${AssessmentLabels.errors} · '
                '${game.totalItems} ${AssessmentLabels.totalItems}',
            value: game.accuracy,
            color: AssessmentPalette.performance(
              AssessmentScoring.percent(game.accuracy),
            ),
            semanticsLabel: '${game.name}, '
                '${AssessmentScoring.percent(game.accuracy)} percent, '
                '${game.correctCount} correct, ${game.errorCount} errors, '
                '${game.totalItems} total items',
          ),
      ]),
    );
  }
}
