import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../providers/assessment_provider.dart';

/// Persists a finished game before the flow moves on.
///
/// Every game screen used to fire `recordGameSession()` and immediately
/// advance, so a failed or still-pending write could be followed by a
/// celebration, a reward and — during an assessment — a finalization that
/// scored fewer games than the child actually played. Recording is awaited
/// here instead, and a failure is offered to the parent as a retry rather
/// than swallowed.
abstract final class GameSessionRecording {
  /// Records the session, retrying on failure until it succeeds or the user
  /// chooses to continue without it.
  ///
  /// Returns true when the session is safely persisted. A false return means
  /// the flow may continue, but nothing was stored — callers in an
  /// assessment must not present the run as successfully completed.
  static Future<bool> record(
    BuildContext context, {
    required String childId,
    required String gameId,
    required String assessmentContext,
    required int score,
    required int totalItems,
    required int errorCount,
    required int totalResponseTimeMs,
    required DateTime startedAt,
    GameSessionMetrics? analytics,
    bool bgMusicEnabled = true,
    bool hapticFeedbackEnabled = true,
    bool applySessionSensoryDefaults = true,
  }) async {
    final provider = context.read<AssessmentProvider>();

    while (true) {
      try {
        await provider.recordGameSession(
          childId: childId,
          gameId: gameId,
          context: assessmentContext,
          score: score,
          totalItems: totalItems,
          errorCount: errorCount,
          totalResponseTimeMs: totalResponseTimeMs,
          startedAt: startedAt,
          analytics: analytics,
          bgMusicEnabled: bgMusicEnabled,
          hapticFeedbackEnabled: hapticFeedbackEnabled,
          applySessionSensoryDefaults: applySessionSensoryDefaults,
        );
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
