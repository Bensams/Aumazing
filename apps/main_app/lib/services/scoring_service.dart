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
    final copyMe = _findResult(results, 'copy_me');
    final doWhat = _findResult(results, 'do_what_i_say');
    final turnTaking = _findResult(results, 'my_turn_your_turn');
    final matchIt = _findResult(results, 'match_it');

    // ── Communication (Copy Me + Do What I Say) ─────────────────────
    final commScores = <double>[
      if (copyMe != null) copyMe.accuracy,
      if (doWhat != null) doWhat.accuracy,
    ];
    final communication = _level(
      commScores.isEmpty ? 0.0 : _avg(commScores),
    );

    // ── Social Interaction (My Turn Your Turn) ──────────────────────
    String socialInteraction;
    if (turnTaking == null) {
      socialInteraction = 'emerging';
    } else {
      final earlyTaps = turnTaking.rawMetrics['early_taps'] as int? ?? 0;
      if (earlyTaps <= 1 && turnTaking.accuracy >= 0.8) {
        socialInteraction = 'good';
      } else if (turnTaking.accuracy >= 0.5) {
        socialInteraction = 'improving';
      } else {
        socialInteraction = 'needs guided turn-taking';
      }
    }

    // ── Play Skills (Match It + Copy Me) ────────────────────────────
    final playScores = <double>[
      if (matchIt != null) matchIt.accuracy,
      if (copyMe != null) copyMe.accuracy,
    ];
    final playSkills = _level(
      playScores.isEmpty ? 0.0 : _avg(playScores),
    );

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

    final needsTurnPractice = turnTaking != null &&
        ((turnTaking.rawMetrics['early_taps'] as int? ?? 0) > 2 ||
            turnTaking.accuracy < 0.5);

    final lowStim = sensoryNotes.length >= 2;

    final promptRep = overallAccuracy < 0.4
        ? 3
        : overallAccuracy < 0.7
            ? 2
            : 1;

    final sessionMin = attention == 'short attention' ? 3 : 5;

    // Do What I Say may report preferred mode
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
