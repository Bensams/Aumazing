import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/services/local_db_service.dart';
import '../../model/assessment_result.dart';
import '../../services/assessment_result_mapper.dart';
import 'observed_session.dart';
import 'parent_questionnaire_comparison_card.dart' show QuestionnaireLoader;

/// "What the observer saw" (AUM-351): the adult's answers for one assessment
/// run, beside each game's score.
///
/// Flags — played with help, did not understand, upset, worse than usual, not
/// a typical day — tell the reader how to take a score. The scores
/// themselves are never changed. Shows nothing when the adult skipped both
/// the before and after questions.
class SessionObservationCard extends StatefulWidget {
  const SessionObservationCard({
    super.key,
    required this.childId,
    required this.assessmentRunId,
    required this.results,
    this.loader,
  });

  final String childId;
  final String assessmentRunId;

  /// This run's game results, for the score beside each game.
  final List<AssessmentResult> results;

  final QuestionnaireLoader? loader;

  @override
  State<SessionObservationCard> createState() => _SessionObservationCardState();
}

class _SessionObservationCardState extends State<SessionObservationCard> {
  ObserverIntake? _intake;
  SessionObservation? _observation;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await (widget.loader ??
          localDbService.getCaregiverQuestionnaires)(widget.childId);
      ObserverIntake? intake;
      SessionObservation? observation;
      for (final row in rows) {
        if (row['assessment_run_id'] != widget.assessmentRunId) continue;
        final type = '${row['questionnaire_type']}';
        final decoded = jsonDecode(row['responses'] as String? ?? '{}');
        if (decoded is! Map<String, dynamic>) continue;
        if (type.endsWith('_intake')) {
          intake ??= ObserverIntake.fromResponses(decoded);
        } else if (type.endsWith('_observation')) {
          observation ??= SessionObservation.fromResponses(decoded);
        }
      }
      if (!mounted) return;
      setState(() {
        _intake = intake;
        _observation = observation;
      });
    } catch (e) {
      debugPrint('[SessionObservationCard] load failed: $e');
    }
  }

  AssessmentResult? _resultFor(String gameId) {
    for (final r in widget.results) {
      if (r.gameId == gameId) return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final intake = _intake;
    final observation = _observation;
    if (intake == null && observation == null) return const SizedBox.shrink();
    final role = observation?.role ?? intake?.role;
    final dayFlag = observation?.dayFlag;
    return AppCard(
      key: const Key('session-observation-card'),
      padding: AppSpacing.paddingMd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('👀', style: TextStyle(fontSize: 22)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  role == null
                      ? 'What the observer saw'
                      : 'What the ${role.inSentence} saw',
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (intake != null) ...[
            const SizedBox(height: 4),
            Text(
              intake.summary,
              key: const Key('session-observation-background'),
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (dayFlag != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _Flag(dayFlag),
          ],
          if (observation == null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'The after-play questions were skipped.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.mutedForeground,
              ),
            ),
          ] else
            for (final entry in observation.games.entries)
              _GameRow(
                gameId: entry.key,
                seen: entry.value,
                result: _resultFor(entry.key),
              ),
          if (observation != null && observation.note.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '“${observation.note}”',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textPrimary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GameRow extends StatelessWidget {
  const _GameRow({
    required this.gameId,
    required this.seen,
    required this.result,
  });

  final String gameId;
  final GameObservation seen;
  final AssessmentResult? result;

  @override
  Widget build(BuildContext context) {
    final result = this.result;
    final details = [
      if (seen.understood != null) 'Understood: ${seen.understood!.label}',
      if (seen.help != null) seen.help!.label,
      if (seen.mood != null) seen.mood!.label,
      if (seen.asUsual != null) seen.asUsual!.label,
    ].join(' · ');
    return Padding(
      key: Key('session-observation-game-$gameId'),
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(AssessmentResultMapper.gameEmoji(gameId)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  AssessmentResultMapper.gameName(gameId),
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (result != null && result.totalItems > 0)
                Text(
                  'Score ${result.score}/${result.totalItems}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
          if (details.isNotEmpty)
            Text(
              details,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          for (final flag in seen.flags) _Flag(flag),
        ],
      ),
    );
  }
}

class _Flag extends StatelessWidget {
  const _Flag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.flag_rounded,
            size: 16,
            color: AppColors.statusWarningDark,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.statusWarningDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
