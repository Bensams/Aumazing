import 'package:flutter/material.dart';
import 'package:questionnaire_core/questionnaire_core.dart';

import '../../model/ai_assessment_response.dart';
import '../../model/assessment_result.dart';
import '../../model/support_profile.dart';
import '../../widgets/assessment_handoff.dart';
import '../../widgets/milestone_victory_scene.dart';
import '../questionnaire/questionnaire_template_repository.dart';
import '../questionnaire/session_observation_screen.dart';
import 'game_summary_dialog.dart';
import 'pre_assessment_result_screen.dart';

/// Screen shown to the child after all pre-assessment games are complete.
///
/// The celebration, the "give the device to your parent" hand-off and the
/// verification gate all live in [AssessmentHandoffScreen], which the
/// post-assessment shares. This screen supplies only what is specific to the
/// pre-assessment: the summary dialog and the result screen behind it.
class WaitingForParentScreen extends StatelessWidget {
  const WaitingForParentScreen({
    super.key,
    required this.results,
    required this.profile,
    this.aiResponse,
    this.voiceOverFactory,
    this.childId,
    this.assessmentRunId,
    this.showQuestionnaire = true,
    this.templateRepository,
  });

  /// Where the questionnaire's active template comes from. Injectable for
  /// tests; the app uses the shared repository.
  final QuestionnaireTemplateRepository? templateRepository;

  /// The child and the finished run, so the parent questionnaire is stored
  /// against them. The run id is captured before the run is closed.
  final String? childId;
  final String? assessmentRunId;

  /// Whether the adult's "What did you see?" questions (AUM-351) come
  /// between verification and the results. On in the app; tests about the
  /// hand-off itself turn it off. The home questionnaire is not asked here:
  /// it comes once, at child profile setup (AUM-364).
  final bool showQuestionnaire;

  final List<AssessmentResult> results;
  final SupportProfile profile;

  /// AI prediction data, or null if AI was unavailable (rule-based fallback).
  final AiAssessmentResponse? aiResponse;

  /// Test seam, forwarded to [AssessmentHandoffScreen].
  final HandoffVoiceOverFactory? voiceOverFactory;

  @override
  Widget build(BuildContext context) {
    return AssessmentHandoffScreen(
      title: MilestoneKind.preAssessment.title,
      subtitle: MilestoneKind.preAssessment.subtitle,
      milestoneVoiceCue: MilestoneKind.preAssessment.voiceCue,
      voiceOverFactory: voiceOverFactory,
      onParentVerified: _afterVerification,
    );
  }

  /// The parent has the device: what they saw while the child played —
  /// before any result is on screen — then the summary.
  Future<void> _afterVerification(BuildContext context) async {
    final childId = this.childId;
    if (!showQuestionnaire || childId == null) {
      _showSummary(context);
      return;
    }
    // The games this run played, in order, each once.
    final played = {for (final r in results) r.gameId}.toList();
    // The practitioner-authored observation questions when active, else the
    // bundled ones; bounded by the repository's short timeout.
    final observation = await (templateRepository ??
            QuestionnaireTemplateRepository.instance)
        .choiceTemplateFor(TemplateKind.observation, 'pre');
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder:
            (_) => SessionObservationScreen(
              template: observation,
              assessmentType: 'pre',
              childId: childId,
              assessmentRunId: assessmentRunId,
              gameIds: played,
              // The home questionnaire was asked when the profile was set
              // up (AUM-364), so the summary follows straight away.
              onDone: _showSummary,
            ),
      ),
    );
  }

  void _showSummary(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder:
            (summaryContext) => GameSummaryDialog(
              results: results,
              aiResponse: aiResponse,
              onContinue: () {
                Navigator.of(summaryContext).pushReplacement(
                  MaterialPageRoute(
                    builder:
                        (_) => PreAssessmentResultScreen(
                          profile: profile,
                          results: results,
                          aiResponse: aiResponse,
                        ),
                  ),
                );
              },
            ),
      ),
    );
  }
}
