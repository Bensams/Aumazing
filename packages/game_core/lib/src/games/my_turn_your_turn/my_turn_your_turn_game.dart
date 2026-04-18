import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart';

import 'package:shared_ui/shared_ui.dart';
import 'components/turn_slot.dart';

/// My Turn, Your Turn — a turn-taking game with a virtual buddy.
///
/// The app and child alternate placing shapes on a grid.
/// Measures impulse control (early taps), waiting, and completion.
class MyTurnYourTurnGame extends FlameGame with TapCallbacks {
  MyTurnYourTurnGame({
    required this.totalRounds,
    required this.onStepChanged,
    required this.onGameComplete,
    required this.onTurnChanged,
  });

  final int totalRounds;
  final void Function(int currentStep) onStepChanged;
  final void Function({
    required int score,
    required int totalItems,
    required int errorCount,
    required int totalResponseTimeMs,
    required Map<String, dynamic> extras,
  }) onGameComplete;

  /// Notify Flutter layer: true = buddy's turn, false = child's turn
  final void Function(bool isBuddyTurn) onTurnChanged;

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
    _setupRound();
  }

  void _setupRound() {
    for (final s in _slots) {
      s.removeFromParent();
    }
    _slots.clear();
    _turnsInRound = 0;

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
    _turnStartTime = DateTime.now();

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
      slot.showEarlyTapWarning();
      return;
    }

    // Child's turn — fill the slot
    final rng = math.Random();
    final color = _childColors[rng.nextInt(_childColors.length)];
    slot.fillByChild(color);
    _turnsInRound++;
    _score++;

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

    if (_currentRound >= totalRounds) {
      Future.delayed(const Duration(milliseconds: 600), () {
        onGameComplete(
          score: _score,
          totalItems: totalRounds * (_slotsPerRound ~/ 2), // child's slots
          errorCount: _errorCount,
          totalResponseTimeMs: _totalResponseTimeMs,
          extras: {'early_taps': _earlyTaps},
        );
      });
    } else {
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
