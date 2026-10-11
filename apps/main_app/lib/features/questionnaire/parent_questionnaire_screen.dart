import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/local_db_service.dart';
import 'parent_questionnaire.dart';

/// Stores one answered questionnaire. Injectable so a widget test can capture
/// the record without a database.
typedef QuestionnaireSaver =
    Future<void> Function({
      required String id,
      required String childId,
      required String? assessmentRunId,
      required String questionnaireType,
      required Map<String, dynamic> responses,
    });

/// The parent questionnaire about home life. It is asked twice per child
/// (AUM-364): once when the profile is set up ([atSetup], the "before"), and
/// after a post-assessment, once the parent has taken the device back and
/// before any result is on screen, so what the parent reports is not coloured
/// by what the games found.
///
/// Optional: **Skip for now** (just **Skip** at setup) continues without
/// saving anything. Answers are saved to the local database and sync like
/// every other record.
class ParentQuestionnaireScreen extends StatefulWidget {
  const ParentQuestionnaireScreen({
    super.key,
    required this.assessmentType,
    required this.childId,
    required this.assessmentRunId,
    required this.onDone,
    this.template = kParentQuestionnaireDraft,
    this.saver,
    this.atSetup = false,
  });

  /// `pre` or `post`; stored as the questionnaire type.
  final String assessmentType;
  final String childId;
  final String? assessmentRunId;

  /// Called once, after saving or skipping, to carry on to the results.
  final void Function(BuildContext context) onDone;

  final QuestionnaireTemplate template;
  final QuestionnaireSaver? saver;

  /// Asked right after the child's profile is set up, with no assessment yet.
  final bool atSetup;

  @override
  State<ParentQuestionnaireScreen> createState() =>
      _ParentQuestionnaireScreenState();
}

class _ParentQuestionnaireScreenState extends State<ParentQuestionnaireScreen> {
  final Map<String, Frequency> _answers = {};
  bool _saving = false;
  bool _done = false;

  QuestionnaireTemplate get _template => widget.template;
  bool get _complete => _answers.length == _template.items.length;

  Future<void> _save() async {
    if (!_complete || _saving || _done) return;
    setState(() => _saving = true);
    final scores = scoreQuestionnaire(_template, _answers);
    final responses = <String, dynamic>{
      'template_id': _template.id,
      'template_version': _template.version,
      // Carried with every answer so draft-template answers can always be
      // told apart from a validated instrument's.
      'template_status': _template.status,
      'schema_signature': questionnaireSchemaSignature(_template),
      'answers': {
        for (final entry in _answers.entries) entry.key: entry.value.value,
      },
      'domain_scores': {
        for (final entry in scores.entries) entry.key.key: entry.value,
      },
      'scale_max': Frequency.maxValue,
    };
    try {
      await (widget.saver ?? _defaultSaver)(
        id: const Uuid().v4(),
        childId: widget.childId,
        assessmentRunId: widget.assessmentRunId,
        questionnaireType: widget.assessmentType,
        responses: responses,
      );
    } catch (e) {
      debugPrint('[ParentQuestionnaire] save failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save your answers. Please try again.'),
        ),
      );
      return;
    }
    _finish();
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

  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    widget.onDone(context);
  }

  @override
  Widget build(BuildContext context) {
    final answered = _answers.length;
    final total = _template.items.length;
    return PopScope(
      // Leaving must go through Skip or Save so the flow always reaches the
      // results.
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.lavenderLight,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(_template.title),
          actions: [
            TextButton(
              key: const Key('questionnaire.skip'),
              onPressed: _saving ? null : _finish,
              // At setup it is asked only once, so it is not "for now".
              child: Text(widget.atSetup ? 'Skip' : 'Skip for now'),
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
                    Text(
                      widget.atSetup
                          ? 'Optional — tell us how your child does at home. '
                              'We ask once now, and again after a follow-up '
                              'assessment so you can compare. You can skip and '
                              'still use every game and summary. Answer about '
                              'the last two weeks.'
                          : 'Optional — your answers add home observations to '
                              'the summary, beside the ones you gave when you '
                              'set up your child’s profile. You can skip and '
                              'still see game results and summaries. Answer '
                              'about home life over the last two weeks, not '
                              'just today’s session.',
                      key: const Key('questionnaire.optionalNote'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _template.intro,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (_template.isDraft) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Draft questions — still being reviewed by special '
                        'education teachers.',
                        key: const Key('questionnaire.draftNote'),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.mutedForeground,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    for (final domain in QuestionnaireDomain.values) ...[
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        domain.label,
                        style: AppTextStyles.titleMedium.copyWith(
                          color: AppColors.primaryPurple,
                        ),
                      ),
                      for (final item in _template.itemsFor(domain))
                        _ItemCard(
                          key: Key('questionnaire.item.${item.id}'),
                          item: item,
                          answer: _answers[item.id],
                          onAnswer:
                              (f) => setState(() => _answers[item.id] = f),
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
                        '$answered of $total answered',
                        key: const Key('questionnaire.progress'),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    FilledButton(
                      key: const Key('questionnaire.save'),
                      onPressed: _complete && !_saving ? _save : null,
                      child: Text(_saving ? 'Saving…' : 'Save and continue'),
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

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    super.key,
    required this.item,
    required this.answer,
    required this.onAnswer,
  });

  final QuestionnaireItem item;
  final Frequency? answer;
  final ValueChanged<Frequency> onAnswer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: AppCard(
        padding: AppSpacing.paddingMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.text,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final f in Frequency.values)
                  ChoiceChip(
                    key: Key('questionnaire.answer.${item.id}.${f.name}'),
                    label: Text(f.label),
                    selected: answer == f,
                    selectedColor: AppColors.primaryPurple,
                    labelStyle: AppTextStyles.bodySmall.copyWith(
                      color:
                          answer == f ? AppColors.white : AppColors.textPrimary,
                    ),
                    onSelected: (_) => onAnswer(f),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
