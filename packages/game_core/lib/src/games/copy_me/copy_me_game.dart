import 'dart:async';
import 'dart:math' as math;

import 'package:flame/components.dart' hide Timer;
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart';

import 'components/pattern_slot.dart';
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
    with
        TapCallbacks,
        DragCallbacks,
        EnhancedGameplayAnalyticsMixin,
        DeveloperAutomationHooks {
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

  /// The four palette cards (bottom row) the child taps or drags to copy with.
  final List<SequenceShape> _shapes = [];

  /// The pattern row (top strip): four slots that show the pattern during the
  /// demo, then fill in again as the child copies it back.
  final List<PatternSlot> _slots = [];

  /// Bounding box of the pattern row, used to decide whether a dragged palette
  /// card was dropped onto it.
  Rect _patternRowRect = Rect.zero;

  /// The "TAP THE SHAPES TO COPY!" caption, shown only during the input phase.
  TextComponent? _copyCaption;

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

    // Two rows now: the pattern row (top) plus the palette row (bottom), each
    // with a caption above it. Size the cards so both rows and their captions
    // fit under the overlay strip and clear of the mascot band.
    const topCapBand = 30.0; // "Watch the pattern!…" line above the slots
    const midCapBand = 30.0; // "TAP THE SHAPES TO COPY!" above the palette
    const rowGap = 20.0; // breathing room between the two blocks
    final availH = gameH - kTopOverlayBand - 12;

    var cardSize = math.min(
      gameW / 5.4,
      (availH - topCapBand - midCapBand - rowGap) / 2,
    );
    cardSize = cardSize.clamp(40.0, availH / 2);

    final gap = cardSize * 0.22;
    final totalW = 4 * cardSize + 3 * gap;
    final startX = (gameW - totalW) / 2;
    double xFor(int i) => startX + i * (cardSize + gap);

    // Stack the two blocks and centre them vertically in the available band.
    final blockH = topCapBand + cardSize + rowGap + midCapBand + cardSize;
    final blockTop = kTopOverlayBand + (availH - blockH) / 2;

    final slotRowY = blockTop + topCapBand;
    final paletteRowY = slotRowY + cardSize + rowGap + midCapBand;

    _patternRowRect = Rect.fromLTWH(
      startX - gap,
      slotRowY - gap,
      totalW + 2 * gap,
      cardSize + 2 * gap,
    );

    // Top caption (always visible).
    add(_caption(
      'Watch the pattern! Then copy it in the row below.',
      y: blockTop + 4,
      width: gameW,
      fontSize: math.max(13.0, cardSize * 0.16),
      color: const Color(0xFF4A4458),
      bold: false,
    ));

    // Middle caption ("TAP THE SHAPES TO COPY!") — its text is set during the
    // input phase and cleared during the demo, so it only shows when it applies.
    _copyCaption = _caption(
      '',
      y: slotRowY + cardSize + rowGap + 2,
      width: gameW,
      fontSize: math.max(13.0, cardSize * 0.17),
      color: const Color(0xFF3F8F5B),
      bold: true,
    );
    add(_copyCaption!);

    // Pattern row — the dashed placeholder slots.
    for (var i = 0; i < 4; i++) {
      final slot = PatternSlot(
        index: i,
        position: Vector2(xFor(i), slotRowY),
        size: Vector2.all(cardSize),
      );
      _slots.add(slot);
      add(slot);
    }

    // Palette row — the four tappable / draggable shape cards.
    for (var i = 0; i < 4; i++) {
      final data = _shapeData[i];
      final shape = SequenceShape(
        shapeType: data.$1,
        shapeColor: data.$2,
        index: i,
        onTapped: _onShapeTapped,
        onDragDropped: _onShapeDragDropped,
        position: Vector2(xFor(i), paletteRowY),
        size: Vector2.all(cardSize),
      );
      _shapes.add(shape);
      add(shape);
    }
  }

  TextComponent _caption(
    String text, {
    required double y,
    required double width,
    required double fontSize,
    required Color color,
    required bool bold,
  }) {
    return TextComponent(
      text: text,
      position: Vector2(width / 2, y),
      anchor: Anchor.topCenter,
      textRenderer: TextPaint(
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          letterSpacing: bold ? 0.5 : 0.0,
        ),
      ),
    );
  }

  void _startRound() {
    _inputIndex = 0;
    _inputPhase = false;
    _consecutiveErrors = 0; // Reset consecutive errors for new round
    _hintsUsedThisRound = 0;
    _adaptive.startRound(); // any step-down only lasts one round

    // Build sequence: length = round + 1 (round 0 → 1 item, etc.), capped at
    // the four pattern slots.
    final rng = math.Random();
    final len = (_currentRound + 1).clamp(1, 4);
    _sequence = List.generate(len, (_) => rng.nextInt(4));

    // Start analytics round tracking
    analyticsStartRound(roundNumber: _currentRound + 1);
    analyticsAddRoundData('sequence_length', len);

    // Empty the pattern row and hide the copy caption while demonstrating.
    for (final slot in _slots) {
      slot.clear();
    }
    _copyCaption?.text = '';

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

    // Demonstrate: drop each shape into its pattern slot, left to right, so the
    // child watches the pattern build up in the row they will copy it into.
    for (var i = 0; i < _sequence.length; i++) {
      if (!isMounted) return;
      final idx = _sequence[i];
      _slots[i].fill(_shapeData[idx].$1, _shapeData[idx].$2);
      _shapes[idx].highlight();
      onPlaySequenceHighlightSfx?.call(i);
      await Future.delayed(const Duration(milliseconds: 700));
    }

    // Hold the finished pattern briefly, then clear it — the child copies it
    // back from memory into the now-empty slots.
    await Future.delayed(const Duration(milliseconds: 700));
    if (!isMounted) return;
    for (final slot in _slots) {
      slot.clear();
    }

    _demonstrating = false;
    _inputPhase = true;
    _inputStartTime = DateTime.now();
    onPhaseChanged?.call(false);
    _copyCaption?.text = 'TAP THE SHAPES TO COPY!';

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

  /// A drag of palette card [index] was released at [dropCenter]. If it landed
  /// on the pattern row it counts as picking that shape, exactly like a tap;
  /// otherwise the card simply returns home with no effect.
  void _onShapeDragDropped(int index, Vector2 dropCenter) {
    if (!_inputPhase || _demonstrating) return;
    if (!_patternRowRect.contains(Offset(dropCenter.x, dropCenter.y))) return;
    _onShapeTapped(index);
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

      // Drop the chosen shape into the next empty pattern slot so the child
      // sees the copy taking shape as they go.
      _slots[_inputIndex].fill(_shapeData[index].$1, _shapeData[index].$2);

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

        // Reset input — child re-copies this sequence from the start, so the
        // pattern slots they had filled empty back out.
        _inputIndex = 0;
        for (final slot in _slots) {
          slot.clear();
        }
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
