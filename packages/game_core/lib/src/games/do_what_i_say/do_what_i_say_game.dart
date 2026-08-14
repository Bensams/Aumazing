import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';

import 'components/instruction_shape.dart';
import '../shared/answer_label.dart';
import '../shared/ghost_hand.dart';
import '../../analytics/enhanced_analytics_mixin.dart';
import '../../analytics/models/models.dart';
import '../../config/adaptive_difficulty.dart';
import '../../config/difficulty_profile.dart';
import '../shared/game_layout.dart';
import '../../automation/developer_automation.dart';

/// Do What I Say — instruction-following game with XGBoost-ready analytics.
///
/// Displays shapes and a text instruction like "Tap the RED circle".
/// The child taps the correct shape. Tracks comprehensive analytics for ML analysis.
class DoWhatISayGame extends FlameGame
    with TapCallbacks, EnhancedGameplayAnalyticsMixin, DeveloperAutomationHooks {
  DoWhatISayGame({
    required this.totalRounds,
    required this.onStepChanged,
    required this.onGameComplete,
    required this.onInstructionChanged,
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
    // Game-specific: listening instruction phase voice-over
    this.onPlayListenVo,
    // Composite voice-over: (action, colorName, shapeType)
    this.onPlayInstructionVoiceOver,
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
    required Map<String, dynamic> extras,
    GameSessionMetrics? analytics,
  }) onGameComplete;

  /// Called when the instruction text changes so the Flutter layer can display it.
  final void Function(String instruction) onInstructionChanged;

  /// Optional callback fired on each correct tap.
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
  /// Immediate feedback on a correct tap: the target the child found, so the
  /// app can name it back ("red circle"). Praise waits for the end of the game.
  final AnswerLabelCallback? onPlayCorrectVo;
  final VoidCallback? onPlayWrongVo;
  final VoidCallback? onPlayInstructionVo;
  final VoidCallback? onPlayTransitionVo;
  final VoidCallback? onPlayCelebrationVo;
  /// Voice-over for the listening instruction phase ("Listen carefully")
  final VoidCallback? onPlayListenVo;

  /// Callback for composite voice over: (action, colorName, shapeType)
  final void Function(String action, String colorName, String shapeType)? onPlayInstructionVoiceOver;

  // ── State ───────────────────────────────────────────────────────────
  int _currentRound = 0;
  int _score = 0;
  int _errorCount = 0;
  int _totalResponseTimeMs = 0;
  DateTime? _roundStartTime;

  final List<InstructionShape> _shapes = [];
  int _targetIndex = -1;

  // Instruction mode tracking
  int _visualCorrect = 0;
  int _verbalCorrect = 0;
  int _combinedCorrect = 0;

  // ── Hint / idle timer state ─────────────────────────────────────────
  Timer? _noResponseTimer;
  int _hintCount = 0;
  int _consecutiveErrors = 0;

  // Difficulty-tier hint state (see DifficultyProfile).
  int _hintsUsedThisRound = 0;
  int _idleRepeats = 0;
  GhostHand? _ghostHand;

  /// Within-round adaptive stepping: 2 consecutive errors temporarily step
  /// the tier down (more support) for the remainder of the round.
  late final AdaptiveDifficulty _adaptive = AdaptiveDifficulty(profile);

  /// The tier in effect right now (base, or one step easier after struggles).
  DifficultyProfile get _tier => _adaptive.effective;

  bool get _hintBudgetLeft =>
      _tier.unlimitedHints || _hintsUsedThisRound < (_tier.hintsPerRound ?? 0);

  // True, natural colors — the spoken color word must match what a child
  // sees in the real world ("red" is real red, not a pale tint), so the
  // color concept generalizes beyond the app.
  static const _colorOptions = [
    (Color(0xFFE53935), 'red'),
    (Color(0xFF1E88E5), 'blue'),
    (Color(0xFF43A047), 'green'),
    (Color(0xFFFDD835), 'yellow'),
    (Color(0xFF8E24AA), 'purple'),
    (Color(0xFFFB8C00), 'orange'),
  ];

  static const _shapeTypes = ['circle', 'star', 'triangle', 'diamond'];

  @override
  Color backgroundColor() => const Color(0x00000000);

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Initialize and start analytics session
    analyticsInitialize(
      gameId: 'do_what_i_say',
      childId: childId,
      totalRounds: totalRounds,
      gameVersion: gameVersion ?? '1.0.0',
    );
    analyticsStartSession();

    // _setupRound speaks the real instruction a moment from now ("Tap the
    // purple circle"), and that *is* the instruction — a generic "Listen"
    // ahead of it would only be cut off mid-word by it. So it plays only when
    // there is no composite voice-over to say instead, which is the same rule
    // _setupRound already applies to onPlayListenVo.
    if (onPlayInstructionVoiceOver == null) {
      onPlayInstructionVo?.call();
    }

    _setupRound();
  }

  void _setupRound() {
    // Cancel any existing timer from previous round
    _cancelNoResponseTimer();

    // Remove old shapes
    for (final s in _shapes) {
      s.removeFromParent();
    }
    _shapes.clear();

    // Reset per-round counters
    _hintCount = 0;
    _consecutiveErrors = 0;
    _hintsUsedThisRound = 0;
    _idleRepeats = 0;
    _adaptive.startRound(); // any step-down only lasts one round

    final rng = math.Random();
    final count = 4 + (_currentRound ~/ 2).clamp(0, 2); // 4-6 shapes

    // Build all unique shape+color combos (4 shapes × 6 colors = 24 combos)
    // This guarantees every shape on screen has a unique shape+color combination,
    // so the instruction is always unambiguous.
    final allCombos = <(String, Color, String)>[];
    for (final shapeType in _shapeTypes) {
      for (final colorData in _colorOptions) {
        allCombos.add((shapeType, colorData.$1, colorData.$2));
      }
    }
    allCombos.shuffle(rng);

    // Take first `count` — guaranteed unique since we drew from a set
    final items = allCombos.take(count).toList();

    // Layout shapes in a responsive grid
    final gameW = size.x;
    final gameH = size.y;
    final cols = count <= 4 ? 4 : 3;
    final rows = (count / cols).ceil();
    final availH = gameH - kTopOverlayBand;
    var cardSize = math.min(gameW / (cols + 1.5), gameH / (rows + 1.5));
    final rowSpan = rows + (rows - 1) * 0.2;
    if (rowSpan * cardSize > availH) cardSize = availH / rowSpan;
    final gap = cardSize * 0.2;
    final totalW = cols * cardSize + (cols - 1) * gap;
    final totalH = rows * cardSize + (rows - 1) * gap;
    final startX = (gameW - totalW) / 2;
    final startY = kTopOverlayBand + (availH - totalH) / 2;

    for (var i = 0; i < items.length; i++) {
      final col = i % cols;
      final row = i ~/ cols;
      final x = startX + col * (cardSize + gap);
      final y = startY + row * (cardSize + gap);
      final item = items[i];

      final shape = InstructionShape(
        shapeType: item.$1,
        shapeColor: item.$2,
        colorName: item.$3,
        sizeCategory: SizeCategory.big,
        index: i,
        onTapped: _onShapeTapped,
        position: Vector2(x, y),
        size: Vector2.all(cardSize),
      );
      _shapes.add(shape);
      add(shape);
    }

    // Pick target
    _targetIndex = rng.nextInt(_shapes.length);
    final target = _shapes[_targetIndex];

    // Generate instruction
    final instruction = 'Tap the ${target.colorName} ${target.shapeType}';
    onInstructionChanged(instruction);

    // Play composite voice-over for the instruction (e.g. "Tap the" + "Red" + "Circle")
    onPlayInstructionVoiceOver?.call('tap', target.colorName, target.shapeType);

    // Play listen voice-over when new instruction is shown (fallback if no composite VO)
    if (onPlayInstructionVoiceOver == null) {
      onPlayListenVo?.call();
    }

    _roundStartTime = DateTime.now();

    // Start round and show stimulus
    analyticsStartRound(roundNumber: _currentRound + 1);
    analyticsShowStimulus();

    // Record instruction as a prompt
    analyticsRecordPrompt(promptType: 'verbal_instruction');

    // Add round-specific data
    analyticsAddRoundData('shape_count', _shapes.length);
    analyticsAddRoundData('target_shape', target.shapeType);
    analyticsAddRoundData('target_color', target.colorName);

    // Start idle timer after instruction is set up
    _startNoResponseTimer();
  }

  // ── No-response timer ───────────────────────────────────────────────

  void _startNoResponseTimer() {
    _cancelNoResponseTimer();
    // Hard tier (or a spent Medium budget) waits longer between neutral
    // instruction repeats; Easy/Medium hint sooner.
    final delay = (_tier.noHints || !_hintBudgetLeft)
        ? _tier.reorientDelay
        : _tier.idleHintDelay;
    _noResponseTimer = Timer(delay, () {
      if (!isMounted) return;
      _onIdleTimeout();
    });
  }

  void _cancelNoResponseTimer() {
    _noResponseTimer?.cancel();
    _noResponseTimer = null;
  }

  void _onIdleTimeout() {
    // Repeat the instruction voice-over
    if (_targetIndex >= 0 && _targetIndex < _shapes.length) {
      final target = _shapes[_targetIndex];
      onPlayInstructionVoiceOver?.call('tap', target.colorName, target.shapeType);
    }

    _hintCount++;
    _idleRepeats++;
    analyticsRecordHint(hintType: 'idle_voice_over_repeat');
    analyticsRecordPrompt(promptType: 'voice_over_repeat_idle');

    // Answer hints (target highlight / tap demo) follow the tier's budget:
    // the voice-over repeat above is a neutral re-orientation allowed at
    // every tier, but revealing the target is not.
    if (_hintBudgetLeft && !_tier.noHints) {
      // Easy: highlight quickly (2nd idle repeat); Medium: 3rd as before.
      final guideThreshold = _tier.guidedDemo ? 2 : 3;
      if (_idleRepeats >= guideThreshold) {
        _showVisualGuide();
        // Easy tier: still idle -> escalate to the tap demo on the target.
        if (_tier.guidedDemo && _idleRepeats > guideThreshold) {
          _showTapDemo();
        }
      }
    }

    // Restart timer for further repeats
    _startNoResponseTimer();
  }

  /// Tap demo for the Easy tier: the ghost hand taps the target shape.
  void _showTapDemo() {
    if (_targetIndex < 0 || _targetIndex >= _shapes.length) return;
    final target = _shapes[_targetIndex];

    _ghostHand?.removeFromParent(); // never more than one demo at a time
    final hand = GhostHand.tap(
      at: target.position + target.size / 2,
      handSize: target.size.x * 0.7,
    );
    _ghostHand = hand;
    add(hand);
    analyticsRecordHint(hintType: 'gesture_demo');
  }

  // ── Visual guide ────────────────────────────────────────────────────

  void _showVisualGuide() {
    if (_targetIndex < 0 || _targetIndex >= _shapes.length) return;

    // Show pulsing hint on the correct target shape
    _shapes[_targetIndex].isHint = true;
    _hintsUsedThisRound++;

    analyticsRecordHint(hintType: 'visual_guide');
    analyticsRecordPrompt(promptType: 'visual_guide_target_highlight');

    // Auto-hide after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (isMounted && _targetIndex >= 0 && _targetIndex < _shapes.length) {
        _shapes[_targetIndex].isHint = false;
      }
    });
  }

  void _hideVisualHints() {
    for (final s in _shapes) {
      s.isHint = false;
    }
  }

  // ── Shape tap handler ───────────────────────────────────────────────

  void _onShapeTapped(int index) {
    // Cancel idle timer on any tap
    _cancelNoResponseTimer();
    _hideVisualHints();

    final target = _shapes[_targetIndex];

    // Play tap SFX on any shape tap
    onPlayTapSfx?.call();

    if (index == _targetIndex) {
      // Correct!
      _score++;
      _consecutiveErrors = 0; // Reset on correct
      _adaptive.recordCorrect();
      _idleRepeats = 0;

      // Record valid action on first tap
      analyticsRecordValidAction();

      // Record correct response with details
      analyticsRecordCorrect(extraData: {
        'target_shape': target.shapeType,
        'target_color': target.colorName,
        'distractor_count': _shapes.length - 1,
      });

      // Play correct SFX and voice-over
      onPlayCorrectSfx?.call();
      onPlayCorrectVo?.call(
          AnswerLabel(color: target.colorName, shape: target.shapeType));

      // Notify Flutter layer of correct tap (for haptic feedback)
      onCorrectMatch?.call();

      _shapes[index].showCorrect();

      // Track mode (simplified — always "combined" in v1)
      _combinedCorrect++;

      if (_roundStartTime != null) {
        _totalResponseTimeMs +=
            DateTime.now().difference(_roundStartTime!).inMilliseconds;
      }

      for (final s in _shapes) {
        s.inputEnabled = false;
      }

      _currentRound++;
      onStepChanged(_currentRound);

      // Complete round
      analyticsCompleteRound(successful: true);
      analyticsAddRoundData('instruction_followed', true);

      if (_currentRound >= totalRounds) {
        // Game complete — play game complete SFX and celebration VO
        _cancelNoResponseTimer();
        onPlayGameCompleteSfx?.call();
        onPlayCelebrationVo?.call();

        analyticsMarkCompleted();
        analyticsCompleteSession();

        // Add game-specific metrics
        final total = _visualCorrect + _verbalCorrect + _combinedCorrect;
        String preferredMode = 'combined';
        if (total > 0) {
          if (_visualCorrect > _verbalCorrect &&
              _visualCorrect > _combinedCorrect) {
            preferredMode = 'visual';
          } else if (_verbalCorrect > _visualCorrect &&
              _verbalCorrect > _combinedCorrect) {
            preferredMode = 'verbal';
          }
        }

        analyticsAddGameSpecificMetric('preferred_mode', preferredMode);
        analyticsAddGameSpecificMetric('avg_response_time_ms',
          _totalResponseTimeMs / (_score > 0 ? _score : 1));
        analyticsAddGameSpecificMetric('max_shape_count',
          4 + ((totalRounds - 1) ~/ 2).clamp(0, 2));
        analyticsAddGameSpecificMetric('hint_count', _hintCount);

        Future.delayed(const Duration(milliseconds: 600), () {
          onGameComplete(
            score: _score,
            totalItems: totalRounds,
            errorCount: _errorCount,
            totalResponseTimeMs: _totalResponseTimeMs,
            extras: {'preferred_mode': preferredMode},
            analytics: analyticsSession,
          );
        });
      } else {
        // Level/round complete — play level complete SFX and transition VO
        onPlayLevelCompleteSfx?.call();
        onPlayTransitionVo?.call();

        Future.delayed(const Duration(milliseconds: 800), _setupRound);
      }
    } else {
      // Wrong - tapped wrong shape
      _errorCount++;
      _consecutiveErrors++;

      // Adaptive stepping: repeated struggle steps the tier down (more
      // support) for the rest of this round.
      if (_adaptive.recordError()) {
        analyticsAddRoundData('difficulty_step_down', _tier.level);
      }

      // Play wrong SFX and voice-over
      onPlayWrongSfx?.call();
      onPlayWrongVo?.call();
      onWrongAnswer?.call();

      final tappedShape = _shapes[index];

      // Record wrong response with details
      analyticsRecordWrong(extraData: {
        'tapped_shape': tappedShape.shapeType,
        'tapped_color': tappedShape.colorName,
        'target_shape': target.shapeType,
        'target_color': target.colorName,
        'consecutive_errors': _consecutiveErrors,
        'error_type': tappedShape.shapeType == target.shapeType
          ? 'color_error'
          : tappedShape.colorName == target.colorName
            ? 'shape_error'
            : 'both_error',
      });

      _shapes[index].showWrong();

      // Error escalation follows the tier: Easy escalates after 2 errors
      // (visual guide + tap demo), Medium after 3 (guide gated by the hint
      // budget), Hard only re-plays the voice-over.
      final errorThreshold = _tier.guidedDemo ? 2 : 3;
      if (_consecutiveErrors >= errorThreshold) {
        _consecutiveErrors = 0; // Reset counter
        _hintCount++;
        analyticsRecordHint(hintType: 'error_voice_over_repeat');
        analyticsRecordPrompt(promptType: 'voice_over_repeat_errors');

        if (_hintBudgetLeft && !_tier.noHints) {
          _showVisualGuide();
          // Easy tier: show exactly where to tap.
          if (_tier.guidedDemo) _showTapDemo();
        }

        // The idle timer replays the voice-over when it fires
        _startNoResponseTimer();
      } else {
        // Restart idle timer after wrong tap
        _startNoResponseTimer();
      }
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

  @override
  void onRemove() {
    _cancelNoResponseTimer();
    super.onRemove();
  }

  // ── Developer auto-play ─────────────────────────────

  /// Ready once a target has been chosen and the shapes accept taps — which
  /// is false while the instruction is still being read out.
  @override
  bool get debugAwaitingInputImpl =>
      _targetIndex >= 0 &&
      _targetIndex < _shapes.length &&
      _shapes.every((s) => s.inputEnabled);

  /// Taps the shape the instruction actually asked for, through the same
  /// handler [InstructionShape] calls.
  @override
  void debugPerformCorrectActionImpl() => _onShapeTapped(_targetIndex);
}
