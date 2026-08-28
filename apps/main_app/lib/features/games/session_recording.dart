import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../providers/assessment_provider.dart';
import '../../providers/progress_provider.dart';

/// Persists a finished game before the flow moves on.
///
/// Every game screen used to fire `recordGameSession()` and immediately
/// advance, so a failed or still-pending write could be followed by a
/// celebration, a reward and — during an assessment — a finalization that
/// scored fewer games than the child actually played. Recording is awaited
/// here instead, and a failure is offered to the parent as a retry rather
/// than swallowed.
///
/// The persisted session is also handed straight to [ProgressProvider], so
/// the parent dashboard's "Recent activity" reflects the play the moment
/// child mode is popped. This is a purely local hand-off: the write already
/// landed in the offline database, and the background push to Supabase is
/// fire-and-forget. Nothing on the dashboard waits for the network.
abstract final class GameSessionRecording {
  /// Records the session, retrying on failure until it succeeds or the user
  /// chooses to continue without it.
  ///
  /// Returns true when the session is safely persisted. A false return means
  /// the flow may continue, but nothing was stored — callers in an
  /// assessment must not present the run as successfully completed.
  ///
  /// [childId] is the loaded child's id, or null when no profile is loaded.
  /// A null id is refused rather than substituted: see below.
  static Future<bool> record(
    BuildContext context, {
    required String? childId,
    required String gameId,
    required String assessmentContext,
    required int score,
    required int totalItems,
    required int errorCount,
    required int totalResponseTimeMs,
    required DateTime startedAt,
    GameSessionMetrics? analytics,
    String? configurationVersionOverride,
    bool bgMusicEnabled = true,
    bool hapticFeedbackEnabled = true,
    bool applySessionSensoryDefaults = true,
  }) async {
    // Without a loaded profile there is no child this play belongs to. The
    // screens used to fall back to the literal id 'unknown', which wrote a
    // row that matched no child: invisible to the dashboard, unscorable by
    // finalization, and missed by every child-scoped delete. The play was
    // lost while the game celebrated as if it had been saved. Refuse the
    // write and say so instead — retrying cannot conjure a profile, so this
    // is told once rather than offered as a retry.
    if (childId == null || childId.isEmpty) {
      debugPrint(
        '[GameSessionRecording] $gameId not saved: no child profile loaded',
      );
      await _warnNotSaved(context);
      return false;
    }

    final provider = context.read<AssessmentProvider>();
    // Read before the first await: a retry dialog can rebuild the tree, and
    // the game screen may be gone by the time the write succeeds.
    final progress = context.read<ProgressProvider>();

    while (true) {
      try {
        final session = await provider.recordGameSession(
          childId: childId,
          gameId: gameId,
          context: assessmentContext,
          score: score,
          totalItems: totalItems,
          errorCount: errorCount,
          totalResponseTimeMs: totalResponseTimeMs,
          startedAt: startedAt,
          analytics: analytics,
          configurationVersionOverride: configurationVersionOverride,
          bgMusicEnabled: bgMusicEnabled,
          hapticFeedbackEnabled: hapticFeedbackEnabled,
          applySessionSensoryDefaults: applySessionSensoryDefaults,
        );
        // Null means a duplicate completion callback for a game already
        // recorded — the row exists, so there is nothing new to show.
        if (session != null) progress.addSession(session);
        return true;
      } catch (e) {
        debugPrint('[GameSessionRecording] $gameId failed to save: $e');
        if (!context.mounted) return false;
        final retry = await _askToRetry(context);
        if (!retry) return false;
        if (!context.mounted) return false;
      }
    }
  }

  /// Tells the parent the game was not kept, with no retry to offer.
  static Future<void> _warnNotSaved(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Could not save this game'),
            content: const Text(
              'No child profile was open, so the results of this game were '
              'not saved. Choose a child profile before playing.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  static Future<bool> _askToRetry(BuildContext context) async {
    final retry = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Could not save this game'),
            content: const Text(
              'The results of this game have not been saved yet. Try again to '
              'keep them, or continue without saving.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Continue anyway'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text(AssessmentLabels.tryAgain),
              ),
            ],
          ),
    );
    return retry ?? false;
  }
}
