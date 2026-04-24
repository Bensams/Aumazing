import 'package:game_core/game_core.dart';

import '../model/assessment_result.dart';
import '../model/support_profile.dart';

/// Analyzes per-game assessment results and generates a [SupportProfile]
/// with a non-clinical developmental summary and recommendations.
class ScoringService {
  const ScoringService();

  SupportProfile generateProfile({
    required List<AssessmentResult> results,
    required Map<String, dynamic> sensorySettings,
  }) {
    // Get games for each category dynamically
    final commGameIds = GameRegistry.gamesForCategory(SkillCategory.communication)
        .map((g) => g.id)
        .toList();
    final playGameIds = GameRegistry.gamesForCategory(SkillCategory.playSkills)
        .map((g) => g.id)
        .toList();
    final socialGameIds = GameRegistry.gamesForCategory(SkillCategory.socialInteraction)
        .map((g) => g.id)
        .toList();

    // ── Communication ───────────────────────────────────────────────
    final commScores = results
        .where((r) => commGameIds.contains(r.gameId))
        .map((r) => r.accuracy)
        .toList();
    final communication = _level(commScores.isEmpty ? 0.0 : _avg(commScores));

    // ── Social Interaction ──────────────────────────────────────────
    String socialInteraction;
    final socialResults = results
        .where((r) => socialGameIds.contains(r.gameId))
        .toList();
    if (socialResults.isEmpty) {
      socialInteraction = 'emerging';
    } else {
      // Apply early_taps logic to social interaction games
      final earlyTaps = socialResults
          .map((r) => r.rawMetrics['early_taps'] as int? ?? 0)
          .reduce((a, b) => a + b);
      final socialAccuracy = _avg(socialResults.map((r) => r.accuracy).toList());
      if (earlyTaps <= 1 && socialAccuracy >= 0.8) {
        socialInteraction = 'good';
      } else if (socialAccuracy >= 0.5) {
        socialInteraction = 'improving';
      } else {
        socialInteraction = 'needs guided turn-taking';
      }
    }

    // ── Play Skills ─────────────────────────────────────────────────
    final playScores = results
        .where((r) => playGameIds.contains(r.gameId))
        .map((r) => r.accuracy)
        .toList();
    final playSkills = _level(playScores.isEmpty ? 0.0 : _avg(playScores));

    // ── Attention (all games: avg response time) ────────────────────
    final allTimes = results.map((r) => r.avgResponseTimeMs).toList();
    final avgTime = allTimes.isEmpty
        ? 5000
        : (allTimes.reduce((a, b) => a + b) / allTimes.length).round();
    String attention;
    if (avgTime > 4000) {
      attention = 'short attention';
    } else if (avgTime > 2000) {
      attention = 'moderate';
    } else {
      attention = 'sustained';
    }

    // ── Sensory Notes ───────────────────────────────────────────────
    final sensoryNotes = <String>[];
    if (sensorySettings['music_enabled'] == false) {
      sensoryNotes.add('prefers no music');
    } else if ((sensorySettings['music_volume'] ?? 0.5) < 0.3) {
      sensoryNotes.add('low music volume');
    }
    if (sensorySettings['vibration_enabled'] == false) {
      sensoryNotes.add('no vibration');
    }
    if ((sensorySettings['animation_intensity'] ?? 1.0) < 0.5) {
      sensoryNotes.add('low animation');
    }

    // ── Recommendations ─────────────────────────────────────────────
    final overallAccuracy = results.isEmpty
        ? 0.0
        : results.map((r) => r.accuracy).reduce((a, b) => a + b) /
            results.length;

    String difficulty;
    if (overallAccuracy >= 0.8) {
      difficulty = 'advanced';
    } else if (overallAccuracy >= 0.5) {
      difficulty = 'intermediate';
    } else {
      difficulty = 'beginner';
    }

    final needsTurnPractice = socialResults.isNotEmpty &&
        (socialResults
                .map((r) => r.rawMetrics['early_taps'] as int? ?? 0)
                .reduce((a, b) => a + b) > 2 ||
            _avg(socialResults.map((r) => r.accuracy).toList()) < 0.5);

    final lowStim = sensoryNotes.length >= 2;

    final promptRep = overallAccuracy < 0.4
        ? 3
        : overallAccuracy < 0.7
            ? 2
            : 1;

    final sessionMin = attention == 'short attention' ? 3 : 5;

    // Do What I Say may report preferred mode
    final doWhat = _findResult(results, 'do_what_i_say');
    final promptStyle =
        doWhat?.rawMetrics['preferred_mode'] as String? ?? 'combined';

    return SupportProfile(
      communication: communication,
      socialInteraction: socialInteraction,
      playSkills: playSkills,
      attention: attention,
      sensoryNotes: sensoryNotes,
      recommendedDifficulty: difficulty,
      recommendedPromptStyle: promptStyle,
      recommendedSessionMinutes: sessionMin,
      lowStimulationMode: lowStim,
      turnTakingPractice: needsTurnPractice,
      promptRepetition: promptRep,
    );
  }

  // ── helpers ────────────────────────────────────────────────────────

  AssessmentResult? _findResult(
    List<AssessmentResult> results,
    String gameId,
  ) {
    try {
      return results.firstWhere((r) => r.gameId == gameId);
    } catch (_) {
      return null;
    }
  }

  double _avg(List<double> values) =>
      values.reduce((a, b) => a + b) / values.length;

  String _level(double accuracy) {
    if (accuracy >= 0.8) return 'strong';
    if (accuracy >= 0.5) return 'developing';
    return 'emerging';
  }
}
