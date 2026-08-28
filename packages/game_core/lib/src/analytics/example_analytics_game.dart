import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';

import 'gameplay_analytics_mixin.dart';

// ──────────────────────────────────────────────────────────────────────────────
// EXAMPLE: A minimal FlameGame implementing GameplayAnalyticsMixin
// ──────────────────────────────────────────────────────────────────────────────

/// A skeleton mini-game that demonstrates how to wire up the
/// [GameplayAnalyticsMixin] inside a real [FlameGame].
///
/// Copy this pattern into any new Aumazing mini-game and replace the
/// placeholder logic with your actual gameplay.
class ExampleAnalyticsGame extends FlameGame
    with TapCallbacks, DragCallbacks, GameplayAnalyticsMixin {
  ExampleAnalyticsGame({
    required this.totalRounds,
    required this.onGameComplete,
  });

  final int totalRounds;
  final void Function(Map<String, dynamic> analyticsPayload) onGameComplete;

  int _currentRound = 0;

  // ── Lifecycle ─────────────────────────────────────────────────────────

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // 1️⃣  Start the analytics session and declare expected sub-tasks.
    analyticsSessionStart(totalSubTasks: totalRounds);

    // Present the first stimulus.
    _startNewRound();
  }

  // ── Round management ──────────────────────────────────────────────────

  void _startNewRound() {
    // 2️⃣  Each time a new prompt / cue appears, mark a stimulus.
    analyticsPresentStimulus();

    // … spawn shapes, show NPC prompt, etc.
  }

  // ── Tap handling ──────────────────────────────────────────────────────

  @override
  void onTapDown(TapDownEvent event) {
    // 3️⃣  The mixin's onTapDown automatically records interaction timing
    //     and calls analyticsRecordFirstInput(). Always call super so the
    //     mixin sees the event.
    super.onTapDown(event);

    // … your hit-testing / game logic …
    final hitCorrectTarget = _checkHit(event);

    if (hitCorrectTarget) {
      // 4️⃣  Record a correct interaction.
      analyticsRecordCorrect();

      // 5️⃣  Mark one sub-task as done.
      analyticsCompleteSubTask();

      _currentRound++;

      if (_currentRound >= totalRounds) {
        _finishGame();
      } else {
        _startNewRound();
      }
    } else {
      // 6️⃣  Record an incorrect interaction (also increments error count).
      analyticsRecordError();
    }
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    // 7️⃣  Let the mixin record drag data for interaction-quality analysis.
    super.onDragUpdate(event);

    // … your drag logic …
  }

  // ── Retry ─────────────────────────────────────────────────────────────

  /// Called when the player presses a "Try Again" button.
  void onRetry() {
    // 8️⃣  Increment the retry counter.
    analyticsRecordRetry();

    _currentRound = 0;
    analyticsReset();
    analyticsSessionStart(totalSubTasks: totalRounds);
    _startNewRound();
  }

  // ── Game complete ─────────────────────────────────────────────────────

  void _finishGame() {
    // 9️⃣  Mark core objective completed and end the session timer.
    analyticsMarkCompleted();
    analyticsSessionEnd();

    // 🔟  Serialize everything into a Supabase-ready JSON map.
    final payload = toAnalyticsJson();

    // Hand the payload to the Flutter layer (e.g. a Provider / Bloc)
    // which will upsert it into the Supabase `assessments.analytics` column.
    onGameComplete(payload);
  }

  // ── Placeholder hit test ──────────────────────────────────────────────

  bool _checkHit(TapDownEvent event) {
    // Replace with real hit-testing logic.
    return true;
  }

  @override
  Color backgroundColor() => const Color(0x00000000);
}
