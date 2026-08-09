import 'dart:async';
import 'dart:math' as math;

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart';

import 'package:shared_ui/shared_ui.dart';
import 'components/sequence_shape.dart';
import '../../analytics/enhanced_analytics_mixin.dart';
import '../../analytics/models/models.dart';

/// Copy Me Game — Full Analytics Integration Example
///
/// This version demonstrates comprehensive use of the EnhancedGameplayAnalyticsMixin
/// for XGBoost-ready data collection.
///
/// ## Analytics Tracked:
/// - **Timing**: timeToFirstTouch, timeToFirstValidAction, timeToCompletion
/// - **Performance**: accuracy, correctCount, wrongCount
/// - **Assistance**: hintCount, promptCount, retryCount
/// - **Engagement**: randomTouchCount, offTaskActionCount, idleTimeSeconds
/// - **Game-Specific**: imitationSuccess, demonstrationsNeeded, sequenceLength
///
/// ## Usage:
/// ```dart
/// CopyMeGameAnalyticsExample(
///   totalRounds: 5,
///   childId: 'child_123',
///   onStepChanged: (step) => print('Round $step'),
///   onGameComplete: (metrics) => saveToFirestore(metrics),
/// )
/// ```
class CopyMeGameAnalyticsExample extends FlameGame
    with TapCallbacks, EnhancedGameplayAnalyticsMixin {
  CopyMeGameAnalyticsExample({
    required this.totalRounds,
    required this.childId,
    required this.onStepChanged,
    required this.onGameComplete,
    this.gameVersion,
  });

  final int totalRounds;
  final String childId;
  final String? gameVersion;
  final void Function(int currentStep) onStepChanged;
  final void Function(GameSessionMetrics metrics) onGameComplete;

  // ── Game State ───────────────────────────────────────────────────────────

  int _currentRound = 0;
  int _score = 0;
  int _errorCount = 0;
  int _demonstrationsNeeded = 0;

  /// Tracks if child is currently watching the demo (can't interact)
  bool _isDemonstrating = false;

  /// Tracks if child is in input phase (can interact)
  bool _isInputPhase = false;

  /// Tracks the expected sequence index the child should tap next
  int _expectedSequenceIndex = 0;

  /// The generated sequence for current round
  List<int> _sequence = [];

  /// Timer for showing hints after inactivity
  Timer? _noResponseTimer;

  /// Shapes on screen
  final List<SequenceShape> _shapes = [];

  /// Notify Flutter layer about phase changes (for UI indicators)
  void Function(bool isDemoPhase)? onPhaseChanged;

  // ── Configuration ─────────────────────────────────────────────────────────

  static const _shapeData = [
    (CopyMeShapeType.circle, AppColors.mint, 'Circle'),
    (CopyMeShapeType.star, AppColors.butterYellow, 'Star'),
    (CopyMeShapeType.heart, AppColors.peach, 'Heart'),
    (CopyMeShapeType.diamond, AppColors.skyBlue, 'Diamond'),
  ];

  /// Time before showing a hint (seconds)
  static const int _hintDelaySeconds = 8;

  @override
  Color backgroundColor() => const Color(0x00000000);

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // 1. Initialize analytics with all required metadata
    analyticsInitialize(
      gameId: 'copy_me',
      childId: childId,
      totalRounds: totalRounds,
      gameVersion: gameVersion ?? '1.0.0',
      deviceInfo: _getDeviceInfo(),
    );

    // 2. Start the analytics session
    analyticsStartSession();

    // 3. Layout shapes
    _layoutShapes();

    // 4. Start first round
    _startRound();
  }

  void _layoutShapes() {
    final gameW = size.x;
    final gameH = size.y;
    final cardSize = math.min(gameW / 5.5, gameH / 3.0);
    final gap = cardSize * 0.22;
    final totalW = 4 * cardSize + 3 * gap;
    final startX = (gameW - totalW) / 2;
    final centerY = gameH / 2 - cardSize / 2;

    for (var i = 0; i < 4; i++) {
      final data = _shapeData[i];
      final shape = SequenceShape(
        shapeType: data.$1,
        shapeColor: data.$2,
        index: i,
        onTapped: _onShapeTapped,
        position: Vector2(startX + i * (cardSize + gap), centerY),
        size: Vector2.all(cardSize),
      );
      _shapes.add(shape);
      add(shape);
    }
  }

  // ── Round Management ──────────────────────────────────────────────────────

  void _startRound() {
    _expectedSequenceIndex = 0;
    _isDemonstrating = true;
    _isInputPhase = false;

    // Generate sequence: length increases with round
    final sequenceLength = (_currentRound + 1).clamp(1, 5);
    final rng = math.Random();
    _sequence = List.generate(sequenceLength, (_) => rng.nextInt(4));

    // 5. Start analytics round tracking
    analyticsStartRound(roundNumber: _currentRound + 1);

    // 6. Record game-specific data for this round
    analyticsAddRoundData('sequence_length', sequenceLength);
    analyticsAddRoundData('round_difficulty', sequenceLength);

    // Disable input during demo
    for (final s in _shapes) {
      s.inputEnabled = false;
    }

    // 7. Record that stimulus (sequence demonstration) is being shown
    analyticsShowStimulus();
    onPhaseChanged?.call(true);

    _demonstrationsNeeded++;
    analyticsAddGameSpecificMetric('demonstrations_needed', _demonstrationsNeeded);

    // Play the demo sequence
    _playDemoSequence();
  }

  Future<void> _playDemoSequence() async {
    await Future.delayed(const Duration(milliseconds: 500));

    for (final idx in _sequence) {
      if (!isMounted) return;
      _shapes[idx].highlight();

      // Track demonstration as a "prompt" since we're showing the child what to do
      analyticsRecordPrompt(promptType: 'sequence_demonstration');

      await Future.delayed(const Duration(milliseconds: 700));
    }

    if (!isMounted) return;

    // Demo complete, enable input
    _isDemonstrating = false;
    _isInputPhase = true;
    onPhaseChanged?.call(false);

    for (final s in _shapes) {
      s.inputEnabled = true;
    }

    // 8. New stimulus: now child needs to respond
    analyticsShowStimulus();

    _startNoResponseTimer();
  }

  // ── Input Handling ─────────────────────────────────────────────────────────

  @override
  void onTapDown(TapDownEvent event) {
    // 9. Let analytics track the touch first
    analyticsHandleTapDown(event);

    // Check if touch is on a shape
    final tappedShape = _findTappedShape(event.localPosition);

    if (tappedShape != null) {
      // This is a valid game interaction
      _onShapeTapped(tappedShape.index);
    } else {
      // 10. Touch was on empty screen - record as random/off-task
      analyticsRecordOffTaskAction(actionType: 'empty_screen_touch');
    }
  }

  SequenceShape? _findTappedShape(Vector2 position) {
    for (final shape in _shapes) {
      if (shape.containsPoint(position)) {
        return shape;
      }
    }
    return null;
  }

  void _onShapeTapped(int index) {
    // Ignore if not in input phase
    if (!_isInputPhase || _isDemonstrating) return;

    _cancelNoResponseTimer();

    final expectedIndex = _sequence[_expectedSequenceIndex];

    if (index == expectedIndex) {
      // ── CORRECT ──

      // 11. Record valid action (first touch in response to stimulus)
      if (_expectedSequenceIndex == 0) {
        analyticsRecordValidAction();
      }

      // Visual feedback
      _shapes[index].showCorrect();

      // 12. Record correct response
      analyticsRecordCorrect(extraData: {
        'shape_index': index,
        'sequence_position': _expectedSequenceIndex,
        'expected_shape': _shapeData[expectedIndex].$3,
      });

      _expectedSequenceIndex++;

      // Check if sequence complete
      if (_expectedSequenceIndex >= _sequence.length) {
        // 13. Round complete!
        _score++;

        // Calculate imitation success for this round
        final successRate = 1.0; // Perfect this round
        analyticsAddRoundData('imitation_success', successRate);
        analyticsAddGameSpecificMetric(
          'imitation_success_${_currentRound + 1}',
          successRate,
        );

        // Mark round complete
        analyticsCompleteRound(successful: true);

        _isInputPhase = false;
        for (final s in _shapes) {
          s.inputEnabled = false;
        }

        _currentRound++;
        onStepChanged(_currentRound);

        // Check if game complete
        if (_currentRound >= totalRounds) {
          _finishGame();
        } else {
          Future.delayed(const Duration(milliseconds: 800), _startRound);
        }
      }
    } else {
      // ── INCORRECT ──

      // Visual feedback
      _shapes[index].showWrong();

      _errorCount++;

      // 14. Record wrong response
      analyticsRecordWrong(extraData: {
        'tapped_shape': _shapeData[index].$3,
        'expected_shape': _shapeData[expectedIndex].$3,
        'sequence_position': _expectedSequenceIndex,
      });

      // 15. Record retry (child must restart sequence)
      analyticsRecordRetry();

      // Reset to beginning of sequence
      _expectedSequenceIndex = 0;

      // Visual indicator that sequence restarted
      _startNoResponseTimer();
    }
  }

  // ── Assistance (Hints) ────────────────────────────────────────────────────

  void _startNoResponseTimer() {
    _cancelNoResponseTimer();
    _noResponseTimer = Timer(const Duration(seconds: _hintDelaySeconds), () {
      if (!isMounted || !_isInputPhase) return;
      _showVisualHint();
    });
  }

  void _cancelNoResponseTimer() {
    _noResponseTimer?.cancel();
    _noResponseTimer = null;
    _hideVisualHint();
  }

  void _showVisualHint() {
    if (_expectedSequenceIndex < _sequence.length) {
      _shapes[_sequence[_expectedSequenceIndex]].showHint();

      // 16. Record hint provided
      analyticsRecordHint(hintType: 'visual_next_shape');

      // Also record as a prompt for promptDependency calculation
      analyticsRecordPrompt(promptType: 'visual_hint_after_idle');
    }
  }

  void _hideVisualHint() {
    for (final s in _shapes) {
      s.hideHint();
    }
  }

  // ── Game Completion ───────────────────────────────────────────────────────

  void _finishGame() {
    // 17. Mark session completed
    analyticsMarkCompleted();

    // Calculate overall imitation success rate
    final overallImitationSuccess = _score / totalRounds;
    analyticsAddGameSpecificMetric('overall_imitation_success', overallImitationSuccess);
    analyticsAddGameSpecificMetric('total_demonstrations_needed', _demonstrationsNeeded);

    // 18. End the analytics session
    analyticsCompleteSession();

    // 19. Get the complete metrics
    final metrics = analyticsSession!;

    // Small delay for visual feedback
    Future.delayed(const Duration(milliseconds: 600), () {
      // 20. Pass metrics to the completion handler
      onGameComplete(metrics);
    });
  }

  // ── Early Exit Handling ───────────────────────────────────────────────────

  /// Call this when the user exits before completing all rounds
  void handleEarlyExit() {
    // 21. Record early exit
    analyticsRecordExit();

    // The analytics mixin will:
    // - Set earlyExit = true
    // - Calculate metrics for completed rounds
    // - Finalize the session

    final metrics = analyticsSession!;
    onGameComplete(metrics);
  }

  // ── Rendering ─────────────────────────────────────────────────────────────
  // Phase labels are not drawn on the canvas: the hosting screen shows them in
  // the upper-left VoiceOverPromptBubble.

  // ── Cleanup ────────────────────────────────────────────────────────────────

  @override
  void onRemove() {
    _cancelNoResponseTimer();
    // The mixin handles analytics cleanup in its onRemove
    super.onRemove();
  }
}

// Helper for device platform - uses dart:io when available
String _getDeviceInfo() {
  try {
    // In a real app, use dart:io Platform or Flutter's defaultTargetPlatform
    return 'Flutter/Mobile';
  } catch (_) {
    return 'Flutter/Unknown';
  }
}
