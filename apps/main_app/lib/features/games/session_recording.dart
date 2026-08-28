import 'dart:async';
import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../providers/assessment_provider.dart';
import '../../providers/progress_provider.dart';
import '../home/home_screen.dart';

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

/// Every game screen latches its completion so the engine firing
/// `onGameComplete` twice can't run the route-popping completion flow twice.
/// If that flow then stalls — the session write hangs, or the reward hands off
/// to a choice/time-up dialog that is never pushed — the child is left staring
/// at the finished frame with no way forward. This guard arms a deadline when
/// the completion latches, cancels it once a real next surface appears
/// ([GameEndChoiceDialog.show]'s `onShown`, or the host taking over navigation
/// / unmount), and otherwise ferries the child back to the lobby.
///
/// [`beginCompletion`] returns `true` only on the first latch, so it replaces
/// the usual `if (_completionHandled) return; _completionHandled = true;`
/// guard.
mixin GameCompletionGuard<T extends StatefulWidget> on State<T> {
  /// How long the child may wait for a real next surface after completion
  /// latches before the guard ferries them to the lobby.
  static const Duration _completionWatchdogTimeout = Duration(seconds: 15);

  bool _completionLatched = false;
  Timer? _completionWatchdog;

  /// Latches completion and arms the escape watchdog. Returns `true` on the
  /// first call; any later call returns `false` and must abort the flow.
  @protected
  bool beginCompletion() {
    if (_completionLatched) return false;
    _completionLatched = true;
    _armCompletionWatchdog();
    return true;
  }

  /// Stands the watchdog down once a real next surface (reward/choice/time-up/
  /// victory, or the host/unmount taking the child elsewhere) is in place.
  @protected
  void cancelCompletionWatchdog() {
    _completionWatchdog?.cancel();
    _completionWatchdog = null;
  }

  /// Resets the watchdog's 15s window at the moment a real next surface (the
  /// reward/choice dialog) actually begins to appear, so a slow session write
  /// that pushed past the first window does not cut the reward/choice short
  /// (AUM-317). Without this, a `record` taking more than ~5s plus the 10s
  /// reward would let the guard fire mid-reward.
  @protected
  void armCompletionWatchdog() {
    if (!_completionLatched) return;
    _armCompletionWatchdog();
  }

  void _armCompletionWatchdog() {
    _completionWatchdog?.cancel();
    _completionWatchdog = Timer(_completionWatchdogTimeout, () {
      if (!mounted || !_completionLatched) return;
      _completionWatchdog = null;
      // Hard escape: a stuck dialog or a never-shown choice must never be a
      // dead end for the child (AUM-317). Clear everything and land on lobby.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => completionFallbackSurface()),
        (_) => false,
      );
    });
  }

  /// The surface a timed-out completion falls back to. Defaults to the lobby
  /// ([HomeScreen]); a test host overrides this so the worst-case escape does
  /// not need the whole lobby provider stack to render.
  @protected
  Widget completionFallbackSurface() => const HomeScreen();

  @override
  void dispose() {
    cancelCompletionWatchdog();
    super.dispose();
  }
}
