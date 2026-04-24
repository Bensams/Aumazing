import 'dart:async';
import 'dart:math' as math;

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart';

import 'package:shared_ui/shared_ui.dart';
import 'components/sequence_shape.dart';
import '../../analytics/enhanced_analytics_mixin.dart';
import '../../analytics/models/models.dart';

/// Copy Me — a "Simon Says" style sequence memory game with XGBoost-ready analytics.
///
/// The app highlights shapes in an increasing sequence and the child
/// must reproduce the sequence by tapping in order.
class CopyMeGame extends FlameGame with TapCallbacks, EnhancedGameplayAnalyticsMixin {
  CopyMeGame({
    required this.totalRounds,
    required this.onStepChanged,
    required this.onGameComplete,
    required this.childId,
    this.gameVersion,
    this.onCorrectMatch,
    // Audio event callbacks (optional, wired by screen wrappers)
    this.onPlayCorrectSfx,
    this.onPlayWrongSfx,
    this.onPlayTapSfx,
    this.onPlayDragSfx,
    this.onPlayDropSfx,
    this.onPlayLevelCompleteSfx,
    this.onPlayGameCompleteSfx,
    this.onPlayCorrectVo,
    this.onPlayWrongVo,
    this.onPlayInstructionVo,
    this.onPlayTransitionVo,
    this.onPlayCelebrationVo,
    // Game-specific: Copy Me turn phase voice-overs
    this.onPlayMyTurnVo,
    this.onPlayYourTurnVo,
    // Game-specific: Copy Me sequence highlight SFX
    this.onPlaySequenceHighlightSfx,
  });

  final int totalRounds;
  final String childId;
  final String? gameVersion;
  final void Function(int currentStep) onStepChanged;
  final void Function({
    required int score,
    required int totalItems,
    required int errorCount,
    required int totalResponseTimeMs,
    GameSessionMetrics? analytics,
  }) onGameComplete;

  /// Optional callback fired on each individual correct tap in the sequence.
  /// Used by the Flutter layer to trigger haptic feedback during pre-assessment.
  final void Function()? onCorrectMatch;

  // ── Audio event callbacks ────────────────────────────────────────────
  final VoidCallback? onPlayCorrectSfx;
  final VoidCallback? onPlayWrongSfx;
  final VoidCallback? onPlayTapSfx;
  final VoidCallback? onPlayDragSfx;
  final VoidCallback? onPlayDropSfx;
  final VoidCallback? onPlayLevelCompleteSfx;
  final VoidCallback? onPlayGameCompleteSfx;
  final VoidCallback? onPlayCorrectVo;
  final VoidCallback? onPlayWrongVo;
  final VoidCallback? onPlayInstructionVo;
  final VoidCallback? onPlayTransitionVo;
  final VoidCallback? onPlayCelebrationVo;
  /// Voice-over for demo/watch phase ("Watch me first" / "My turn")
  final VoidCallback? onPlayMyTurnVo;
  /// Voice-over for child input phase ("Your turn" / "Now you try")
  final VoidCallback? onPlayYourTurnVo;
  /// SFX callback for each sequence highlight during demo phase.
  /// Receives the 0-based position in the sequence.
  final void Function(int sequencePosition)? onPlaySequenceHighlightSfx;

  // ── State ───────────────────────────────────────────────────────────
  int _currentRound = 0;
  int _score = 0;
  int _errorCount = 0;
  int _totalResponseTimeMs = 0;
  int _retries = 0;
  int _consecutiveErrors = 0; // Track consecutive invalid taps
  DateTime? _inputStartTime;

  final List<SequenceShape> _shapes = [];
  List<int> _sequence = [];
  int _inputIndex = 0;
  bool _demonstrating = false;
  bool _inputPhase = false;
  Timer? _noResponseTimer;

  /// Notify Flutter layer about phase changes
  void Function(bool isDemoPhase)? onPhaseChanged;
  
  /// Public method to trigger visual guide replay
  void replaySequenceAsVisualGuide() {
    if (_inputPhase && !_demonstrating) {
      _showSequentialVisualGuide();
    }
  }
  
  /// Public method to show visual hints for entire sequence
  void showFullSequenceHints() {
    if (_inputPhase && !_demonstrating) {
      _showEntireSequenceHints();
    }
  }

  static const _shapeData = [
    (CopyMeShapeType.circle, AppColors.mint, 'Circle'),
    (CopyMeShapeType.star, AppColors.butterYellow, 'Star'),
    (CopyMeShapeType.heart, AppColors.peach, 'Heart'),
    (CopyMeShapeType.diamond, AppColors.skyBlue, 'Diamond'),
  ];

  @override
  Color backgroundColor() => const Color(0x00000000);

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Initialize and start analytics session
    analyticsInitialize(
      gameId: 'copy_me',
      childId: childId,
      totalRounds: totalRounds,
      gameVersion: gameVersion ?? '1.0.0',
    );
    analyticsStartSession();

    // Play instruction voice-over when game loads
    onPlayInstructionVo?.call();

    _layoutShapes();

    // Wait for instruction VO ("Copy Me") to finish before starting first round
    // Use non-blocking delay so Flame's rendering pipeline isn't blocked
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (!isMounted) return;
      _startRound();
    });
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

  void _startRound() {
    _inputIndex = 0;
    _inputPhase = false;
    _consecutiveErrors = 0; // Reset consecutive errors for new round

    // Build sequence: length = round + 1 (round 0 → 1 item, etc.)
    final rng = math.Random();
    final len = (_currentRound + 1).clamp(1, 5);
    _sequence = List.generate(len, (_) => rng.nextInt(4));

    // Start analytics round tracking
    analyticsStartRound(roundNumber: _currentRound + 1);
    analyticsAddRoundData('sequence_length', len);

    // Disable input during demo
    for (final s in _shapes) {
      s.inputEnabled = false;
    }

    _demonstrating = true;
    onPhaseChanged?.call(true);
    // Play "my turn" / "watch me" voice-over for demo phase
    onPlayMyTurnVo?.call();
    _playDemoSequence();
  }

  Future<void> _playDemoSequence() async {
    // Wait for "Watch me first" / "My turn" VO to finish before starting demo
    await Future.delayed(const Duration(milliseconds: 2000));

    // Record stimulus when sequence demonstration starts
    analyticsShowStimulus();
    analyticsRecordPrompt(promptType: 'sequence_demonstration');

    for (var i = 0; i < _sequence.length; i++) {
      if (!isMounted) return;
      final idx = _sequence[i];
      _shapes[idx].highlight();
      onPlaySequenceHighlightSfx?.call(i);
      await Future.delayed(const Duration(milliseconds: 700));
    }

    if (!isMounted) return;
    _demonstrating = false;
    _inputPhase = true;
    _inputStartTime = DateTime.now();
    onPhaseChanged?.call(false);

    // Brief pause before "your turn" VO so it doesn't overlap with last highlight
    await Future.delayed(const Duration(milliseconds: 400));
    if (!isMounted) return;
    // Play "your turn" voice-over for child input phase
    onPlayYourTurnVo?.call();

    // New stimulus for child's input phase
    analyticsShowStimulus();

    for (final s in _shapes) {
      s.inputEnabled = true;
    }

    _startNoResponseTimer();
  }

  void _onShapeTapped(int index) {
    if (!_inputPhase || _demonstrating) return;

    _cancelNoResponseTimer();

    // Record valid action on first tap in sequence
    if (_inputIndex == 0) {
      analyticsRecordValidAction();
    }

    if (index == _sequence[_inputIndex]) {
      // Correct
      _shapes[index].showCorrect();

      // Play position-based shimmer SFX for this correct tap
      onPlaySequenceHighlightSfx?.call(_inputIndex);

      // Notify Flutter layer of individual correct tap (for haptic feedback)
      onCorrectMatch?.call();

      // Record correct response with details
      analyticsRecordCorrect(extraData: {
        'shape_index': index,
        'sequence_position': _inputIndex,
        'expected_shape': _shapeData[_sequence[_inputIndex]].$3,
      });

      _inputIndex++;

      if (_inputIndex >= _sequence.length) {
        // Sequence complete — this round was successful
        // Play praise voice-over only when the full sequence is completed
        onPlayCorrectVo?.call();
        _score++;
        _consecutiveErrors = 0; // Reset consecutive errors on success

        // Complete the analytics round
        analyticsCompleteRound(successful: true);
        analyticsAddRoundData('sequence_completed', true);
        analyticsAddRoundData('sequence_length', _sequence.length);

        if (_inputStartTime != null) {
          _totalResponseTimeMs +=
              DateTime.now().difference(_inputStartTime!).inMilliseconds;
        }

        _inputPhase = false;
        for (final s in _shapes) {
          s.inputEnabled = false;
        }

        _currentRound++;
        onStepChanged(_currentRound);

        if (_currentRound >= totalRounds) {
          // Game complete — wait for praise VO to finish, then play celebration
          analyticsMarkCompleted();
          analyticsCompleteSession();

          // Add game-specific metrics
          analyticsAddGameSpecificMetric('avg_response_time_ms',
            _totalResponseTimeMs / (_score > 0 ? _score : 1));
          analyticsAddGameSpecificMetric('total_retries', _retries);
          analyticsAddGameSpecificMetric('max_sequence_length',
            totalRounds > 0 ? (totalRounds).clamp(1, 5) : 1);

          // Wait for praise VO to finish before playing celebration VO
          Future.delayed(const Duration(milliseconds: 2000), () {
            if (!isMounted) return;
            onPlayGameCompleteSfx?.call();
            onPlayCelebrationVo?.call();

            Future.delayed(const Duration(milliseconds: 600), () {
              onGameComplete(
                score: _score,
                totalItems: totalRounds,
                errorCount: _errorCount,
                totalResponseTimeMs: _totalResponseTimeMs,
                analytics: analyticsSession,
              );
            });
          });
        } else {
          // Level/round complete — wait for praise VO to finish, then play transition
          Future.delayed(const Duration(milliseconds: 2000), () {
            if (!isMounted) return;
            onPlayLevelCompleteSfx?.call();
            onPlayTransitionVo?.call();

            // Wait for transition VO to finish before starting next round
            Future.delayed(const Duration(milliseconds: 2000), () {
              if (!isMounted) return;
              _startRound();
            });
          });
        }
      }
    } else {
      // Wrong — play wrong SFX and voice-over
      _shapes[index].showWrong();
      onPlayWrongSfx?.call();
      onPlayWrongVo?.call();

      _errorCount++;
      _retries++;
      _consecutiveErrors++; // Track consecutive errors

      // Record wrong response with details
      analyticsRecordWrong(extraData: {
        'tapped_shape': _shapeData[index].$3,
        'expected_shape': _shapeData[_sequence[_inputIndex]].$3,
        'sequence_position': _inputIndex,
        'consecutive_errors': _consecutiveErrors,
      });

      // Check if we should show visual guide after 3 consecutive errors
      if (_consecutiveErrors >= 3) {
        _showSequentialVisualGuide();
        _consecutiveErrors = 0; // Reset after showing guide
      } else {
        // Record retry
        analyticsRecordRetry();
        
        // Reset input — child retries this sequence
        _inputIndex = 0;
        _startNoResponseTimer();
      }
    }
  }

  void _startNoResponseTimer() {
    _cancelNoResponseTimer();
    _noResponseTimer = Timer(const Duration(seconds: 10), () {
      if (!isMounted || !_inputPhase) return;
      _showSequentialVisualGuide();
    });
  }

  void _cancelNoResponseTimer() {
    _noResponseTimer?.cancel();
    _noResponseTimer = null;
    _hideVisualHint();
  }
  
  /// Show visual hints for the entire sequence at once
  void _showEntireSequenceHints() {
    if (!isMounted || !_inputPhase) return;
    
    // Hide any existing hints first
    _hideVisualHint();
    
    // Show hints for all shapes in the sequence
    for (final idx in _sequence) {
      _shapes[idx].showHint();
    }
    
    // Record the full sequence hint prompt
    analyticsRecordPrompt(promptType: 'visual_guide_full_sequence_hint');
    analyticsRecordHint(hintType: 'full_sequence_visual');
    
    // Auto-hide hints after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (isMounted && _inputPhase) {
        _hideVisualHint();
      }
    });
  }
  
  /// Enhanced visual guide that highlights shapes in correct sequence
  Future<void> _showSequentialVisualGuide() async {
    if (!isMounted || !_inputPhase) return;
    
    // Temporarily disable input during visual guide
    for (final s in _shapes) {
      s.inputEnabled = false;
    }
    
    // Hide any existing hints
    _hideVisualHint();
    
    // Record the sequential visual guide prompt
    analyticsRecordPrompt(promptType: 'visual_guide_sequential_highlight');
    analyticsRecordHint(hintType: 'sequential_visual_guide');
    
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Highlight each shape in the correct sequence with timing
    for (int i = 0; i < _sequence.length; i++) {
      if (!isMounted) return;
      
      final idx = _sequence[i];
      
      // Highlight the current shape in sequence
      _shapes[idx].highlight();
      
      // Wait for highlight to complete before next one
      await Future.delayed(const Duration(milliseconds: 800));
      
      // Brief pause between shapes
      if (i < _sequence.length - 1) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
    
    if (!isMounted) return;
    
    // Re-enable input after visual guide
    for (final s in _shapes) {
      s.inputEnabled = true;
    }
    
    // Restart no-response timer
    _startNoResponseTimer();
  }

  void _hideVisualHint() {
    for (final s in _shapes) {
      s.hideHint();
    }
  }

  @override
  void render(Canvas canvas) {
    final fontSize = (size.x * 0.035).clamp(16.0, 24.0);
    // Demo phase label
    if (_demonstrating) {
      final tp = TextPainter(
        text: TextSpan(
          text: 'Watch carefully…',
          style: TextStyle(
            color: Color(0xFF9B82C4),
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.x / 2 - tp.width / 2, 20));
    } else if (_inputPhase) {
      final tp = TextPainter(
        text: TextSpan(
          text: 'Your turn! Tap the shapes!',
          style: TextStyle(
            color: Color(0xFF5DAF8E),
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.x / 2 - tp.width / 2, 20));
    }

    super.render(canvas);
  }

  @override
  void onRemove() {
    _cancelNoResponseTimer();
    super.onRemove();
  }
}
