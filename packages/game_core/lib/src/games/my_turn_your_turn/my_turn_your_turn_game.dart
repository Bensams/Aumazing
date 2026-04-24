import 'dart:math' as math;

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart';

import 'package:shared_ui/shared_ui.dart';
import 'components/turn_slot.dart';
import '../../analytics/enhanced_analytics_mixin.dart';
import '../../analytics/models/models.dart';

/// My Turn, Your Turn — a turn-taking game with a virtual buddy.
///
/// The app and child alternate placing shapes on a grid.
/// Measures impulse control (early taps), waiting, and completion.
/// Tracks comprehensive XGBoost-ready analytics.
class MyTurnYourTurnGame extends FlameGame with TapCallbacks, EnhancedGameplayAnalyticsMixin {
  MyTurnYourTurnGame({
    required this.totalRounds,
    required this.onStepChanged,
    required this.onGameComplete,
    required this.onTurnChanged,
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
    // Game-specific: turn-taking phase voice-overs
    this.onPlayMyTurnVo,
    this.onPlayYourTurnVo,
    this.onPlayWaitVo,
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
    required Map<String, dynamic> extras,
    GameSessionMetrics? analytics,
  }) onGameComplete;

  /// Notify Flutter layer: true = buddy's turn, false = child's turn
  final void Function(bool isBuddyTurn) onTurnChanged;

  /// Optional callback fired on each correct child turn.
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
  /// Voice-over for buddy's turn ("My turn")
  final VoidCallback? onPlayMyTurnVo;
  /// Voice-over for child's turn ("Your turn")
  final VoidCallback? onPlayYourTurnVo;
  /// Voice-over for waiting phase ("Wait")
  final VoidCallback? onPlayWaitVo;

  // ── State ───────────────────────────────────────────────────────────
  int _currentRound = 0;
  int _score = 0;
  int _errorCount = 0;
  int _earlyTaps = 0;
  int _totalResponseTimeMs = 0;
  DateTime? _turnStartTime;

  final List<TurnSlot> _slots = [];
  bool _isBuddyTurn = true;
  int _turnsInRound = 0;
  static const _slotsPerRound = 6; // 3x2 grid = 6 slots, 3 each

  static const _buddyColors = [
    AppColors.peach,
    AppColors.skyBlue,
    AppColors.lavender,
  ];

  static const _childColors = [
    AppColors.mint,
    AppColors.butterYellow,
    AppColors.peach,
  ];

  @override
  Color backgroundColor() => const Color(0x00000000);

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Initialize and start analytics session
    analyticsInitialize(
      gameId: 'my_turn_your_turn',
      childId: childId,
      totalRounds: totalRounds,
      gameVersion: gameVersion ?? '1.0.0',
    );
    analyticsStartSession();

    // Play instruction voice-over when game loads
    onPlayInstructionVo?.call();

    _setupRound();
  }

  void _setupRound() {
    for (final s in _slots) {
      s.removeFromParent();
    }
    _slots.clear();
    _turnsInRound = 0;

    // Start analytics round
    analyticsStartRound(roundNumber: _currentRound + 1);
    analyticsAddRoundData('slots_per_round', _slotsPerRound);
    analyticsAddRoundData('child_turns_per_round', _slotsPerRound ~/ 2);

    // Layout 3x2 responsive grid
    final gameW = size.x;
    final gameH = size.y;
    const cols = 3;
    const rows = 2;
    final cardSize = math.min(gameW / (cols + 1.5), gameH / (rows + 1.5));
    final gap = cardSize * 0.16;
    final totalW = cols * cardSize + (cols - 1) * gap;
    final totalH = rows * cardSize + (rows - 1) * gap;
    final startX = (gameW - totalW) / 2;
    final startY = (gameH - totalH) / 2;

    for (var i = 0; i < _slotsPerRound; i++) {
      final col = i % cols;
      final row = i ~/ cols;
      final slot = TurnSlot(
        slotIndex: i,
        onTapped: _onSlotTapped,
        position: Vector2(
          startX + col * (cardSize + gap),
          startY + row * (cardSize + gap),
        ),
        size: Vector2.all(cardSize),
      );
      _slots.add(slot);
      add(slot);
    }

    // Start with buddy's turn
    _startBuddyTurn();
  }

  void _startBuddyTurn() {
    _isBuddyTurn = true;
    onTurnChanged(true);
    // Play "my turn" and "wait" voice-overs for buddy's turn
    onPlayMyTurnVo?.call();
    onPlayWaitVo?.call();

    for (final s in _slots) {
      s.inputEnabled = false;
    }

    // Buddy acts after a delay (simulating thinking)
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!isMounted) return;
      _buddyPlays();
    });
  }

  void _buddyPlays() {
    final emptySlots =
        _slots.where((s) => !s.isFilled).toList();
    if (emptySlots.isEmpty) return;

    final rng = math.Random();
    final slot = emptySlots[rng.nextInt(emptySlots.length)];
    final color = _buddyColors[rng.nextInt(_buddyColors.length)];
    slot.fillByBuddy(color);
    _turnsInRound++;

    // Check if round complete
    if (_checkRoundComplete()) return;

    // Switch to child's turn
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!isMounted) return;
      _startChildTurn();
    });
  }

  void _startChildTurn() {
    _isBuddyTurn = false;
    onTurnChanged(false);
    // Play "your turn" voice-over for child's turn
    onPlayYourTurnVo?.call();
    _turnStartTime = DateTime.now();

    // Child's turn is the stimulus
    analyticsShowStimulus();
    analyticsRecordPrompt(promptType: 'your_turn_indicator');

    for (final s in _slots) {
      s.inputEnabled = true; // allow tapping empty slots
    }
  }

  void _onSlotTapped(int index) {
    final slot = _slots[index];
    if (slot.isFilled) return;

    if (_isBuddyTurn) {
      // Early tap during buddy's turn — impulse control issue
      _earlyTaps++;
      _errorCount++;

      // Play wrong SFX and voice-over for early tap
      onPlayWrongSfx?.call();
      onPlayWrongVo?.call();

      // Record as off-task action (important for XGBoost)
      analyticsRecordOffTaskAction(actionType: 'early_tap_during_buddy_turn');
      analyticsRecordWrong(extraData: {
        'error_type': 'impulse_control',
        'turn_phase': 'buddy_turn',
        'slot_index': index,
      });

      slot.showEarlyTapWarning();
      return;
    }

    // Child's turn — fill the slot
    // Play tap SFX
    onPlayTapSfx?.call();

    final rng = math.Random();
    final color = _childColors[rng.nextInt(_childColors.length)];
    slot.fillByChild(color);
    _turnsInRound++;
    _score++;

    // Play correct SFX and voice-over
    onPlayCorrectSfx?.call();
    onPlayCorrectVo?.call();

    // Record valid action and correct response
    analyticsRecordValidAction();
    analyticsRecordCorrect(extraData: {
      'slot_index': index,
      'turn_in_round': _turnsInRound,
      'waited_for_turn': true,
    });

    // Notify Flutter layer of correct child turn (for haptic feedback)
    onCorrectMatch?.call();

    if (_turnStartTime != null) {
      _totalResponseTimeMs +=
          DateTime.now().difference(_turnStartTime!).inMilliseconds;
    }

    for (final s in _slots) {
      s.inputEnabled = false;
    }

    // Check if round complete
    if (_checkRoundComplete()) return;

    // Back to buddy
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!isMounted) return;
      _startBuddyTurn();
    });
  }

  bool _checkRoundComplete() {
    final allFilled = _slots.every((s) => s.isFilled);
    if (!allFilled) return false;

    _currentRound++;
    onStepChanged(_currentRound);

    // Complete round
    analyticsCompleteRound(successful: true);
    analyticsAddRoundData('early_taps_in_round', _earlyTaps);
    analyticsAddRoundData('turns_taken', _turnsInRound);

    if (_currentRound >= totalRounds) {
      // Game complete — play game complete SFX and celebration VO
      onPlayGameCompleteSfx?.call();
      onPlayCelebrationVo?.call();

      analyticsMarkCompleted();
      analyticsCompleteSession();

      // Add game-specific metrics for XGBoost
      analyticsAddGameSpecificMetric('early_taps_total', _earlyTaps);
      analyticsAddGameSpecificMetric('avg_response_time_ms',
        _totalResponseTimeMs / (_score > 0 ? _score : 1));
      analyticsAddGameSpecificMetric('impulse_control_score',
        _earlyTaps == 0 ? 1.0 : 1.0 - (_earlyTaps / (_score + _earlyTaps)).clamp(0.0, 1.0));
      analyticsAddGameSpecificMetric('turn_completion_rate',
        _score / (totalRounds * (_slotsPerRound ~/ 2)));

      Future.delayed(const Duration(milliseconds: 600), () {
        onGameComplete(
          score: _score,
          totalItems: totalRounds * (_slotsPerRound ~/ 2), // child's slots
          errorCount: _errorCount,
          totalResponseTimeMs: _totalResponseTimeMs,
          extras: {'early_taps': _earlyTaps},
          analytics: analyticsSession,
        );
      });
    } else {
      // Level/round complete — play level complete SFX and transition VO
      onPlayLevelCompleteSfx?.call();
      onPlayTransitionVo?.call();

      Future.delayed(const Duration(milliseconds: 800), _setupRound);
    }
    return true;
  }

  @override
  void render(Canvas canvas) {
    // Turn indicator
    final text = _isBuddyTurn ? "🐻 Buddy's turn…" : '⭐ Your turn!';
    final color = _isBuddyTurn
        ? const Color(0xFF9B82C4)
        : const Color(0xFF5DAF8E);
    final fontSize = (size.x * 0.04).clamp(16.0, 28.0);

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.x / 2 - tp.width / 2, 12));

    super.render(canvas);
  }
}
