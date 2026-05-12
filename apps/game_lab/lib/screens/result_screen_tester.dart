import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Test harness for the shared [AssessmentResultLayout] widget.
///
/// Provides hardcoded mock data and a toggle to switch between
/// AI-powered and Rule-based views.
class ResultScreenTester extends StatefulWidget {
  const ResultScreenTester({super.key});

  @override
  State<ResultScreenTester> createState() => _ResultScreenTesterState();
}

class _ResultScreenTesterState extends State<ResultScreenTester> {
  bool _showAi = true;

  // ── Mock data ──────────────────────────────────────────────────────────

  static const _mockAreaLevels = [
    ResultAreaLevel(
        label: 'Communication', levelName: 'Emerging', levelInt: 1),
    ResultAreaLevel(
        label: 'Social Interaction', levelName: 'Needs Support', levelInt: 0),
    ResultAreaLevel(
        label: 'Play Skills', levelName: 'Emerging', levelInt: 1),
    ResultAreaLevel(
        label: 'Attention', levelName: 'Strength', levelInt: 2),
  ];

  static const _mockGameScores = [
    ResultGameScore(
        gameId: 'copy_me', name: 'Copy Me', emoji: '🪞', accuracy: 0.29),
    ResultGameScore(
        gameId: 'do_what_i_say',
        name: 'Do What I Say',
        emoji: '🗣️',
        accuracy: 0.28),
    ResultGameScore(
        gameId: 'my_turn_your_turn',
        name: 'My Turn, Your Turn',
        emoji: '🔄',
        accuracy: 0.50),
    ResultGameScore(
        gameId: 'match_it', name: 'Match It', emoji: '🧩', accuracy: 0.65),
  ];

  static const _mockModules = [
    ResultModule(name: 'Copy Me', startingLevel: 1),
    ResultModule(name: 'Do What I Say', startingLevel: 1),
    ResultModule(name: 'My Turn, Your Turn', startingLevel: 2),
    ResultModule(name: 'Match It', startingLevel: 2),
  ];

  static const _mockProfileRows = [
    ResultProfileRow(area: 'Communication', level: 'Emerging'),
    ResultProfileRow(area: 'Social Interaction', level: 'Needs Support'),
    ResultProfileRow(area: 'Play Skills', level: 'Emerging'),
    ResultProfileRow(area: 'Attention', level: 'Strong'),
  ];

  static const _mockRecommendations = [
    ResultRecommendation(
        icon: Icons.speed_rounded, label: 'Difficulty', value: 'beginner'),
    ResultRecommendation(
        icon: Icons.record_voice_over_rounded,
        label: 'Prompt Style',
        value: 'combined'),
    ResultRecommendation(
        icon: Icons.timer_rounded, label: 'Session Length', value: '5 min'),
    ResultRecommendation(
        icon: Icons.repeat_rounded,
        label: 'Prompt Repetition',
        value: '2x'),
    ResultRecommendation(
        icon: Icons.people_rounded,
        label: 'Practice',
        value: 'Extra turn-taking'),
  ];

  static const _mockAiData = ResultAiData(
    areaLevels: _mockAreaLevels,
    confidence: 0.94,
    summary: 'Communication and social interaction need support. '
        'Play skills are emerging. Attention is a strength.',
    modules: _mockModules,
  );

  @override
  Widget build(BuildContext context) {
    // Wrap in a Stack to overlay the toggle button
    return Stack(
      children: [
        AssessmentResultLayout(
          profileRows: _mockProfileRows,
          recommendations: _mockRecommendations,
          gameScores: _mockGameScores,
          aiData: _showAi ? _mockAiData : null,
          onContinue: () => Navigator.of(context).pop(),
        ),
        // Toggle button overlay
        Positioned(
          top: 12,
          right: 12,
          child: SafeArea(
            child: SizedBox(
              height: 28,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _showAi = !_showAi),
                icon: Icon(
                  _showAi ? Icons.smart_toy : Icons.rule,
                  size: 14,
                ),
                label: Text(
                  _showAi ? 'Switch to Rule' : 'Switch to AI',
                  style: const TextStyle(fontSize: 10),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  backgroundColor: Colors.white.withAlpha(220),
                  side: const BorderSide(color: Color(0xFF9B82C4), width: 1),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
