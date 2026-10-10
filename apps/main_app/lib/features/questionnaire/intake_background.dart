import 'dart:convert';

import 'package:questionnaire_core/questionnaire_core.dart';

/// Background that can safely be carried forward from one earlier intake.
/// Current-session values and the previous observer's identity are excluded.
class IntakeBackground {
  const IntakeBackground({
    required this.rowId,
    required this.completedAt,
    required this.answers,
    required this.sources,
  });

  final String? rowId;
  final String? completedAt;
  final Map<String, Object?> answers;
  final Map<String, Object?> sources;

  static IntakeBackground? latest(
    List<Map<String, dynamic>> rows,
    ChoiceTemplate template,
  ) {
    final ordered = [
      ...rows,
    ]..sort((a, b) => '${b['completed_at']}'.compareTo('${a['completed_at']}'));
    for (final row in ordered) {
      if (!'${row['questionnaire_type']}'.endsWith('_intake')) continue;
      try {
        final raw = row['responses'];
        final data = raw is String ? jsonDecode(raw) : raw;
        if (data is! Map || data['template_id'] != template.key) continue;
        final oldAnswers = data['answers'];
        if (oldAnswers is! Map) continue;
        final signatures = data['question_signatures'];
        final origins = data['answer_sources'];
        final answers = <String, Object?>{};
        final sources = <String, Object?>{};
        for (final q in template.questions) {
          if (q.timing != AnswerTiming.background) continue;
          // Older records have only a template stamp: require its exact version.
          final compatible =
              signatures is Map
                  ? signatures[q.id] == q.answerSignature
                  : data['template_version'] == template.version;
          final value = oldAnswers[q.id];
          if (!compatible || !q.isAnswered(value)) continue;
          answers[q.id] = value;
          sources[q.id] =
              origins is Map && origins[q.id] is Map
                  ? origins[q.id]
                  : {
                    'questionnaire_id': row['id'],
                    'completed_at': row['completed_at'],
                    'template_id': data['template_id'],
                    'template_version': data['template_version'],
                  'template_status': data['template_status'],
                  'observer_role': data['observer_role'],
                  };
        }
        return IntakeBackground(
          rowId: row['id'] as String?,
          completedAt: row['completed_at'] as String?,
          answers: answers,
          sources: sources,
        );
      } catch (_) {
        // An unreadable historical row must not block the next assessment.
      }
    }
    return null;
  }
}
