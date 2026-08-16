import 'package:game_core/game_core.dart';

import '../model/gameplay_session.dart';

/// Whether an assessment run covered everything it is scored on (AUM-154).
///
/// An assessment reports on four developmental areas, and each of the four
/// assessment games is the evidence for one of them. A run that stopped
/// after one or two games has nothing to say about the areas it never
/// reached — so finalizing it would produce a profile and a recommendation
/// built on absent evidence, and the parent would have no way to tell.
///
/// The rule lives here, apart from the provider, so both the pre- and
/// post-assessment paths ask the same question and a test can drive it
/// without a database.
abstract final class AssessmentCompleteness {
  /// The games a run must cover to be scored, in registry order.
  static List<String> get requiredGameIds => GameRegistry.assessmentGameIds;

  /// Required games with no session in [sessions], in registry order.
  ///
  /// Extra sessions — a replayed game, a practice round that slipped into
  /// the list — never make a run incomplete; only absence does.
  static List<String> missingGames(Iterable<GameplaySession> sessions) {
    final played = sessions.map((s) => s.gameId).toSet();
    return [
      for (final id in requiredGameIds)
        if (!played.contains(id)) id,
    ];
  }

  /// True when every required game has at least one session.
  static bool isComplete(Iterable<GameplaySession> sessions) =>
      missingGames(sessions).isEmpty;

  /// How many of the required games have been covered so far.
  static int playedCount(Iterable<GameplaySession> sessions) =>
      requiredGameIds.length - missingGames(sessions).length;

  /// A parent-facing explanation of why a run cannot be scored yet.
  ///
  /// Names the progress rather than the failure: an interrupted assessment
  /// is a normal thing to resume, not an error the parent caused.
  static String incompleteMessage(Iterable<GameplaySession> sessions) {
    final missing = missingGames(sessions);
    if (missing.isEmpty) return '';
    final done = playedCount(sessions);
    final total = requiredGameIds.length;
    final remaining = missing.length == 1 ? 'game' : 'games';
    return 'This assessment covered $done of $total activities. '
        'The last ${missing.length} $remaining still need to be played '
        'before the results can be worked out.';
  }
}
