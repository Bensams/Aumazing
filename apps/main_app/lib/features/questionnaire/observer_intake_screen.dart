import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:questionnaire_core/questionnaire_core.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/local_db_service.dart';
import 'observed_session.dart';
import 'parent_questionnaire_comparison_card.dart' show QuestionnaireLoader;
import 'parent_questionnaire_screen.dart' show QuestionnaireSaver;
import 'questionnaire_template_repository.dart';
import 'widgets/observation_choice_row.dart';
import 'widgets/template_question_field.dart';

/// "Before your child starts" (AUM-351): shown to the adult once a new
/// assessment run exists and before the first game, so nothing is asked
/// while the child plays.
///
/// Records who is watching, then the practitioner-authored intake questions
/// (AUM-352) — background about the child, pre-filled from the last time.
/// **Skip** starts the games without saving anything.
class ObserverIntakeScreen extends StatefulWidget {
  const ObserverIntakeScreen({
    super.key,
    required this.assessmentType,
    required this.childId,
    required this.assessmentRunId,
    this.saver,
    this.loader,
    this.template,
  });

  /// `pre` or `post`.
  final String assessmentType;
  final String childId;
  final String? assessmentRunId;

  final QuestionnaireSaver? saver;
  final QuestionnaireLoader? loader;

  /// The questions to ask; the active template, or the bundled default,
  /// when null.
  final ChoiceTemplate? template;

  /// Shows the screen and completes with what was saved, or null when the
  /// adult skipped it.
  static Future<IntakeRecord?> show(
    BuildContext context, {
    required String assessmentType,
    required String childId,
    required String? assessmentRunId,
  }) async {
    final template = await QuestionnaireTemplateRepository.instance
        .choiceTemplateFor(TemplateKind.intake, assessmentType);
    if (!context.mounted) return null;
    return Navigator.of(context).push<IntakeRecord>(
      MaterialPageRoute(
        builder:
            (_) => ObserverIntakeScreen(
              assessmentType: assessmentType,
              childId: childId,
              assessmentRunId: assessmentRunId,
              template: template,
            ),
      ),
    );
  }

  @override
  State<ObserverIntakeScreen> createState() => _ObserverIntakeScreenState();
}

class _ObserverIntakeScreenState extends State<ObserverIntakeScreen> {
  ObserverRole? _role;
  final Map<String, Object?> _answers = {};
  bool _saving = false;

  /// Bumped when last time's answers arrive, so the fields rebuild with them.
  int _prefillGeneration = 0;

  ChoiceTemplate get _template => widget.template ?? kDefaultIntakeTemplate;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  /// The latest intake for this child, so background is answered once and
  /// only corrected afterwards. Answers the current questions no longer
  /// offer are dropped.
  Future<void> _prefill() async {
    try {
      final rows = await (widget.loader ??
          localDbService.getCaregiverQuestionnaires)(widget.childId);
      final intakes =
          rows
              .where(
                (r) => '${r['questionnaire_type']}'.endsWith('_intake'),
              )
              .toList()
            ..sort(
              (a, b) =>
                  '${b['completed_at']}'.compareTo('${a['completed_at']}'),
            );
      for (final row in intakes) {
        final decoded = jsonDecode(row['responses'] as String? ?? '{}');
        if (decoded is! Map<String, dynamic>) continue;
        final last = IntakeRecord.fromResponses(decoded);
        if (last == null) continue;
        if (!mounted) return;
        setState(() {
          _role ??= last.role;
          for (final q in _template.questions) {
            final value = last.answers[q.id];
            if (!_answers.containsKey(q.id) && q.isAnswered(value)) {
              _answers[q.id] = value;
            }
          }
          _prefillGeneration++;
        });
        return;
      }
    } catch (e) {
      debugPrint('[ObserverIntake] prefill failed: $e');
    }
  }

  bool get _canStart =>
      _role != null &&
      !_saving &&
      _template.isComplete(_answers, QuestionScope.session);

  Future<void> _start() async {
    final role = _role;
    if (role == null || !_canStart) return;
    setState(() => _saving = true);
    final record = IntakeRecord.answer(_template, role, {
      for (final entry in _answers.entries)
        if (entry.value != null) entry.key: entry.value,
    });
    try {
      await (widget.saver ?? _defaultSaver)(
        id: const Uuid().v4(),
        childId: widget.childId,
        assessmentRunId: widget.assessmentRunId,
        questionnaireType: intakeTypeFor(widget.assessmentType),
        responses: record.toResponses(_template),
      );
    } catch (e) {
      // The games matter more than this record: start them anyway.
      debugPrint('[ObserverIntake] save failed: $e');
    }
    if (mounted) Navigator.of(context).pop(record);
  }

  static Future<void> _defaultSaver({
    required String id,
    required String childId,
    required String? assessmentRunId,
    required String questionnaireType,
    required Map<String, dynamic> responses,
  }) => localDbService.insertCaregiverQuestionnaire(
    id: id,
    childId: childId,
    assessmentRunId: assessmentRunId,
    questionnaireType: questionnaireType,
    responses: responses,
  );

  @override
  Widget build(BuildContext context) {
    final template = _template;
    return PopScope(
      // Leaving goes through Skip or Start, so the games always follow.
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.lavenderLight,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(template.title),
          actions: [
            TextButton(
              key: const Key('intake.skip'),
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Skip'),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: [
                    if (template.intro.isNotEmpty)
                      AppCard(
                        key: const Key('intake.instructions'),
                        padding: AppSpacing.paddingMd,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('👀', style: TextStyle(fontSize: 28)),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Text(
                                template.intro,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    ObservationChoiceRow<ObserverRole>(
                      keyPrefix: 'intake.role',
                      question: 'Who is watching?',
                      values: ObserverRole.values,
                      label: (v) => v.label,
                      id: (v) => v.key,
                      selected: _role,
                      onSelected: (v) => setState(() => _role = v),
                    ),
                    if (template.questions.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'About your child',
                        style: AppTextStyles.titleMedium.copyWith(
                          color: AppColors.primaryPurple,
                        ),
                      ),
                      Text(
                        'Saved with this assessment to help read the '
                        'results. It does not change any score.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.mutedForeground,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      for (final q in template.questions)
                        TemplateQuestionField(
                          key: ValueKey('intake.${q.id}.$_prefillGeneration'),
                          keyPrefix: 'intake',
                          question: q,
                          value: _answers[q.id],
                          onChanged: (v) => setState(() => _answers[q.id] = v),
                        ),
                    ],
                  ],
                ),
              ),
              Container(
                color: AppColors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _role == null
                            ? 'Choose who is watching to start.'
                            : 'Hand the device to your child when the '
                                'games begin.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    FilledButton(
                      key: const Key('intake.start'),
                      onPressed: _canStart ? _start : null,
                      child: const Text('Start the games'),
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
