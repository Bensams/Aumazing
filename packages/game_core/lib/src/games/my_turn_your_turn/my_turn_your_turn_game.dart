import 'dart:async';
import 'dart:math' as math;

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart';

import 'components/game_piece.dart';
import 'components/turn_slot.dart';
import '../shared/answer_label.dart';
import '../shared/ghost_hand.dart';
import '../../analytics/enhanced_analytics_mixin.dart';
import '../../analytics/models/models.dart';
import '../../config/adaptive_difficulty.dart';
import '../../config/difficulty_profile.dart';
import '../shared/game_layout.dart';
import '../../automation/developer_automation.dart';
import '../shared/game_lifecycle_guard.dart';

/// My Turn, Your Turn — a turn-taking game with a virtual buddy.
///
/// Layout: the buddy's pieces sit in a tray on the LEFT and glide into a chosen
/// slot on the buddy's turn; the child's pieces (their chosen avatar) sit in a
/// tray on the RIGHT and are placed into slots on the child's turn — by tapping
/// a piece then a slot, or by dragging a piece onto a slot. Measures impulse
/// control (early taps), waiting, and completion.
class MyTurnYourTurnGame extends FlameGame
    with
        GameLifecycleGuard,
        TapCallbacks,
        DragCallbacks,
        EnhancedGameplayAnalyticsMixin,
        DeveloperAutomationHooks {
  MyTurnYourTurnGame({
    required this.totalRounds,
    required this.onStepChanged,
    required this.onGameComplete,
    required this.onTurnChanged,
    required this.childId,
    this.avatar = '⭐',
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
    // Game-specific: turn-taking phase voice-overs
    this.onPlayMyTurnVo,
    this.onPlayYourTurnVo,
    this.onPlayWaitVo,
  });

  final int totalRounds;
  final String childId;
  final String? gameVersion;

  /// The child's chosen avatar emoji (from their profile). Shown on the child's
  /// pieces and filled slots instead of a generic star.
  final String avatar;

  final void Function(int currentStep) onStepChanged;
  final void Function({
    required int score,
    required int totalItems,
    required int errorCount,
    required int totalResponseTimeMs,
    required Map<String, dynamic> extras,
    GameSessionMetrics? analytics,
  })
  onGameComplete;

  /// Notify Flutter layer: true = buddy's turn, false = child's turn
  final void Function(bool isBuddyTurn) onTurnChanged;

  /// Optional callback fired on each correct child turn (for haptics).
  final void Function()? onCorrectMatch;

  /// Optional callback fired when the child taps out of turn, alongside the
  /// wrong SFX and the encouraging voice line. The Flutter layer uses it for
  /// the mascot's reaction, so the character answers a mistake the same way
  /// the audio does.
  final void Function()? onWrongAnswer;

  // ── Audio event callbacks ────────────────────────────────────────────
  final VoidCallback? onPlayCorrectSfx;
  final VoidCallback? onPlayWrongSfx;
  final VoidCallback? onPlayTapSfx;
  final VoidCallback? onPlayDragSfx;
  final VoidCallback? onPlayDropSfx;
  final VoidCallback? onPlayLevelCompleteSfx;
  final VoidCallback? onPlayGameCompleteSfx;

  /// Immediate feedback on a correct turn. Taking a turn in the right order
  /// is a sequence, not a thing with a name, so this always carries
  /// [AnswerLabel.none] and the app stays quiet — the drop SFX is the
  /// feedback. Praise waits for the end of the game.
  final AnswerLabelCallback? onPlayCorrectVo;
  final VoidCallback? onPlayWrongVo;
  final VoidCallback? onPlayInstructionVo;
  final VoidCallback? onPlayTransitionVo;
  final VoidCallback? onPlayCelebrationVo;
  final VoidCallback? onPlayMyTurnVo;
  final VoidCallback? onPlayYourTurnVo;

  /// "Please wait" cue that opens the buddy's turn. Awaited when it returns a
  /// Future so the buddy's move never auto-triggers in the middle of the cue
  /// (see [_startBuddyTurn]); a plain void callback simply proceeds at once.
  final FutureOr<void> Function()? onPlayWaitVo;

  // ── State ───────────────────────────────────────────────────────────
  int _currentRound = 0;
  int _score = 0;
  int _errorCount = 0;
  int _earlyTaps = 0;
  int _totalResponseTimeMs = 0;
  DateTime? _turnStartTime;

  final List<TurnSlot> _slots = [];
  final List<GamePiece> _buddyPieces = [];
  final List<GamePiece> _childPieces = [];
  GamePiece? _selectedPiece;

  bool _isBuddyTurn = true;
  int _turnsInRound = 0;
  static const _slotsPerRound = 6; // 3 buddy + 3 child
  int get _turnsPerSide => _slotsPerRound ~/ 2;

  final math.Random _rng = math.Random();

  Timer? _noResponseTimer;
  int _hintCount = 0;

  // ── Buddy-turn wait timing ───────────────────────────────────────────
  // Predictable, difficulty-based waits (replacing the old random 1–5s) so
  // every child gets a wait that is deliberately slow enough to practise
  // patience but never unpredictably short. Easier tiers wait longer.
  static const _buddyWaitEasyMs = 6000; // Easy: most patience-building
  static const _buddyWaitMediumMs = 5000;
  static const _buddyWaitHardMs = 4000;
  // Assessment uses a single fixed wait so its impulse-control telemetry stays
  // comparable across children and never adapts to performance.
  static const _buddyWaitAssessmentMs = 5000;
  // A one-off, bounded per-round grace added to the buddy wait after an early
  // tap — extra settling time for a child who jumped. Practice only, so it
  // never changes the fixed assessment interval.
  static const _earlyTapWaitBonusMs = 2000;
  // Floor for the idle "your turn" reminder so a child always gets a
  // reasonable window to process before being nudged. Longer tiers are kept.
  static const _reminderFloorMs = 10000;

  /// Seconds left on the current buddy wait, counted down in [update] so it
  /// pauses/resumes with the Flame engine (a raw Timer would keep running
  /// while paused). `null` means no wait is in flight.
  double? _buddyWaitRemaining;

  /// Bumped whenever a buddy wait is (re)started or cancelled so a stale voice
  /// cue completing after a teardown/round change cannot start a countdown.
  int _buddyWaitToken = 0;

  /// Extra buddy-wait time granted for the rest of this round after an early
  /// tap (bounded to a single [_earlyTapWaitBonusMs]); reset every round.
  int _roundWaitBonusMs = 0;

  /// True for the assessment profile: it disables adaptive stepping so its
  /// telemetry stays comparable, and here it also pins a fixed buddy wait and
  /// suppresses the early-tap grace.
  bool get _isAssessment => !profile.adaptiveSteppingEnabled;

  /// The buddy wait for the current turn: a fixed interval in assessment, or a
  /// difficulty-based interval (plus any earned early-tap grace) in practice.
  int get _buddyWaitMs {
    if (_isAssessment) return _buddyWaitAssessmentMs;
    final base = switch (profile.level) {
      1 => _buddyWaitEasyMs,
      3 => _buddyWaitHardMs,
      _ => _buddyWaitMediumMs,
    };
    return base + _roundWaitBonusMs;
  }

  /// Hint/guidance policy for the selected difficulty tier (ABA prompt
  /// hierarchy - see [DifficultyProfile]).
  final DifficultyProfile profile;

  // Difficulty-tier hint state (see DifficultyProfile).
  int _hintsUsedThisRound = 0;
  int _consecutiveIdleHints = 0;
  GhostHand? _ghostHand;

  /// Within-round adaptive stepping: 2 consecutive errors temporarily step
  /// the tier down (more support) for the remainder of the round.
  late final AdaptiveDifficulty _adaptive = AdaptiveDifficulty(profile);

  /// The tier in effect right now (base, or one step easier after struggles).
  DifficultyProfile get _tier => _adaptive.effective;

  bool get _hintBudgetLeft =>
      _tier.unlimitedHints || _hintsUsedThisRound < (_tier.hintsPerRound ?? 0);

  // True colors (not pastels): buddy pieces are real blue, the child's are
  // real green, so "whose turn" reads instantly and matches natural colors.
  static const Color _buddyColor = Color(0xFF1E88E5);
  static const Color _childColor = Color(0xFF43A047);

  /// Pool of buddy avatar candidates (matches the child avatar set).
  static const _avatarPool = ['🐻', '🐼', '🦊', '🐨', '🐸', '🦄', '🐙', '🐰'];

  /// Buddy's avatar — picked once at load from [_avatarPool], always different
  /// from the child's avatar so the two players are easy to tell apart.
  String _buddyEmoji = '🐻';

  @override
  Color backgroundColor() => const Color(0x00000000);

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Pick a buddy avatar that differs from the child's chosen avatar.
    final buddyOptions = _avatarPool.where((e) => e != avatar).toList()
      ..shuffle(_rng);
    if (buddyOptions.isNotEmpty) _buddyEmoji = buddyOptions.first;

    analyticsInitialize(
      gameId: 'my_turn_your_turn',
      childId: childId,
      totalRounds: totalRounds,
      gameVersion: gameVersion ?? '1.0.0',
    );
    analyticsStartSession();
    onPlayInstructionVo?.call();
    _setupRound();
  }

  void _setupRound() {
    _cancelNoResponseTimer();
    _cancelBuddyWait();
    _roundWaitBonusMs = 0;
    for (final s in _slots) {
      s.removeFromParent();
    }
    for (final p in [..._buddyPieces, ..._childPieces]) {
      p.removeFromParent();
    }
    _slots.clear();
    _buddyPieces.clear();
    _childPieces.clear();
    _selectedPiece = null;
    _turnsInRound = 0;
    _hintCount = 0;
    _hintsUsedThisRound = 0;
    _consecutiveIdleHints = 0;
    _adaptive.startRound(); // any step-down only lasts one round

    analyticsStartRound(roundNumber: _currentRound + 1);
    analyticsAddRoundData('slots_per_round', _slotsPerRound);
    analyticsAddRoundData('child_turns_per_round', _turnsPerSide);

    final gameW = size.x;
    final gameH = size.y;

    // Centre slot grid (leaves side margins for the two trays).
    const cols = 3;
    const rows = 2;
    final centreLeft = gameW * 0.20;
    final centreW = gameW * 0.60;
    final availH = gameH - kTopOverlayBand;
    var cardSize = math.min(centreW / (cols + 0.4), gameH / (rows + 1.2));
    final rowSpan = rows + (rows - 1) * 0.18;
    if (rowSpan * cardSize > availH) cardSize = availH / rowSpan;
    final gap = cardSize * 0.18;
    final gridW = cols * cardSize + (cols - 1) * gap;
    final gridH = rows * cardSize + (rows - 1) * gap;
    final startX = centreLeft + (centreW - gridW) / 2;
    final startY = kTopOverlayBand + (gameH - kTopOverlayBand - gridH) / 2;

    for (var i = 0; i < _slotsPerRound; i++) {
      final col = i % cols;
      final row = i ~/ cols;
      final slot = TurnSlot(
        slotIndex: i,
        onTapped: _onSlotTapped,
        onTappedWhileDisabled: _onSlotTappedWhileDisabled,
        position: Vector2(
          startX + col * (cardSize + gap),
          startY + row * (cardSize + gap),
        ),
        size: Vector2.all(cardSize),
      );
      _slots.add(slot);
      add(slot);
    }

    // Side trays: centre-anchored tokens stacked in the area BELOW the top bar
    // so the top piece never overlaps the Retry/Menu/Lock icons.
    final trayTop = gameH * 0.18;
    final trayAvailH = gameH * 0.72;
    final slotH = trayAvailH / _turnsPerSide;
    final pieceSize = math.min(cardSize * 0.8, slotH * 0.82);

    for (var i = 0; i < _turnsPerSide; i++) {
      final y = trayTop + slotH * i + slotH / 2;
      final buddy = GamePiece(
        emoji: _buddyEmoji,
        color: _buddyColor,
        isChild: false,
        position: Vector2(gameW * 0.09, y),
        size: Vector2.all(pieceSize),
      );
      _buddyPieces.add(buddy);
      add(buddy);

      final child = GamePiece(
        emoji: avatar,
        color: _childColor,
        isChild: true,
        onTapped: _onChildPieceTapped,
        onPickedUp: _onChildPiecePickedUp,
        onDragEnded: _onChildPieceDragEnded,
        position: Vector2(gameW * 0.91, y),
        size: Vector2.all(pieceSize),
      );
      _childPieces.add(child);
      add(child);
    }

    _startBuddyTurn();
  }

  // ── Buddy's turn ─────────────────────────────────────────────────────

  Future<void> _startBuddyTurn() async {
    _isBuddyTurn = true;
    _cancelNoResponseTimer();
    _cancelBuddyWait();
    onTurnChanged(true);

    for (final s in _slots) {
      s.inputEnabled = false;
    }
    for (final p in _childPieces) {
      p.interactive = false;
    }

    onPlayMyTurnVo?.call();

    // Cue-safe start: hold the countdown until the "please wait" line finishes
    // (when the callback reports completion) so the buddy never moves in the
    // middle of the cue. A synchronous/void callback just proceeds at once.
    final token = ++_buddyWaitToken;
    final lifeToken = lifecycleToken;
    final cue = onPlayWaitVo?.call();
    if (cue is Future) await cue;
    if (!isLifecycleTokenValid(lifeToken) ||
        token != _buddyWaitToken ||
        !isMounted ||
        !_isBuddyTurn) {
      return;
    }

    // Predictable, difficulty-based wait, counted down in [update] so it
    // pauses and resumes with the engine.
    final waitMs = _buddyWaitMs;
    analyticsAddRoundData('buddy_turn_delay_ms', waitMs);
    _buddyWaitRemaining = waitMs / 1000.0;
  }

  /// Stops any in-flight buddy wait and invalidates pending cue completions.
  void _cancelBuddyWait() {
    _buddyWaitRemaining = null;
    _buddyWaitToken++;
  }

  @override
  void update(double dt) {
    super.update(dt);
    final remaining = _buddyWaitRemaining;
    if (remaining != null) {
      final next = remaining - dt;
      if (next <= 0) {
        _buddyWaitRemaining = null;
        _buddyPlays();
      } else {
        _buddyWaitRemaining = next;
      }
    }
  }

  void _buddyPlays() {
    final emptySlots = _slots.where((s) => !s.isFilled).toList();
    if (emptySlots.isEmpty || _buddyPieces.isEmpty) return;

    final slot = emptySlots[_rng.nextInt(emptySlots.length)];
    final piece = _buddyPieces.removeLast();
    onPlayDragSfx?.call();

    piece.moveToTarget(
      slot.position + slot.size / 2,
      onDone: () {
        if (!isMounted) return;
        piece.removeFromParent();
        slot.fill(color: _buddyColor, emoji: _buddyEmoji, isBuddy: true);
        onPlayDropSfx?.call();
        _turnsInRound++;
        if (_checkRoundComplete()) return;
        Future.delayed(const Duration(milliseconds: 400), () {
          if (isMounted) _startChildTurn();
        });
      },
    );
  }

  // ── Child's turn ─────────────────────────────────────────────────────

  void _startChildTurn() {
    _isBuddyTurn = false;
    onTurnChanged(false);
    onPlayYourTurnVo?.call();
    _turnStartTime = DateTime.now();

    analyticsShowStimulus();
    analyticsRecordPrompt(promptType: 'your_turn_indicator');

    for (final s in _slots) {
      s.inputEnabled = true;
    }
    for (final p in _childPieces) {
      p.interactive = true;
    }

    _startNoResponseTimer();
  }

  void _onChildPieceTapped(GamePiece piece) {
    if (_isBuddyTurn) return;
    _cancelNoResponseTimer();
    for (final p in _childPieces) {
      if (p != piece) p.deselect();
    }
    _selectedPiece = piece;
    piece.select();
    onPlayTapSfx?.call();
    _startNoResponseTimer();
  }

  void _onChildPiecePickedUp(GamePiece piece) {
    _cancelNoResponseTimer();
    _hideVisualHints();
    for (final p in _childPieces) {
      if (p != piece) p.deselect();
    }
    _selectedPiece = piece;
    onPlayDragSfx?.call();
  }

  /// Child drops a dragged piece — place it if it landed on an empty slot.
  void _onChildPieceDragEnded(GamePiece piece, Vector2 dropCenter) {
    if (_isBuddyTurn) {
      piece.returnHome();
      return;
    }
    TurnSlot? target;
    for (final s in _slots) {
      if (!s.isFilled && s.containsPoint(dropCenter)) {
        target = s;
        break;
      }
    }
    if (target == null) {
      piece.returnHome();
      _startNoResponseTimer();
      return;
    }
    _placeChildPiece(piece, target);
  }

  /// Child taps a slot — place the selected piece (or the next available one).
  void _onSlotTapped(int index) {
    if (_isBuddyTurn) return;
    final slot = _slots[index];
    if (slot.isFilled) return;
    final piece =
        _selectedPiece ?? (_childPieces.isNotEmpty ? _childPieces.first : null);
    if (piece == null) return;
    _placeChildPiece(piece, slot);
  }

  void _placeChildPiece(GamePiece piece, TurnSlot slot) {
    _cancelNoResponseTimer();
    _selectedPiece = null;
    _childPieces.remove(piece);

    for (final s in _slots) {
      s.inputEnabled = false;
    }
    for (final p in _childPieces) {
      p.interactive = false;
    }

    onPlayDragSfx?.call();
    piece.moveToTarget(
      slot.position + slot.size / 2,
      onDone: () {
        if (!isMounted) return;
        piece.removeFromParent();
        slot.fill(color: _childColor, emoji: avatar, isBuddy: false);
        _turnsInRound++;
        _score++;

        onPlayDropSfx?.call();
        onPlayCorrectSfx?.call();
        onPlayCorrectVo?.call(AnswerLabel.none);
        onCorrectMatch?.call();

        _adaptive.recordCorrect();
        _consecutiveIdleHints = 0;

        analyticsRecordValidAction();
        analyticsRecordCorrect(
          extraData: {
            'slot_index': slot.slotIndex,
            'turn_in_round': _turnsInRound,
            'waited_for_turn': true,
          },
        );
        if (_turnStartTime != null) {
          _totalResponseTimeMs += DateTime.now()
              .difference(_turnStartTime!)
              .inMilliseconds;
        }

        if (_checkRoundComplete()) return;
        Future.delayed(const Duration(milliseconds: 400), () {
          if (isMounted) _startBuddyTurn();
        });
      },
    );
  }

  /// A slot tapped while input is disabled (buddy's turn) → impulse-control error.
  void _onSlotTappedWhileDisabled(int index) {
    final slot = _slots[index];
    _earlyTaps++;
    _errorCount++;

    // Adaptive stepping: repeated impulse errors step the tier down (more
    // support) for the rest of this round.
    if (_adaptive.recordError()) {
      analyticsAddRoundData('difficulty_step_down', _tier.level);
    }

    onPlayWrongSfx?.call();
    onPlayWrongVo?.call();
    onWrongAnswer?.call();
    analyticsRecordOffTaskAction(actionType: 'early_tap_slot_buddy_turn');
    analyticsRecordWrong(
      extraData: {
        'error_type': 'impulse_control',
        'turn_phase': 'buddy_turn',
        'tap_target': 'slot',
        'slot_index': index,
      },
    );
    slot.showEarlyTapWarning();

    // Practice only: give the child a little extra settling time for the rest
    // of this round after they jump. Bounded to one grace so the wait can
    // never stack indefinitely, and never applied in assessment so its fixed
    // interval stays comparable. Also stretch the wait already in flight so
    // the child benefits on the very turn they jumped.
    if (!_isAssessment && _roundWaitBonusMs == 0) {
      _roundWaitBonusMs = _earlyTapWaitBonusMs;
      if (_buddyWaitRemaining != null) {
        _buddyWaitRemaining =
            _buddyWaitRemaining! + _earlyTapWaitBonusMs / 1000.0;
      }
    }
  }

  bool _checkRoundComplete() {
    final allFilled = _slots.every((s) => s.isFilled);
    if (!allFilled) return false;

    _cancelNoResponseTimer();
    _currentRound++;
    onStepChanged(_currentRound);

    analyticsCompleteRound(successful: true);
    analyticsAddRoundData('early_taps_in_round', _earlyTaps);
    analyticsAddRoundData('turns_taken', _turnsInRound);

    if (_currentRound >= totalRounds) {
      if (!tryBeginCompletion()) return true;
      onPlayGameCompleteSfx?.call();
      onPlayCelebrationVo?.call();

      analyticsMarkCompleted();
      analyticsCompleteSession();
      analyticsAddGameSpecificMetric('early_taps_total', _earlyTaps);
      analyticsAddGameSpecificMetric('hint_count', _hintCount);
      analyticsAddGameSpecificMetric(
        'avg_response_time_ms',
        _totalResponseTimeMs / (_score > 0 ? _score : 1),
      );
      analyticsAddGameSpecificMetric(
        'impulse_control_score',
        _earlyTaps == 0
            ? 1.0
            : 1.0 - (_earlyTaps / (_score + _earlyTaps)).clamp(0.0, 1.0),
      );
      analyticsAddGameSpecificMetric(
        'turn_completion_rate',
        _score / (totalRounds * _turnsPerSide),
      );

      guardedDelay(const Duration(milliseconds: 600), () {
        onGameComplete(
          score: _score,
          totalItems: totalRounds * _turnsPerSide,
          errorCount: _errorCount,
          totalResponseTimeMs: _totalResponseTimeMs,
          extras: {'early_taps': _earlyTaps},
          analytics: analyticsSession,
        );
      });
    } else {
      onPlayLevelCompleteSfx?.call();
      onPlayTransitionVo?.call();
      Future.delayed(const Duration(milliseconds: 800), _setupRound);
    }
    return true;
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    analyticsRecordTouch(
      Offset(event.canvasPosition.x, event.canvasPosition.y),
      isValid: event.handled,
    );
  }

  // ── Idle timer / hint ────────────────────────────────────────────────

  void _startNoResponseTimer() {
    _cancelNoResponseTimer();
    // Hard tier (or a spent Medium budget) waits longer and re-orients with
    // the "your turn" VO instead of revealing a slot.
    final tierDelay = (_tier.noHints || !_hintBudgetLeft)
        ? _tier.reorientDelay
        : _tier.idleHintDelay;
    // Never nudge before a reasonable processing floor: a reminder that lands
    // too soon reads as impatience. Longer tiers (e.g. the 20s re-orient) are
    // kept as-is; only the short 5s/8s idle hints are floored up to 10s. This
    // stays a reminder, not a failure — no round ever ends on this timer.
    final delayMs = tierDelay.inMilliseconds < _reminderFloorMs
        ? _reminderFloorMs
        : tierDelay.inMilliseconds;
    final delay = Duration(milliseconds: delayMs);
    _noResponseTimer = Timer(delay, () {
      if (!isMounted || _isBuddyTurn) return;
      _showVisualGuide();
    });
  }

  void _cancelNoResponseTimer() {
    _noResponseTimer?.cancel();
    _noResponseTimer = null;
    _hideVisualHints();
  }

  void _showVisualGuide() {
    final emptySlots = _slots.where((s) => !s.isFilled).toList();
    if (emptySlots.isEmpty) return;

    // No answer hints available (Hard, or Medium budget spent): re-play the
    // "your turn" cue to re-orient attention, but never reveal a slot.
    if (_tier.noHints || !_hintBudgetLeft) {
      onPlayYourTurnVo?.call();
      analyticsRecordHint(hintType: 'reorient_instruction');
      _startNoResponseTimer();
      return;
    }

    _consecutiveIdleHints++;

    final targetSlot = emptySlots.first;
    targetSlot.showHint();
    _hintCount++;
    _hintsUsedThisRound++;
    analyticsRecordHint(hintType: 'idle_visual_guide');
    analyticsRecordPrompt(promptType: 'visual_guide_idle_slot');

    // Easy tier: still idle after a slot hint -> ghost hand demonstrates
    // dragging a tray piece into the highlighted slot.
    if (_tier.guidedDemo &&
        _consecutiveIdleHints >= 2 &&
        _childPieces.isNotEmpty) {
      _showDragDemo(_childPieces.first, targetSlot);
    }

    Future.delayed(const Duration(seconds: 3), () {
      if (!isMounted) return;
      targetSlot.hideHint();
      if (!_isBuddyTurn) _startNoResponseTimer();
    });
  }

  /// Ghost-hand demo dragging [piece] from the tray into [slot] (Easy tier).
  void _showDragDemo(GamePiece piece, TurnSlot slot) {
    _ghostHand?.removeFromParent(); // never more than one demo at a time
    final hand = GhostHand.drag(
      from: piece.position + piece.size / 2,
      to: slot.position + slot.size / 2,
      handSize: piece.size.x * 0.8,
    );
    _ghostHand = hand;
    add(hand);
    analyticsRecordHint(hintType: 'gesture_demo');
  }

  void _hideVisualHints() {
    for (final s in _slots) {
      s.hideHint();
    }
  }

  @override
  void onRemove() {
    _cancelNoResponseTimer();
    _cancelBuddyWait();
    super.onRemove();
  }

  // The turn label is not drawn on the canvas: the screen shows it in the
  // upper-left VoiceOverPromptBubble via onTurnChanged.

  // ── Developer auto-play ─────────────────────────────

  /// Ready only on the child's turn with a free slot and a piece to place.
  /// Waiting through the buddy's turn is the skill this game measures, so
  /// automation waits it out rather than tapping early — an early tap here
  /// would be recorded as an impulse-control error.
  @override
  bool get debugAwaitingInputImpl =>
      !_isBuddyTurn &&
      _childPieces.isNotEmpty &&
      _slots.any((s) => !s.isFilled && s.inputEnabled);

  /// Taps the first free slot, which places the child's next piece through
  /// the same handler a real tap uses.
  @override
  void debugPerformCorrectActionImpl() {
    final index = _slots.indexWhere((s) => !s.isFilled && s.inputEnabled);
    if (index < 0) return;
    _onSlotTapped(index);
  }
}
