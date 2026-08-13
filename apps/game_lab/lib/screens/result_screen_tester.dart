import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Test harness for the shared [AssessmentResultLayout] widget.
///
/// Provides a hardcoded [AssessmentResultViewModel] and toggles for the
/// analysis source and the presentation mode, so the completion and review
/// modes can be compared side by side.
class ResultScreenTester extends StatefulWidget {
  const ResultScreenTester({super.key});

  @override
  State<ResultScreenTester> createState() => _ResultScreenTesterState();
}

class _ResultScreenTesterState extends State<ResultScreenTester> {
  bool _showAi = true;
  bool _review = false;

  // ── Mock data ──────────────────────────────────────────────────────────

  static const _mockAreas = [
    ResultAreaLevel(
        label: 'Communication', levelName: 'Emerging', levelInt: 1),
    ResultAreaLevel(
        label: 'Social Interaction', levelName: 'Needs Support', levelInt: 0),
    ResultAreaLevel(label: 'Play Skills', levelName: 'Emerging', levelInt: 1),
    ResultAreaLevel(label: 'Attention', levelName: 'Strength', levelInt: 2),
  ];

  static const _mockGames = [
    ResultGameScore(
      gameId: 'copy_me',
      name: 'Copy Me',
      emoji: '🪞',
      accuracy: 0.29,
      correctCount: 4,
      errorCount: 10,
      totalItems: 10,
    ),
    ResultGameScore(
      gameId: 'do_what_i_say',
      name: 'Do What I Say',
      emoji: '🗣️',
      accuracy: 0.28,
      correctCount: 5,
      errorCount: 13,
      totalItems: 12,
    ),
    ResultGameScore(
      gameId: 'my_turn_your_turn',
      name: 'My Turn, Your Turn',
      emoji: '🔄',
      accuracy: 0.50,
      correctCount: 6,
      errorCount: 6,
      totalItems: 8,
    ),
    ResultGameScore(
      gameId: 'match_it',
      name: 'Match It',
      emoji: '🧩',
      accuracy: 0.65,
      correctCount: 13,
      errorCount: 7,
      totalItems: 14,
    ),
  ];

  static const _mockPath = [
    ResultModule(name: 'Copy Me', startingLevel: 1),
    ResultModule(name: 'Do What I Say', startingLevel: 1),
    ResultModule(name: 'My Turn, Your Turn', startingLevel: 2),
    ResultModule(name: 'Match It', startingLevel: 2),
  ];

  static const _mockRecommendations = [
    ResultRecommendation(
        icon: Icons.speed_rounded,
        label: AssessmentLabels.difficulty,
        value: 'Beginner'),
    ResultRecommendation(
        icon: Icons.record_voice_over_rounded,
        label: AssessmentLabels.promptStyle,
        value: 'Combined'),
    ResultRecommendation(
        icon: Icons.timer_rounded,
        label: AssessmentLabels.sessionLength,
        value: '5 min'),
    ResultRecommendation(
        icon: Icons.repeat_rounded,
        label: AssessmentLabels.promptRepetition,
        value: '2x'),
    ResultRecommendation(
        icon: Icons.people_rounded,
        label: AssessmentLabels.turnTakingPractice,
        value: 'Extra practice'),
  ];

  AssessmentResultViewModel get _model => AssessmentResultViewModel(
        assessmentType: 'pre',
        assessmentRunId: 'run-demo',
        completedAt: DateTime(2026, 5, 12),
        games: _mockGames,
        areas: _mockAreas,
        recommendations: _mockRecommendations,
        source: _showAi
            ? AssessmentAnalysisSource.onDeviceAi
            : AssessmentAnalysisSource.ruleBased,
        confidence: _showAi ? 0.94 : 0.5,
        summary: 'Communication and social interaction need support. '
            'Play skills are emerging. Attention is a strength.',
        learningPath: _mockPath,
        sensoryObservations: const ['Prefers Quiet Play'],
      );

  @override
  Widget build(BuildContext context) {
    // Wrap in a Stack to overlay the toggle buttons.
    return Stack(
      children: [
        AssessmentResultLayout(
          model: _model,
          presentation: _review
              ? AssessmentResultPresentation.review
              : AssessmentResultPresentation.completion,
          onContinue: () => Navigator.of(context).pop(),
          onBack: () => Navigator.of(context).pop(),
          onRetake: () {},
        ),
        Positioned(
          top: 12,
          right: 12,
          child: SafeArea(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _toggle(
                  icon: _showAi ? Icons.smart_toy : Icons.rule,
                  label: _showAi ? 'Switch to Rule' : 'Switch to AI',
                  onPressed: () => setState(() => _showAi = !_showAi),
                ),
                const SizedBox(width: 6),
                _toggle(
                  icon: _review ? Icons.celebration : Icons.fact_check,
                  label: _review ? 'Completion mode' : 'Review mode',
                  onPressed: () => setState(() => _review = !_review),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _toggle({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 28,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 10)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          backgroundColor: Colors.white.withAlpha(220),
          side: const BorderSide(color: Color(0xFF9B82C4), width: 1),
        ),
      ),
    );
  }
}
