import 'package:flutter/material.dart';
import 'package:questionnaire_core/questionnaire_core.dart';

import '../../widgets/assessment_handoff.dart';
import '../../widgets/milestone_victory_scene.dart';
import '../questionnaire/home_questionnaire_flow.dart';
import '../questionnaire/questionnaire_template_repository.dart';
import '../questionnaire/session_observation_screen.dart';
import 'post_assessment_result_screen.dart';

/// Screen shown to the child after all post-assessment games are complete.
///
/// The post-assessment used to drop straight from the last game into
/// [PostAssessmentResultScreen], which is parent-facing — so the child was
/// handed the comparison of their own before/after levels, and no verification
/// stood between them and it. This puts the same child hand-off the
/// pre-assessment has in front of it.
///
/// The finished run's numbers are carried through verbatim rather than
/// recomputed: they were produced by the run that just ended, and re-deriving
/// them here could only disagree with it.
class PostAssessmentHandoffScreen extends StatelessWidget {
  const PostAssessmentHandoffScreen({
    super.key,
    required this.improvement,
    this.nextModulePremiumRequired = false,
    this.voiceOverFactory,
    this.childId,
    this.assessmentRunId,
    this.showQuestionnaire = true,
    this.templateRepository,
    this.gameIds = kAssessmentGameIds,
  });

  /// Where the questionnaire's active template comes from. Injectable for
  /// tests; the app uses the shared repository.
  final QuestionnaireTemplateRepository? templateRepository;
  final List<String> gameIds;

  /// The child and the finished run, so the parent questionnaire is stored
  /// against them. The run id is captured before the run is closed.
  final String? childId;
  final String? assessmentRunId;

  /// Whether the adult's questions — what they saw (AUM-351), then the
  /// parent questionnaire — come between verification and the results. On
  /// in the app; tests about the hand-off itself turn it off.
  final bool showQuestionnaire;

  /// Output of AssessmentService.compareAssessments for the completed run.
  final Map<String, dynamic> improvement;

  /// Whether generating the next personalized module requires Premium.
  final bool nextModulePremiumRequired;

  /// Test seam, forwarded to [AssessmentHandoffScreen].
  final HandoffVoiceOverFactory? voiceOverFactory;

  @override
  Widget build(BuildContext context) {
    return AssessmentHandoffScreen(
      title: MilestoneKind.postAssessment.title,
      subtitle: MilestoneKind.postAssessment.subtitle,
      milestoneVoiceCue: MilestoneKind.postAssessment.voiceCue,
      voiceOverFactory: voiceOverFactory,
      onParentVerified: _afterVerification,
    );
  }

  /// The same questions as after the pre-assessment — what the adult saw,
  /// then the questionnaire — answered before the comparison is shown, so
  /// the adult's view of change is their own.
  Future<void> _afterVerification(BuildContext context) async {
    final childId = this.childId;
    if (!showQuestionnaire || childId == null) {
      _showResults(context);
      return;
    }
    // The practitioner-authored observation questions when active, else the
    // bundled ones; bounded by the repository's short timeout.
    final observation = await (templateRepository ??
            QuestionnaireTemplateRepository.instance)
        .choiceTemplateFor(TemplateKind.observation, 'post');
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder:
            (_) => SessionObservationScreen(
              template: observation,
              assessmentType: 'post',
              childId: childId,
              assessmentRunId: assessmentRunId,
              gameIds: gameIds,
              onDone: (next) => _showQuestionnaire(next, childId),
            ),
      ),
    );
  }

  Future<void> _showQuestionnaire(BuildContext context, String childId) =>
      HomeQuestionnaireFlow.show(
        context,
        assessmentType: 'post',
        childId: childId,
        assessmentRunId: assessmentRunId,
        onDone: _showResults,
        repository: templateRepository,
      );

  void _showResults(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder:
            (_) => PostAssessmentResultScreen(
              improvement: improvement,
              nextModulePremiumRequired: nextModulePremiumRequired,
            ),
      ),
    );
  }
}
