import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/local_db_service.dart';
import '../../services/assessment_result_mapper.dart';
import 'observed_session.dart';
import 'parent_questionnaire_comparison_card.dart' show QuestionnaireLoader;
import 'parent_questionnaire_screen.dart' show QuestionnaireSaver;
import 'widgets/observation_choice_row.dart';

/// The assessment games, in play order.
const kAssessmentGameIds = [
  'copy_me',
  'do_what_i_say',
  'my_turn_your_turn',
  'match_it',
];

/// "What did you see?" (AUM-351): once the adult has taken the device back
/// after the last game, and before any result is on screen, they report
/// what they saw in each game the child just played.
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
    this.saver,
    this.loader,
  });

  /// `pre` or `post`.
  final String assessmentType;
  final String childId;
  final String? assessmentRunId;

  /// The games the child played, in order.
  final List<String> gameIds;

  /// Called once, after saving or skipping.
  final void Function(BuildContext context) onDone;

  final QuestionnaireSaver? saver;
  final QuestionnaireLoader? loader;

  @override
  State<SessionObservationScreen> createState() =>
      _SessionObservationScreenState();
}

class _SessionObservationScreenState extends State<SessionObservationScreen> {
  late final Map<String, GameObservation> _games = {
    for (final id in widget.gameIds) id: const GameObservation(),
  };
  final _note = TextEditingController();
  ObserverRole? _role;
  SessionDay? _day;
  bool _saving = false;
  bool _done = false;

  SessionObservation get _observation => SessionObservation(
    games: _games,
    role: _role,
    day: _day,
    note: _note.text,
  );

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
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
        final intake = ObserverIntake.fromResponses(decoded);
        if (intake != null && mounted) setState(() => _role = intake.role);
        return;
      }
    } catch (e) {
      debugPrint('[SessionObservation] intake read failed: $e');
    }
  }

  void _update(String gameId, GameObservation Function(GameObservation) f) =>
      setState(() => _games[gameId] = f(_games[gameId]!));

  Future<void> _save() async {
    if (!_observation.complete || _saving || _done) return;
    setState(() => _saving = true);
    try {
      await (widget.saver ?? _defaultSaver)(
        id: const Uuid().v4(),
        childId: widget.childId,
        assessmentRunId: widget.assessmentRunId,
        questionnaireType: observationTypeFor(widget.assessmentType),
        responses: _observation.toResponses(),
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
    final answered =
        _games.values.where((g) => g.complete).length + (_day == null ? 0 : 1);
    final total = _games.length + 1;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.lavenderLight,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('What did you see?'),
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
                    Text(
                      'Think back to the games your child just played. There '
                      'are no right answers — tell us what you saw. Your '
                      'answers appear beside each game\'s result and never '
                      'change a score.',
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
                      _GameCard(
                        key: Key('observation.game.$id'),
                        gameId: id,
                        value: _games[id]!,
                        onChanged: (f) => _update(id, f),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    AppCard(
                      padding: AppSpacing.paddingMd,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ObservationChoiceRow<SessionDay>(
                            keyPrefix: 'observation.day',
                            question: 'Was today a typical day for your child?',
                            values: SessionDay.values,
                            label: (v) => v.label,
                            id: (v) => v.key,
                            selected: _day,
                            onSelected: (v) => setState(() => _day = v),
                          ),
                          TextField(
                            key: const Key('observation.note'),
                            controller: _note,
                            maxLines: 3,
                            maxLength: 500,
                            decoration: const InputDecoration(
                              labelText: 'Anything else you noticed? (optional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
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
                      onPressed:
                          _observation.complete && !_saving ? _save : null,
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

class _GameCard extends StatelessWidget {
  const _GameCard({
    super.key,
    required this.gameId,
    required this.value,
    required this.onChanged,
  });

  final String gameId;
  final GameObservation value;
  final ValueChanged<GameObservation Function(GameObservation)> onChanged;

  @override
  Widget build(BuildContext context) {
    final prefix = 'observation.$gameId';
    return AppCard(
      padding: AppSpacing.paddingMd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                AssessmentResultMapper.gameEmoji(gameId),
                style: const TextStyle(fontSize: 24),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  AssessmentResultMapper.gameName(gameId),
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.primaryPurple,
                  ),
                ),
              ),
              if (value.complete)
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.statusSuccessDark,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ObservationChoiceRow<Understood>(
            keyPrefix: '$prefix.understood',
            question: 'Did your child understand what to do?',
            values: Understood.values,
            label: (v) => v.label,
            id: (v) => v.key,
            selected: value.understood,
            onSelected: (v) => onChanged((g) => g.copyWith(understood: v)),
          ),
          ObservationChoiceRow<HelpGiven>(
            keyPrefix: '$prefix.help',
            question: 'How much did you help?',
            values: HelpGiven.values,
            label: (v) => v.label,
            id: (v) => v.key,
            selected: value.help,
            onSelected: (v) => onChanged((g) => g.copyWith(help: v)),
          ),
          ObservationChoiceRow<ChildMood>(
            keyPrefix: '$prefix.mood',
            question: 'How did your child seem?',
            values: ChildMood.values,
            label: (v) => v.label,
            id: (v) => v.key,
            selected: value.mood,
            onSelected: (v) => onChanged((g) => g.copyWith(mood: v)),
          ),
          ObservationChoiceRow<AsUsual>(
            keyPrefix: '$prefix.usual',
            question: 'Compared with how your child usually does tasks like '
                'this:',
            values: AsUsual.values,
            label: (v) => v.label,
            id: (v) => v.key,
            selected: value.asUsual,
            onSelected: (v) => onChanged((g) => g.copyWith(asUsual: v)),
          ),
        ],
      ),
    );
  }
}
