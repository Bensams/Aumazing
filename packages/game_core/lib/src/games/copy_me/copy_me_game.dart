import 'dart:async';
import 'dart:math' as math;

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart';

import 'components/sequence_shape.dart';
import '../../automation/developer_automation.dart';
import '../shared/answer_label.dart';
import '../../analytics/enhanced_analytics_mixin.dart';
import '../../analytics/models/models.dart';
import '../../config/adaptive_difficulty.dart';
import '../../config/difficulty_profile.dart';
import '../shared/game_layout.dart';

/// Copy Me — a "Simon Says" style sequence memory game with XGBoost-ready analytics.
///
/// The app highlights shapes in an increasing sequence and the child
/// must reproduce the sequence by tapping in order.
class CopyMeGame extends FlameGame
    with TapCallbacks, EnhancedGameplayAnalyticsMixin, DeveloperAutomationHooks {
  CopyMeGame({
    required this.totalRounds,
    required this.onStepChanged,
    required this.onGameComplete,
    required this.childId,
    this.gameVersion,
    this.profile = DifficultyProfile.medium,
    this.onCorrectMatch,
    this.onWrongAnswer,
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

  /// Hint/guidance policy for the selected difficulty tier (ABA prompt
  /// hierarchy - see [DifficultyProfile]).
  final DifficultyProfile profile;

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

  /// Optional callback fired on each wrong tap, alongside the wrong SFX and the
  /// encouraging voice line. The Flutter layer uses it for the mascot's
  /// reaction, so the character answers a mistake the same way the audio does.
  final void Function()? onWrongAnswer;

  // ── Audio event callbacks ────────────────────────────────────────────
  final VoidCallback? onPlayCorrectSfx;
  final VoidCallback? onPlayWrongSfx;
  final VoidCallback? onPlayTapSfx;
  final VoidCallback? onPlayDragSfx;
  final VoidCallback? onPlayDropSfx;
  final VoidCallback? onPlayLevelCompleteSfx;
  final VoidCallback? onPlayGameCompleteSfx;
  /// Immediate feedback on each correct tap: the shape the child just hit, so
  /// the app can name it back. Fires per tap rather than per completed
  /// sequence — the point of naming is to land while the child is still
  /// looking at what they touched. Praise waits for the end of the game.
  final AnswerLabelCallback? onPlayCorrectVo;
  final VoidCallback? onPlayWrongVo;
  final VoidCallback? onPlayInstructionVo;
  final VoidCallback? onPlayTransitionVo;
  final VoidCallback? onPlayCelebrationVo;
  /// Voice-over for demo/watch phase ("Watch me first" / "My turn").
  ///
  /// Returns a future that completes when the line has finished if the caller
  /// can tell — the demo waits for it rather than for a fixed number of
  /// milliseconds. See [_playDemoSequence].
  final FutureOr<void> Function()? onPlayMyTurnVo;
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

  // Difficulty-tier hint state (see DifficultyProfile).
  int _hintsUsedThisRound = 0;

  /// Within-round adaptive stepping: 2 consecutive errors temporarily step
  /// the tier down (more support) for the remainder of the round.
  late final AdaptiveDifficulty _adaptive = AdaptiveDifficulty(profile);

  /// The tier in effect right now (base, or one step easier after struggles).
  DifficultyProfile get _tier => _adaptive.effective;

  bool get _hintBudgetLeft =>
      _tier.unlimitedHints || _hintsUsedThisRound < (_tier.hintsPerRound ?? 0);

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

  // True, natural colors (not pastel tints) so the shapes a child copies
  // carry real-world color concepts: green circle, yellow star, red heart,
  // blue diamond.
  static const _shapeData = [
    (CopyMeShapeType.circle, Color(0xFF43A047), 'Circle'),
    (CopyMeShapeType.star, Color(0xFFFDD835), 'Star'),
    (CopyMeShapeType.heart, Color(0xFFE53935), 'Heart'),
    (CopyMeShapeType.diamond, Color(0xFF1E88E5), 'Diamond'),
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
    final availH = gameH - kTopOverlayBand;
    var cardSize = math.min(gameW / 5.5, gameH / 3.0);
    if (cardSize > availH) cardSize = availH;
    final gap = cardSize * 0.22;
    final totalW = 4 * cardSize + 3 * gap;
    final startX = (gameW - totalW) / 2;
    // Centred in the space below the overlay strip, not the whole screen.
    final centerY = kTopOverlayBand + (availH - cardSize) / 2;

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
    _hintsUsedThisRound = 0;
    _adaptive.startRound(); // any step-down only lasts one round

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
    _playDemoSequence();
  }

  Future<void> _playDemoSequence() async {
    // "Watch me first" has to finish before the demo starts, or the child is
    // being told to watch while the thing to watch is already happening.
    //
    // How long that takes is not a number this game can know: the recording
    // differs per voice pack and per language (1.5 s in one, 1.8 s in
    // another), and the parent's prompt-speed setting stretches all of them.
    // So the line reports its own end, and this waits for that. A caller that
    // cannot report it falls back to a beat sized for the longest recording.
    final spoken = onPlayMyTurnVo?.call();
    if (spoken is Future) {
      await spoken;
    } else {
      await Future.delayed(const Duration(milliseconds: 2000));
    }
    if (!isMounted) return;

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
      _adaptive.recordCorrect();
        _shapes[index].showCorrect();

      // Play position-based shimmer SFX for this correct tap, then name the
      // shape that was tapped.
      onPlaySequenceHighlightSfx?.call(_inputIndex);
      onPlayCorrectVo?.call(AnswerLabel(shape: _shapeData[index].$3));

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
          // Game complete
          analyticsMarkCompleted();
          analyticsCompleteSession();

          // Add game-specific metrics
          analyticsAddGameSpecificMetric('avg_response_time_ms',
            _totalResponseTimeMs / (_score > 0 ? _score : 1));
          analyticsAddGameSpecificMetric('total_retries', _retries);
          analyticsAddGameSpecificMetric('max_sequence_length',
            totalRounds > 0 ? (totalRounds).clamp(1, 5) : 1);

          // Play game-complete SFX and the children's cheer immediately (uses
          // AudioService — separate player pool from VoiceOverService, so no
          // conflict with the voice-over).
          onPlayGameCompleteSfx?.call();

          // Wait for the last shape's name to finish before the celebration VO
          // (both use VoiceOverService, so they would cut each other off). One
          // shape name is short, so this is much less than the two seconds the
          // old full praise line needed.
          Future.delayed(const Duration(milliseconds: 900), () {
            if (!isMounted) return;
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
          // Level/round complete — play SFX immediately (uses AudioService —
          // separate player pool, no conflict with praise VO)
          onPlayLevelCompleteSfx?.call();

          // Wait for praise VO to finish before playing transition VO
          // (both use VoiceOverService, so they would cut each other off)
          Future.delayed(const Duration(milliseconds: 2000), () {
            if (!isMounted) return;
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
      onWrongAnswer?.call();

      _errorCount++;
      _retries++;
      _consecutiveErrors++; // Track consecutive errors

      // Adaptive stepping: repeated struggle steps the tier down (more
      // support) for the rest of this round.
      if (_adaptive.recordError()) {
        analyticsAddRoundData('difficulty_step_down', _tier.level);
      }

      // Record wrong response with details
      analyticsRecordWrong(extraData: {
        'tapped_shape': _shapeData[index].$3,
        'expected_shape': _shapeData[_sequence[_inputIndex]].$3,
        'sequence_position': _inputIndex,
        'consecutive_errors': _consecutiveErrors,
      });

      // Sequence replay follows the tier: Easy replays after 2 errors,
      // Medium after 3 while the hint budget lasts, Hard never replays
      // (independence). No ghost-hand demo here — Copy Me is a memory task,
      // and pointing at the next shape would confuse the sequence; the
      // replay itself is the visual guide.
      final errorThreshold = _tier.guidedDemo ? 2 : 3;
      if (_consecutiveErrors >= errorThreshold &&
          _hintBudgetLeft &&
          !_tier.noHints) {
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
    // Hard tier (or a spent Medium budget) waits longer and re-orients with
    // the "your turn" VO instead of replaying the sequence.
    final delay = (_tier.noHints || !_hintBudgetLeft)
        ? _tier.reorientDelay
        : _tier.idleHintDelay;
    _noResponseTimer = Timer(delay, () {
      if (!isMounted || !_inputPhase) return;
      if (_tier.noHints || !_hintBudgetLeft) {
        // Neutral re-orientation: never replays the answer.
        onPlayYourTurnVo?.call();
        analyticsRecordHint(hintType: 'reorient_instruction');
        _startNoResponseTimer();
        return;
      }
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
    _hintsUsedThisRound++;
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
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    // Record ALL taps — valid ones that hit components and invalid ones that missed
    analyticsRecordTouch(
      Offset(event.canvasPosition.x, event.canvasPosition.y),
      isValid: event.handled,
    );
  }

  // No on-canvas phase labels: the "Watch carefully…" / "Your turn! Tap the
  // shapes!" prompts belong to the VoiceOverPromptBubble overlay in the upper
  // left, which also honours the child's showTextPrompts preference.

  @override
  void onRemove() {
    _cancelNoResponseTimer();
    super.onRemove();
  }

  // ── Developer auto-play ─────────────────────────────

  /// Ready once the demo has finished and the shapes accept taps.
  @override
  bool get debugAwaitingInputImpl =>
      _inputPhase &&
      !_demonstrating &&
      _inputIndex < _sequence.length &&
      _shapes.length == 4 &&
      _shapes.every((s) => s.inputEnabled);

  /// Taps the next shape of the sequence the child was shown — the same call
  /// [SequenceShape] makes, so scoring, analytics and round advancement all
  /// run exactly as they do for a real tap.
  @override
  void debugPerformCorrectActionImpl() =>
      _onShapeTapped(_sequence[_inputIndex]);
}
