import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:questionnaire_core/questionnaire_core.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/local_db_service.dart';
import '../../services/assessment_result_mapper.dart';
import 'observed_session.dart';
import 'parent_questionnaire_comparison_card.dart' show QuestionnaireLoader;
import 'parent_questionnaire_screen.dart' show QuestionnaireSaver;
import 'widgets/template_question_field.dart';

/// The assessment games, in play order.
const kAssessmentGameIds = [
  'copy_me',
  'do_what_i_say',
  'my_turn_your_turn',
  'match_it',
];

/// "What did you see?" (AUM-351): once the adult has taken the device back
/// after the last game, and before any result is on screen, they answer the
/// practitioner-authored observation questions (AUM-352) — the per-game ones
/// for each game the child played, then the session ones.
///
/// Optional: **Skip for now** continues without saving anything.
class SessionObservationScreen extends StatefulWidget {
  const SessionObservationScreen({
    super.key,
    required this.assessmentType,
    required this.childId,
    required this.assessmentRunId,
    required this.onDone,
    this.gameIds = kAssessmentGameIds,
    this.template = kDefaultObservationTemplate,
    this.saver,
    this.loader,
  });

  /// `pre` or `post`.
  final String assessmentType;
  final String childId;
  final String? assessmentRunId;

  /// The games the child played, in order.
  final List<String> gameIds;

  final ChoiceTemplate template;

  /// Called once, after saving or skipping.
  final void Function(BuildContext context) onDone;

  final QuestionnaireSaver? saver;
  final QuestionnaireLoader? loader;

  @override
  State<SessionObservationScreen> createState() =>
      _SessionObservationScreenState();
}

class _SessionObservationScreenState extends State<SessionObservationScreen> {
  late final Map<String, Map<String, Object?>> _games = {
    for (final id in widget.gameIds) id: <String, Object?>{},
  };
  final Map<String, Object?> _session = {};
  ObserverRole? _role;
  bool _saving = false;
  bool _done = false;

  ChoiceTemplate get _template => widget.template;

  bool _gameComplete(String id) =>
      _template.isComplete(_games[id]!, QuestionScope.game);

  bool get _sessionComplete =>
      _template.isComplete(_session, QuestionScope.session);

  bool get _complete => widget.gameIds.every(_gameComplete) && _sessionComplete;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  /// Who said they were watching, from this run's intake.
  Future<void> _loadRole() async {
    try {
      final rows = await (widget.loader ??
          localDbService.getCaregiverQuestionnaires)(widget.childId);
      for (final row in rows) {
        if (row['questionnaire_type'] !=
                intakeTypeFor(widget.assessmentType) ||
            row['assessment_run_id'] != widget.assessmentRunId) {
          continue;
        }
        final decoded = jsonDecode(row['responses'] as String? ?? '{}');
        if (decoded is! Map<String, dynamic>) continue;
        final intake = IntakeRecord.fromResponses(decoded);
        if (intake != null && mounted) setState(() => _role = intake.role);
        return;
      }
    } catch (e) {
      debugPrint('[SessionObservation] intake read failed: $e');
    }
  }

  Map<String, Object?> _clean(Map<String, Object?> answers) => {
    for (final entry in answers.entries)
      if (entry.value != null) entry.key: entry.value,
  };

  Future<void> _save() async {
    if (!_complete || _saving || _done) return;
    setState(() => _saving = true);
    final record = ObservationRecord.answer(
      _template,
      role: _role,
      games: {
        for (final entry in _games.entries) entry.key: _clean(entry.value),
      },
      session: _clean(_session),
    );
    try {
      await (widget.saver ?? _defaultSaver)(
        id: const Uuid().v4(),
        childId: widget.childId,
        assessmentRunId: widget.assessmentRunId,
        questionnaireType: observationTypeFor(widget.assessmentType),
        responses: record.toResponses(_template),
      );
    } catch (e) {
      debugPrint('[SessionObservation] save failed: $e');
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
    final template = _template;
    final sessionQuestions = template.questionsFor(QuestionScope.session);
    final answered =
        widget.gameIds.where(_gameComplete).length +
        (sessionQuestions.isNotEmpty && _sessionComplete ? 1 : 0);
    final total = widget.gameIds.length + (sessionQuestions.isEmpty ? 0 : 1);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.lavenderLight,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(template.title),
          actions: [
            TextButton(
              key: const Key('observation.skip'),
              onPressed: _saving ? null : _finish,
              child: const Text('Skip for now'),
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
                      Text(
                        template.intro,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    if (_role != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Answering as: ${_role!.label}',
                        key: const Key('observation.role'),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.mutedForeground,
                        ),
                      ),
                    ],
                    for (final id in widget.gameIds) ...[
                      const SizedBox(height: AppSpacing.md),
                      AppCard(
                        key: Key('observation.game.$id'),
                        padding: AppSpacing.paddingMd,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  AssessmentResultMapper.gameEmoji(id),
                                  style: const TextStyle(fontSize: 24),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    AssessmentResultMapper.gameName(id),
                                    style: AppTextStyles.titleMedium.copyWith(
                                      color: AppColors.primaryPurple,
                                    ),
                                  ),
                                ),
                                if (_gameComplete(id))
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: AppColors.statusSuccessDark,
                                  ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            for (final q in template.questionsFor(
                              QuestionScope.game,
                            ))
                              TemplateQuestionField(
                                keyPrefix: 'observation.$id',
                                question: q,
                                value: _games[id]![q.id],
                                onChanged:
                                    (v) => setState(() => _games[id]![q.id] = v),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (sessionQuestions.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      AppCard(
                        key: const Key('observation.session'),
                        padding: AppSpacing.paddingMd,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final q in sessionQuestions)
                              TemplateQuestionField(
                                keyPrefix: 'observation.session',
                                question: q,
                                value: _session[q.id],
                                onChanged:
                                    (v) => setState(() => _session[q.id] = v),
                              ),
                          ],
                        ),
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
                        key: const Key('observation.progress'),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    FilledButton(
                      key: const Key('observation.save'),
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
