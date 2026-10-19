import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:questionnaire_core/questionnaire_core.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/local_db_service.dart';
import 'observed_session.dart';
import 'intake_background.dart';
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
/// (AUM-352) — background about the child, with an explicit reuse or update choice.
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
  bool _loading = true;
  IntakeBackground? _previous;
  String? _backgroundMode;
  final Set<String> _edited = {};

  /// Bumped when last time's answers arrive, so the fields rebuild with them.
  int _prefillGeneration = 0;

  /// Set when Start is tapped too early, so what is missing is outlined.
  bool _showMissing = false;

  final _backgroundCard = GlobalKey();
  final _roleCard = GlobalKey();
  final Map<String, GlobalKey> _questionCards = {};

  /// Questions read comfortably up to this width on a tablet.
  static const double _maxContentWidth = 760;

  ChoiceTemplate get _template => widget.template ?? kDefaultIntakeTemplate;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    try {
      final rows = await (widget.loader ??
          localDbService.getCaregiverQuestionnaires)(widget.childId);
      if (!mounted) return;
      final previous = IntakeBackground.latest(rows, _template);
      setState(() {
        _previous = previous;
        _loading = false;
        if (previous == null || previous.answers.isEmpty) {
          _backgroundMode = 'initial';
        }
      });
    } catch (e) {
      debugPrint('[ObserverIntake] background read failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _backgroundMode = 'initial';
        });
      }
    }
  }

  void _chooseBackground(String mode) {
    setState(() {
      _backgroundMode = mode;
      for (final q in _template.questions) {
        if (q.timing == AnswerTiming.background) _answers.remove(q.id);
      }
      _answers.addAll(_previous?.answers ?? {});
      _edited.clear();
      _prefillGeneration++;
    });
  }

  bool _showQuestion(TemplateQuestion q) =>
      q.timing == AnswerTiming.currentSession ||
      (_backgroundMode != null &&
          (_backgroundMode != 'reuse' ||
              !(_previous?.answers.containsKey(q.id) ?? false)));

  bool get _canStart =>
      _role != null &&
      !_saving &&
      !_loading &&
      _backgroundMode != null &&
      _template.isComplete(_answers, QuestionScope.session);

  bool _isMissing(TemplateQuestion q) =>
      q.required && _showQuestion(q) && !q.isAnswered(_answers[q.id]);

  /// The first card still blocking Start, top to bottom.
  GlobalKey? get _firstMissing {
    if (_backgroundMode == null) return _backgroundCard;
    if (_role == null) return _roleCard;
    for (final q in _template.questions) {
      if (_isMissing(q)) return _questionCards[q.id];
    }
    return null;
  }

  /// Start is never greyed out: tapping it early scrolls to what is missing.
  void _onStartPressed() {
    final missing = _firstMissing;
    if (missing == null) {
      _start();
      return;
    }
    setState(() => _showMissing = true);
    final target = missing.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 300),
        alignment: 0.1,
      );
    }
  }

  String get _footerText {
    final role = _role;
    if (role == null) return 'Choose who is watching to start.';
    final shown = _template.questions.where(_showQuestion).toList();
    final answered = shown.where((q) => q.isAnswered(_answers[q.id])).length;
    final progress =
        shown.isEmpty ? '' : ' · $answered of ${shown.length} answered';
    return 'Watching: ${role.label}$progress\n'
        'Hand the device to your child when the games begin.';
  }

  Future<void> _start() async {
    final role = _role;
    if (role == null || !_canStart) return;
    setState(() => _saving = true);
    final answers = <String, Object?>{
      for (final q in _template.questions)
        if (q.isAnswered(_answers[q.id])) q.id: _answers[q.id],
    };
    final reused = <String>[
      for (final q in _template.questions)
        if (q.timing == AnswerTiming.background &&
            !_edited.contains(q.id) &&
            (_previous?.answers.containsKey(q.id) ?? false) &&
            answers.containsKey(q.id))
          q.id,
    ];
    final record = IntakeRecord(
      role: role,
      answers: answers,
      summary: _template.summary(answers, QuestionScope.session),
      backgroundMode: _backgroundMode,
      reusedQuestionIds: reused,
      answerSources: {for (final id in reused) id: _previous!.sources[id]},
    );
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
    final hasPrevious = _previous != null && _previous!.answers.isNotEmpty;
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
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
              ),
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Skip'),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: SafeArea(
                bottom: false,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final side = math.max(
                      AppSpacing.md,
                      (constraints.maxWidth - _maxContentWidth) / 2,
                    );
                    // One child holding every card, so they are all built
                    // up front and Start can scroll to a missing card that
                    // is still off screen.
                    return ListView(
                      padding: EdgeInsets.symmetric(
                        horizontal: side,
                        vertical: AppSpacing.md,
                      ),
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Optional — background helps explain your child’s needs. '
                              'You can skip and still play the games and see results and summaries. '
                              'It does not change scores.',
                              key: const Key('intake.optionalNote'),
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            if (_loading) const LinearProgressIndicator(),
                            if (template.intro.isNotEmpty)
                              AppCard(
                                key: const Key('intake.instructions'),
                                padding: AppSpacing.paddingMd,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '👀',
                                      style: TextStyle(fontSize: 28),
                                    ),
                                    const SizedBox(width: AppSpacing.md),
                                    Expanded(
                                      child: Text(
                                        template.intro,
                                        style: AppTextStyles.bodyMedium
                                            .copyWith(
                                              color: AppColors.textPrimary,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: AppSpacing.lg),
                            if (hasPrevious)
                              _QuestionCard(
                                key: _backgroundCard,
                                missing:
                                    _showMissing && _backgroundMode == null,
                                child: Column(
                                  key: const Key('intake.previousNote'),
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ObservationChoiceRow<String>(
                                      keyPrefix: 'intake',
                                      question:
                                          'Background is available from an '
                                          'earlier questionnaire.',
                                      hint:
                                          'Reusing it keeps the original dates '
                                          'and labels it as earlier information.',
                                      values: const ['reuse', 'update'],
                                      label:
                                          (v) =>
                                              v == 'reuse'
                                                  ? 'Use previous answers'
                                                  : 'Update answers',
                                      id: (v) => v,
                                      selected: _backgroundMode,
                                      onSelected: (v) {
                                        if (!_saving) _chooseBackground(v);
                                      },
                                    ),
                                    if (_backgroundMode == 'reuse')
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: AppSpacing.xs,
                                        ),
                                        child: Text(
                                          'Previous background selected. Answer '
                                          'only what is new or needed today.',
                                          style: AppTextStyles.bodySmall
                                              .copyWith(
                                                color: AppColors.textSecondary,
                                              ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            _QuestionCard(
                              key: _roleCard,
                              missing: _showMissing && _role == null,
                              child: ObservationChoiceRow<ObserverRole>(
                                keyPrefix: 'intake.role',
                                question: 'Who is watching?',
                                hint: 'Choose one · needed to start',
                                values: ObserverRole.values,
                                label: (v) => v.label,
                                id: (v) => v.key,
                                selected: _role,
                                onSelected: (v) => setState(() => _role = v),
                              ),
                            ),
                            if (template.questions.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                'About your child',
                                style: AppTextStyles.titleMedium.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                'Saved with this assessment to help read the '
                                'results. It does not change any score.',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              for (final q in template.questions.where(
                                _showQuestion,
                              ))
                                _QuestionCard(
                                  key: _questionCards.putIfAbsent(
                                    q.id,
                                    GlobalKey.new,
                                  ),
                                  missing: _showMissing && _isMissing(q),
                                  child: TemplateQuestionField(
                                    key: ValueKey(
                                      'intake.${q.id}.$_prefillGeneration',
                                    ),
                                    keyPrefix: 'intake',
                                    question: q,
                                    value: _answers[q.id],
                                    onChanged:
                                        (v) => setState(() {
                                          _answers[q.id] = v;
                                          _edited.add(q.id);
                                        }),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            // Full width, so the white bar is not cut short by the side
            // safe-area inset in landscape.
            Container(
              color: AppColors.white,
              child: SafeArea(
                top: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _maxContentWidth,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _footerText,
                              key: const Key('intake.footer'),
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          FilledButton(
                            key: const Key('intake.start'),
                            onPressed:
                                _saving || _loading ? null : _onStartPressed,
                            child: const Text('Start the games'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One question on its own white card, outlined when Start was tapped
/// before it was answered.
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({super.key, required this.child, this.missing = false});

  final Widget child;
  final bool missing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: AppRadius.card,
          boxShadow: AppShadows.card,
          border: Border.all(
            color: missing ? AppColors.destructiveRed : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            child,
            if (missing)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  'Answer this to start the games.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.destructiveRed,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
