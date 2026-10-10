import 'package:flutter/material.dart';

import '../../core/services/local_db_service.dart';
import 'parent_questionnaire_comparison_card.dart' show QuestionnaireLoader;
import 'parent_questionnaire_screen.dart';
import 'questionnaire_template_repository.dart';

/// Home reports belong at the initial assessment and at the post-assessment
/// after a learning path, including later assessment cycles. Ordinary game
/// sessions never call this flow. Home answers are always new parent reports.
class HomeQuestionnaireFlow {
  static bool shouldCollect({
    required String assessmentType,
    required String? assessmentRunId,
    required List<Map<String, dynamic>> rows,
  }) =>
      (assessmentType == 'pre' || assessmentType == 'post') &&
      assessmentRunId != null &&
      !rows.any(
        (row) =>
            row['assessment_run_id'] == assessmentRunId &&
            (row['questionnaire_type'] == 'pre' ||
                row['questionnaire_type'] == 'post'),
      );

  static Future<void> show(
    BuildContext context, {
    required String assessmentType,
    required String childId,
    required String? assessmentRunId,
    required void Function(BuildContext) onDone,
    QuestionnaireTemplateRepository? repository,
    QuestionnaireLoader? loader,
    QuestionnaireSaver? saver,
  }) async {
    List<Map<String, dynamic>> rows = [];
    try {
      rows = await (loader ?? localDbService.getCaregiverQuestionnaires)(
        childId,
      );
    } catch (_) {
      // Missing local context must not prevent results or a new report.
    }
    if (!context.mounted) return;
    if (!shouldCollect(
      assessmentType: assessmentType,
      assessmentRunId: assessmentRunId,
      rows: rows,
    )) {
      onDone(context);
      return;
    }
    final template = await (repository ??
            QuestionnaireTemplateRepository.instance)
        .templateFor(assessmentType);
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder:
            (_) => ParentQuestionnaireScreen(
              template: template,
              assessmentType: assessmentType,
              childId: childId,
              assessmentRunId: assessmentRunId,
              onDone: onDone,
              saver: saver,
            ),
      ),
    );
  }
}
