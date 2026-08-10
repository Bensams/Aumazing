import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:shared_ui/shared_ui.dart';

import 'components/routine_card.dart';
import 'components/sequence_slot.dart';
import 'routine_steps.dart';
import '../shared/game_layout.dart';
import '../../analytics/enhanced_analytics_mixin.dart';
import '../../analytics/models/models.dart';
import '../../config/adaptive_difficulty.dart';
import '../../config/difficulty_profile.dart';

/// The core Flame game for "Ano'ng Susunod?" (What's Next?).
///
/// The child puts the steps of an everyday routine into order. It is the app's
/// most direct expression of TEACCH: a visual schedule — the central TEACCH
/// support — turned into an assessable task. Because the routines are ones the
/// child already lives through, it doubles as a functional-skills intervention
/// rather than an abstract ordering puzzle.
///
/// Interaction is **tap-to-select, then tap-a-slot**. Dragging is deliberately
/// not the only path: at 2–6, and especially with motor-planning differences,
/// a drag that is released a few pixels early reads as a failure the child did
/// not make. Two taps cannot be dropped.
///
/// Three decisions worth keeping if this is ever refactored:
///
/// * **The tray is shuffled every round.** Presenting steps in canonical order
///   lets a child score full marks by always taking the leftmost card, which
///   measures nothing. The shuffle is what makes the accuracy number mean
///   anything at all.
/// * **A wrong placement never ends the round.** The card returns to the tray,
///   a retry is recorded, and the prompt hierarchy escalates — highlight at two
///   wrong attempts, place it for them at four. The routine always completes.
/// * **On the hardest tier the child may place cards in the wrong order**, and
///   the first complete ordering is scored before any correction. That is the
///   only reason `sequence_distance` can be non-zero: a child who is one swap
///   away from right is not the same as one who is random, and no other game
///   in the app can tell those apart.
class AnongSusunodGame extends FlameGame
    with TapCallbacks, EnhancedGameplayAnalyticsMixin {
  AnongSusunodGame({
    required this.onStepChanged,
    required this.onGameComplete,
    required this.childId,
    this.totalRounds = 4,
    this.gameVersion,
    this.profile = DifficultyProfile.medium,
    this.strings = const AppStrings(GameLanguage.english),
    this.onCorrectPlacement,
    this.onWrongAnswer,
    this.onPlayCorrectSfx,
    this.onPlayWrongSfx,
    this.onPlayTapSfx,
    this.onPlayLevelCompleteSfx,
    this.onPlayGameCompleteSfx,
    this.onPlayCorrectVo,
    this.onPlayWrongVo,
    this.onPlayInstructionVo,
    this.onPlayTransitionVo,
    this.onPlayCelebrationVo,
  });

  final void Function(int currentStep) onStepChanged;
  final void Function({
    required int score,
    required int totalItems,
    required int errorCount,
    required int totalResponseTimeMs,
    required Map<String, dynamic> extras,
    GameSessionMetrics? analytics,
  }) onGameComplete;

  final void Function()? onCorrectPlacement;
  final void Function()? onWrongAnswer;

  final VoidCallback? onPlayCorrectSfx;
  final VoidCallback? onPlayWrongSfx;
  final VoidCallback? onPlayTapSfx;
  final VoidCallback? onPlayLevelCompleteSfx;
  final VoidCallback? onPlayGameCompleteSfx;
  final VoidCallback? onPlayCorrectVo;
  final VoidCallback? onPlayWrongVo;
  final VoidCallback? onPlayInstructionVo;
  final VoidCallback? onPlayTransitionVo;
  final VoidCallback? onPlayCelebrationVo;

  final int totalRounds;
  final String childId;
  final String? gameVersion;
  final DifficultyProfile profile;

  /// Localized strings (English / Tagalog / Cebuano) for on-screen labels.
  final AppStrings strings;

  // ── Session totals ───────────────────────────────────────────────────
  int _currentRound = 0;
  int _score = 0;
  int _errorCount = 0;
  int _totalResponseTimeMs = 0;
  int _retryCount = 0;
  int _hintCount = 0;
  int _selfCorrections = 0;
  int _promptedPlacements = 0;
  int _sequenceDistanceTotal = 0;
  int _totalPlacementsRequired = 0;

  // ── Round state ──────────────────────────────────────────────────────
  final List<SequenceSlot> _slots = [];
  final List<RoutineCard> _tray = [];
  RoutineCard? _selected;
  DateTime? _slotStart;
  int _hintsUsedThisRound = 0;
  final Map<int, int> _wrongPerSlot = {};

  /// The child's first complete ordering, captured before any correction.
  List<String>? _firstOrdering;

  Timer? _idleTimer;
  Timer? _advanceTimer;

  late final AdaptiveDifficulty _adaptive = AdaptiveDifficulty(profile);
  DifficultyProfile get _tier => _adaptive.effective;

  bool get _hintBudgetLeft =>
      _tier.unlimitedHints || _hintsUsedThisRound < (_tier.hintsPerRound ?? 0);

  final math.Random _random = math.Random();

  Routine get _routine => kRoutines[_currentRound % kRoutines.length];

  /// How many slots the tier exposes (Easy uses a 3-step routine).
  int get _slotCount => _tier.level == 1 ? 3 : 4;

  /// How many of those the child fills themselves.
  int get _placementsThisRound {
    switch (_tier.level) {
      case 1:
        return 1; // two pre-placed, choose the last
      case 3:
        return 4; // all scrambled
      default:
        return 3; // first pre-placed
    }
  }

  /// Whether the tier lets the child seat a card in a slot it does not belong
  /// in. Only the hardest tier does; it is what makes real ordering possible.
  bool get _freePlacement => _tier.level >= 3;

  // ── Lifecycle ────────────────────────────────────────────────────────

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    analyticsInitialize(
      gameId: 'anong_susunod',
      childId: childId,
      totalRounds: totalRounds,
      gameVersion: gameVersion,
    );
    analyticsStartSession();

    onPlayInstructionVo?.call();
    _startRound();
  }

  @override
  void onGameResize(Vector2 newSize) {
    super.onGameResize(newSize);
    if (_slots.isNotEmpty) _layout();
  }

  @override
  void onRemove() {
    _idleTimer?.cancel();
    _advanceTimer?.cancel();
    super.onRemove();
  }

  // ── Round setup ──────────────────────────────────────────────────────

  void _startRound() {
    for (final s in _slots) {
      s.removeFromParent();
    }
    for (final c in _tray) {
      c.removeFromParent();
    }
    _slots.clear();
    _tray.clear();
    _selected = null;
    _wrongPerSlot.clear();
    _hintsUsedThisRound = 0;
    _firstOrdering = null;
    _adaptive.startRound();

    analyticsStartRound(roundNumber: _currentRound + 1);

    final steps = _routine.steps.take(_slotCount).toList();

    for (var i = 0; i < _slotCount; i++) {
      final slot = SequenceSlot(index: i, position: Vector2.zero(), size: Vector2.all(1));
      _slots.add(slot);
      add(slot);
    }

    // Pre-place the leading steps the tier hands the child for free.
    final presetCount = _slotCount - _placementsThisRound;
    for (var i = 0; i < presetCount; i++) {
      _slots[i]
        ..filled = steps[i]
        ..preset = true;
    }

    // Remaining steps go to the tray, SHUFFLED. Without this the correct card
    // is always the leftmost one and the whole task collapses.
    final remaining = steps.sublist(presetCount).toList()..shuffle(_random);
    for (final step in remaining) {
      final card = RoutineCard(
          step: step, position: Vector2.zero(), size: Vector2.all(1));
      _tray.add(card);
      add(card);
    }

    _totalPlacementsRequired += _placementsThisRound;
    _slotStart = DateTime.now();
    _layout();
    _armIdle();
    analyticsShowStimulus();
  }

  /// Lays slots across the upper band and the tray beneath, sized to whatever
  /// canvas we were handed. Everything sits below [kTopOverlayBand] so the
  /// Flutter overlay never eats a touch meant for a card.
  void _layout() {
    if (size.x <= 0 || size.y <= 0) return;

    final usableTop = kTopOverlayBand + 8;
    final usableHeight = size.y - usableTop - 12;

    final slotH = usableHeight * 0.52;
    final slotW = math.min(slotH * 0.86, (size.x - 40) / _slotCount - 18);
    final gap = math.min(28.0, slotW * 0.34);
    final rowW = _slotCount * slotW + (_slotCount - 1) * gap;
    final startX = (size.x - rowW) / 2 + slotW / 2;
    final slotY = usableTop + slotH / 2;

    for (var i = 0; i < _slots.length; i++) {
      _slots[i]
        ..position = Vector2(startX + i * (slotW + gap), slotY)
        ..size = Vector2(slotW, slotH);
    }

    final cardH = usableHeight * 0.36;
    final cardW = math.min(cardH * 0.94, (size.x - 60) / math.max(_tray.length, 1) - 16);
    final trayGap = math.min(24.0, cardW * 0.3);
    final trayW = _tray.length * cardW + math.max(_tray.length - 1, 0) * trayGap;
    final trayStartX = (size.x - trayW) / 2 + cardW / 2;
    final trayY = usableTop + slotH + 14 + cardH / 2;

    for (var i = 0; i < _tray.length; i++) {
      _tray[i]
        ..position = Vector2(trayStartX + i * (cardW + trayGap), trayY)
        ..size = Vector2(cardW, cardH);
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    // Connector arrows between slots, drawn by the game so they sit under
    // nothing and never intercept a tap.
    for (var i = 0; i < _slots.length - 1; i++) {
      final a = _slots[i];
      final b = _slots[i + 1];
      SequenceSlot.drawArrow(
        canvas,
        Offset((a.position.x + a.size.x / 2 + b.position.x - b.size.x / 2) / 2,
            a.position.y),
        a.size.y,
      );
    }
  }

  // ── Input ────────────────────────────────────────────────────────────

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    final point = event.localPosition;

    // A card in the tray?
    for (final card in _tray) {
      if (!card.placed && card.containsLocal(point)) {
        _select(card);
        return;
      }
    }

    // A slot?
    for (final slot in _slots) {
      if (slot.containsLocal(point)) {
        _tapSlot(slot);
        return;
      }
    }

    // Empty canvas. Recorded so overall_invalid_touch_count reflects genuinely
    // undirected taps rather than mis-hits on real targets.
    analyticsRecordTouch(Offset(point.x, point.y), isValid: false);
    analyticsRecordOffTaskAction(actionType: 'tap_empty_canvas');
    _resetIdle();
  }

  void _select(RoutineCard card) {
    for (final c in _tray) {
      c.selected = false;
    }
    card.selected = true;
    _selected = card;
    onPlayTapSfx?.call();
    _resetIdle();
  }

  void _tapSlot(SequenceSlot slot) {
    final card = _selected;

    if (card == null) {
      // Tapping a slot with nothing picked up is not an error — it is a very
      // common way for a child to indicate "this one". Treat it as a request
      // for guidance rather than a mistake.
      analyticsRecordTouch(
          Offset(slot.position.x, slot.position.y), isValid: false);
      _resetIdle();
      return;
    }

    if (slot.preset) return;

    if (slot.filled != null) {
      // Moving a card out of a filled slot: a self-correction, which is a
      // genuinely good sign and is counted as such rather than as an error.
      if (_freePlacement) {
        _pullBack(slot);
      }
      return;
    }

    final correctHere = _routine.steps[slot.index].id == card.step.id;

    if (!correctHere && !_freePlacement) {
      _rejectPlacement(slot, card);
      return;
    }

    _seat(slot, card, prompted: false);
  }

  /// Returns a seated card to the tray so the child can rearrange it.
  void _pullBack(SequenceSlot slot) {
    final step = slot.filled;
    if (step == null) return;
    slot.filled = null;
    _selfCorrections++;
    analyticsAddRoundData('self_correction_slot_${slot.index}', true);
    for (final c in _tray) {
      if (c.step.id == step.id && c.placed) {
        c.placed = false;
        break;
      }
    }
    _layout();
    _resetIdle();
  }

  void _rejectPlacement(SequenceSlot slot, RoutineCard card) {
    _retryCount++;
    _errorCount++;
    _wrongPerSlot[slot.index] = (_wrongPerSlot[slot.index] ?? 0) + 1;

    analyticsRecordRetry();
    analyticsRecordWrong(extraData: {
      'slot': slot.index,
      'offered': card.step.id,
      'expected': _routine.steps[slot.index].id,
    });
    _adaptive.recordError();

    slot.rejecting = true;
    card.selected = false;
    _selected = null;

    onPlayWrongSfx?.call();
    onPlayWrongVo?.call();
    onWrongAnswer?.call();

    final wrongHere = _wrongPerSlot[slot.index] ?? 0;

    // ABA least-to-most: highlight at two, place it for them at four. The
    // child is never left stuck, and never loses the round.
    if (wrongHere == 2 && _hintBudgetLeft) {
      _hintCount++;
      _hintsUsedThisRound++;
      analyticsRecordHint(hintType: 'highlight_correct_card');
      _highlightCorrectFor(slot);
    } else if (wrongHere >= 4) {
      _hintCount++;
      _hintsUsedThisRound++;
      analyticsRecordHint(hintType: 'model_placement');
      final correct = _tray.firstWhere(
        (c) => !c.placed && c.step.id == _routine.steps[slot.index].id,
        orElse: () => _tray.first,
      );
      _seat(slot, correct, prompted: true);
    }

    _advanceTimer = Timer(const Duration(milliseconds: 600), () {
      slot.rejecting = false;
    });
    _resetIdle();
  }

  void _highlightCorrectFor(SequenceSlot slot) {
    final wanted = _routine.steps[slot.index].id;
    for (final c in _tray) {
      if (!c.placed && c.step.id == wanted) {
        c.hinted = true;
        _advanceTimer = Timer(const Duration(milliseconds: 1800), () {
          c.hinted = false;
        });
        return;
      }
    }
  }

  void _seat(SequenceSlot slot, RoutineCard card, {required bool prompted}) {
    final elapsed = _slotStart == null
        ? 0
        : DateTime.now().difference(_slotStart!).inMilliseconds;

    slot.filled = card.step;
    card
      ..placed = true
      ..selected = false
      ..hinted = false;
    _selected = null;

    _totalResponseTimeMs += elapsed;
    _slotStart = DateTime.now();

    if (prompted) {
      _promptedPlacements++;
      _errorCount++;
    } else {
      _score++;
      analyticsRecordValidAction();
      analyticsRecordCorrect(extraData: {'response_time_ms': elapsed});
      _adaptive.recordCorrect();
      onPlayCorrectSfx?.call();
      onCorrectPlacement?.call();
    }

    _layout();

    if (_slots.every((s) => s.filled != null)) {
      _resolveRound();
    } else {
      _resetIdle();
    }
  }

  // ── Round resolution ─────────────────────────────────────────────────

  void _resolveRound() {
    _idleTimer?.cancel();

    final ordering = _slots.map((s) => s.filled!.id).toList();
    final correct = _routine.steps.take(_slotCount).map((s) => s.id).toList();

    _firstOrdering ??= ordering;

    if (_freePlacement && !_listEquals(ordering, correct)) {
      // The child has filled every slot but the order is not right yet. Score
      // the attempt, then hand the mismatched cards back so they can fix it —
      // the fix itself is the learning, and it is recorded as a correction
      // rather than a failure.
      _sequenceDistanceTotal += _positionalDistance(ordering, correct);

      var returned = 0;
      for (var i = 0; i < _slots.length; i++) {
        if (_slots[i].filled!.id != correct[i]) {
          _pullBack(_slots[i]);
          returned++;
        }
      }
      if (returned > 0) {
        _retryCount++;
        _errorCount++;
        analyticsRecordRetry();
        onPlayWrongSfx?.call();
        onWrongAnswer?.call();
        _armIdle();
        return;
      }
    } else if (_firstOrdering != null) {
      _sequenceDistanceTotal += _positionalDistance(_firstOrdering!, correct);
    }

    analyticsCompleteRound(successful: true);
    _currentRound++;
    onStepChanged(_currentRound);

    if (_currentRound >= totalRounds) {
      _advanceTimer = Timer(const Duration(milliseconds: 800), _finish);
      return;
    }

    onPlayLevelCompleteSfx?.call();
    onPlayTransitionVo?.call();
    _advanceTimer = Timer(const Duration(milliseconds: 1300), _startRound);
  }

  /// How many positions are wrong. Simpler than edit distance and a better fit
  /// for a fixed-length ordering: what matters is how many steps sit in the
  /// wrong place, not how few splices would repair it.
  int _positionalDistance(List<String> a, List<String> b) {
    var d = 0;
    for (var i = 0; i < math.min(a.length, b.length); i++) {
      if (a[i] != b[i]) d++;
    }
    return d;
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ── Idle prompting ───────────────────────────────────────────────────

  void _armIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_tier.idleHintDelay, () {
      if (isRemoved) return;
      final next = _slots.firstWhere(
        (s) => s.filled == null,
        orElse: () => _slots.last,
      );
      if (next.filled != null) return;
      if (_hintBudgetLeft) {
        _hintCount++;
        _hintsUsedThisRound++;
        analyticsRecordHint(hintType: 'idle_nudge');
        analyticsRecordIdleTime(_tier.idleHintDelay.inSeconds);
        _highlightCorrectFor(next);
      }
      _armIdle();
    });
  }

  void _resetIdle() {
    _idleTimer?.cancel();
    _armIdle();
  }

  // ── Completion ───────────────────────────────────────────────────────

  void _finish() {
    _idleTimer?.cancel();
    _advanceTimer?.cancel();
    analyticsMarkCompleted();
    analyticsCompleteSession();

    onPlayGameCompleteSfx?.call();
    onPlayCelebrationVo?.call();

    onGameComplete(
      score: _score,
      totalItems: _totalPlacementsRequired,
      errorCount: _errorCount,
      totalResponseTimeMs: _totalResponseTimeMs,
      extras: {
        'retry_count': _retryCount,
        'hint_count': _hintCount,
        'self_corrections': _selfCorrections,
        'prompted_placements': _promptedPlacements,
        // Only ever non-zero on the free-placement tier — see the class doc.
        'sequence_distance': _sequenceDistanceTotal,
        'difficulty_level': profile.level,
      },
      analytics: analyticsSession,
    );
  }
}
