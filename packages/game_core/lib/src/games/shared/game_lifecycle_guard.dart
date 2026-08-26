import 'dart:async';

import 'package:flame/game.dart';

/// Prevents delayed callbacks from a disposed Flame game affecting a later one.
///
/// The token changes synchronously on both lifecycle teardown paths. Callbacks
/// that can outlive a game should capture [lifecycleToken] and check it through
/// [isLifecycleTokenValid], or use [guardedDelay].
///
/// [tryBeginCompletion] is a one-shot gate for rapid duplicate input at the
/// end of a game.
mixin GameLifecycleGuard on FlameGame {
  int _lifecycleGeneration = 0;
  bool _lifecycleActive = true;
  bool _completionStarted = false;

  int get lifecycleToken => _lifecycleGeneration;

  bool get isLifecycleActive => _lifecycleActive;
  bool get isCompletionStarted => _completionStarted;

  bool isLifecycleTokenValid(int token) =>
      _lifecycleActive && token == _lifecycleGeneration;

  bool tryBeginCompletion() {
    if (!_lifecycleActive || _completionStarted) return false;
    _completionStarted = true;
    return true;
  }

  Future<void> guardedDelay(Duration delay, void Function() callback) async {
    final token = lifecycleToken;
    await Future<void>.delayed(delay);
    if (isLifecycleTokenValid(token)) callback();
  }

  void invalidateLifecycle() {
    if (!_lifecycleActive) return;
    _lifecycleActive = false;
    _lifecycleGeneration++;
  }

  @override
  void onRemove() {
    invalidateLifecycle();
    super.onRemove();
  }

  @override
  void onDispose() {
    invalidateLifecycle();
    super.onDispose();
  }
}
