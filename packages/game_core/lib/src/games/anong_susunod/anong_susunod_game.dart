import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:shared_ui/shared_ui.dart';

import 'components/routine_card.dart';
import 'components/sequence_slot.dart';
import 'routine_art_cache.dart';
import 'routine_steps.dart';
import '../shared/answer_label.dart';
import '../shared/game_layout.dart';
import '../../analytics/enhanced_analytics_mixin.dart';
import '../../analytics/models/models.dart';
import '../../config/adaptive_difficulty.dart';
import '../../config/difficulty_profile.dart';
import '../shared/game_lifecycle_guard.dart';

/// The core Flame game for "Ano'ng Susunod?" (What's Next?).
///
/// The child puts the steps of an everyday routine into order. It is the app's
/// most direct expression of TEACCH: a visual schedule — the central TEACCH
/// support — turned into an assessable task. Because the routines are ones the
/// child already lives through, it doubles as a functional-skills intervention
/// rather than an abstract ordering puzzle.
///
/// Interaction is **tap-to-select then tap-a-slot, or drag the card across** —
/// both paths, always, on every tier. Dragging is the gesture a child reaches
/// for unprompted and it keeps the card under the finger that means it; the tap
/// path is what a child with motor-planning differences can still complete when
/// a drag gets released a few pixels early. Neither is the fallback for the
/// other, and a drag that never travels past [_dragSlop] resolves as a tap, so a
/// tremor cannot turn a pick-up into a dropped card.
///
/// Four decisions worth keeping if this is ever refactored:
///
/// * **The tray is shuffled every round, and holds more cards than there are
///   slots.** Presenting steps in canonical order lets a child score full marks
///   by always taking the leftmost card. Handing out exactly as many cards as
///   there are gaps is the same failure one step later: whatever the child does
///   with the earlier cards, the last gap can only take the last card. The
///   shuffle and the distractors together are what make the accuracy number mean
///   anything at all — see [_foilCount].
/// * **A wrong placement never ends the round.** The card returns to the tray,
///   a retry is recorded, and the prompt hierarchy escalates — highlight at two
///   wrong attempts, place it for them at four. The routine always completes.
/// * **On the hardest tier the child may place cards in the wrong order**, and
///   the first complete ordering is scored before any correction. That is the
///   only reason `sequence_distance` can be non-zero: a child who is one swap
///   away from right is not the same as one who is random, and no other game
///   in the app can tell those apart.
class AnongSusunodGame extends FlameGame
    with GameLifecycleGuard, TapCallbacks, DragCallbacks, EnhancedGameplayAnalyticsMixin {
  AnongSusunodGame({
    required this.onStepChanged,
    required this.onGameComplete,
    required this.childId,
    this.totalRounds = 4,
    this.gameVersion,
    this.profile = DifficultyProfile.medium,
    this.strings = const AppStrings(GameLanguage.english),
    this.onCorrectPlacement,
    this.onRoutineChanged,
    this.onWrongAnswer,
    this.onPlayCorrectSfx,
    this.onPlayWrongSfx,
    this.onPlayTapSfx,
    this.onPlayLevelCompleteSfx,
    this.onPlayGameCompleteSfx,
    this.onPlayCorrectVo,
    this.onPlayWrongVo,
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

  /// Fired as each round opens, with the routine's id, its title already
  /// rendered in [strings]' language, and whether this is the opening round.
  ///
  /// The id is for the audio layer (it selects the recording); the title is for
  /// the Flutter overlay. Both are handed out here rather than looked up by the
  /// screen because the game alone knows which routine the round drew.
  ///
  /// This carries the game's spoken opening, which is why there is no separate
  /// `onPlayInstructionVo` here as in the other games: the question belongs
  /// after the routine name ("Umaga. What comes next?"), and firing the two
  /// from different places would let one silence the other.
  final void Function(String routineId, String routineTitle, bool isFirstRound)?
      onRoutineChanged;

  final VoidCallback? onPlayCorrectSfx;
  final VoidCallback? onPlayWrongSfx;
  final VoidCallback? onPlayTapSfx;
  final VoidCallback? onPlayLevelCompleteSfx;
  final VoidCallback? onPlayGameCompleteSfx;

  /// Names the step the child just seated — "Maghugas ng kamay" — instead of
  /// praising the placement. See [AnswerLabel].
  final AnswerLabelCallback? onPlayCorrectVo;
  final VoidCallback? onPlayWrongVo;
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

  /// The card currently under the child's finger, once the gesture has been
  /// confirmed as a drag rather than a tap.
  RoutineCard? _dragCard;

  /// Where the pointer went down, in game space. The tap/drag decision is
  /// DISPLACEMENT from here rather than accumulated deltas: summed deltas keep
  /// growing while a finger trembles in one spot, so a child with a tremor could
  /// cross the threshold without ever moving off the card — the exact case the
  /// threshold exists to protect.
  Vector2? _dragOrigin;

  /// Pointer travel (game px) below which a release still counts as a tap.
  static const double _dragSlop = 14.0;

  Timer? _idleTimer;
  Timer? _advanceTimer;
  bool _completionPending = false;

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

  /// Extra cards in the tray that belong to no slot this round, drawn from the
  /// other routines.
  ///
  /// Without these the task is not answerable *wrongly*. A tray holding exactly
  /// as many cards as there are gaps means the final placement of every round is
  /// forced, and on the Easy tier — one gap, one card — the whole round is: the
  /// child cannot be incorrect no matter what they understand, and the session
  /// reports a flawless score that tells the assessment model nothing. A
  /// distractor makes the choice real while leaving the support in place; on
  /// Easy the hints are still unlimited and the idle nudge still lights up the
  /// right card after five seconds, so this is errorless *teaching*, not an
  /// errorless *task*.
  ///
  /// One is enough. The point is that a choice exists, not that it is crowded —
  /// a tray of near-misses would tax working memory, which is not what this game
  /// is measuring.
  int get _foilCount => 1;

  // ── Lifecycle ────────────────────────────────────────────────────────

  @override
  Color backgroundColor() => const Color(0x00000000); // Transparent

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Decode the card pictures before the first round is laid out. Awaited so
    // the child never sees the painted fallback swap to the picture mid-round —
    // a card changing appearance under them is exactly the unpredictability
    // this app is built to avoid.
    await RoutineArtCache.ensureLoaded();
    if (!isLifecycleActive) return;

    analyticsInitialize(
      gameId: 'anong_susunod',
      childId: childId,
      totalRounds: totalRounds,
      gameVersion: gameVersion,
    );
    analyticsStartSession();

    // The spoken opening is announced by _startRound via
    // [onRoutineChanged] — see the note there.
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
    // Every card the drag could have been holding has just left the tree; a
    // stale reference here would keep the next round's layout skipping a card
    // that no longer exists.
    _dragCard = null;
    _dragOrigin = null;
    _wrongPerSlot.clear();
    _hintsUsedThisRound = 0;
    _firstOrdering = null;
    _adaptive.startRound();

    analyticsStartRound(roundNumber: _currentRound + 1);

    // Announce the routine before the cards appear. A child who is told the
    // round is about "Umaga" has a frame to sort the pictures into; without it
    // the first card is a guess.
    onRoutineChanged?.call(
        _routine.id, _routine.title(strings.language), _currentRound == 0);

    final steps = _routine.steps.take(_slotCount).toList();

    for (var i = 0; i < _slotCount; i++) {
      final slot = SequenceSlot(
          index: i,
          language: strings.language,
          position: Vector2.zero(),
          size: Vector2.all(1));
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

    // Remaining steps go to the tray with their distractors, SHUFFLED. Without
    // the shuffle the correct card is always the leftmost one; without the
    // distractors the last gap can only take the last card. Either alone
    // collapses the task — see [_foilCount].
    final remaining = [
      ...steps.sublist(presetCount),
      ..._pickFoils(steps, _foilCount),
    ]..shuffle(_random);
    for (final step in remaining) {
      final card = RoutineCard(
          step: step,
          language: strings.language,
          position: Vector2.zero(),
          size: Vector2.all(1));
      _tray.add(card);
      add(card);
    }

    // Counts only the real steps: a distractor is never something the child is
    // required to place, so it must not enlarge the denominator the accuracy
    // score is read against.
    _totalPlacementsRequired += _placementsThisRound;
    _slotStart = DateTime.now();
    _layout();
    _armIdle();
    analyticsShowStimulus();
  }

  /// Picks [count] distractor steps that belong to no slot in [inRound].
  ///
  /// Drawn from the *other* routines rather than invented, so a foil is still a
  /// real thing the child does — "Maligo" offered during Umaga is a step they
  /// recognise that simply does not belong here, which is the discrimination
  /// being asked for. A nonsense card would be rejected on sight and measure
  /// nothing.
  ///
  /// Matched by step id, not by identity: `brush` appears in both Umaga and
  /// Gabi and `wash` in both Kainan and Laro, so a shared step must never come
  /// back as a foil for the routine it is already part of.
  List<RoutineStep> _pickFoils(List<RoutineStep> inRound, int count) {
    if (count <= 0) return const [];

    final excluded = inRound.map((s) => s.id).toSet();
    final pool = <String, RoutineStep>{};
    for (final routine in kRoutines) {
      for (final step in routine.steps) {
        if (!excluded.contains(step.id)) pool.putIfAbsent(step.id, () => step);
      }
    }

    final candidates = pool.values.toList()..shuffle(_random);
    return candidates.take(count).toList();
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
      final card = _tray[i];
      card
        ..homePosition = Vector2(trayStartX + i * (cardW + trayGap), trayY)
        ..size = Vector2(cardW, cardH);
      // A card under the finger keeps whatever position the drag has given it;
      // snapping it back to its slot in the tray mid-gesture would read as the
      // card escaping the child's grip.
      if (card != _dragCard) card.position = card.homePosition;
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
    if (!isLifecycleActive || _completionPending) return;
    super.onTapDown(event);
    final point = event.localPosition;

    for (final card in _tray) {
      if (!card.placed && card.containsLocal(point)) {
        _select(card);
        return;
      }
    }

    for (final slot in _slots) {
      if (slot.containsLocal(point)) {
        _tapSlot(slot);
        return;
      }
    }

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

    _offer(slot, card);
  }

  /// Resolves [card] against [slot]. The single place a placement is judged, so
  /// a dragged card and a tapped one are scored identically — the gesture the
  /// child reached for must never change what the session reports about them.
  void _offer(SequenceSlot slot, RoutineCard card) {
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

  // ── Drag (the other way to place a card) ─────────────────────────────

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    // Canvas space throughout, which is both the cards' parent space and what
    // [FingertipDrag] expects — no camera sits between the two in this game.
    final point = event.canvasPosition;

    for (final card in _tray) {
      if (!card.placed && card.containsLocal(point)) {
        _dragCard = card;
        _dragOrigin = point.clone();
        return;
      }
    }
    _dragCard = null;
    _dragOrigin = null;
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    final card = _dragCard;
    final origin = _dragOrigin;
    if (card == null || origin == null) return;

    if (!card.isFollowingFingertip) {
      // Still tap-like: leave the card sitting in the tray so a shaky tap does
      // not visibly nudge it.
      if ((event.canvasEndPosition - origin).length < _dragSlop) return;
      // Confirmed as a drag. Lift it above the other cards and the slots, and
      // start the glide onto the fingertip — done here rather than at
      // onDragStart so a wobbled tap never yanks the card out from under the
      // child.
      _select(card);
      card.priority = 300;
      card.startFingertipFollow(event.canvasEndPosition);
      return;
    }

    card.moveFingertip(event.canvasEndPosition);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    final card = _dragCard;
    _dragCard = null;
    _dragOrigin = null;
    if (card == null) return;

    if (!card.isFollowingFingertip) {
      // Never travelled: that was a tap, and onTapDown has already selected the
      // card. Nothing more to do.
      return;
    }

    // Hit-tested from the card's centre, which [FingertipDrag] has parked under
    // the fingertip — so the slot the child was pointing at is the slot that
    // takes the card.
    final centre = card.visualCenter;
    card.stopFingertipFollow();
    card.priority = 0;

    for (final slot in _slots) {
      if (slot.containsLocal(centre)) {
        _offer(slot, card);
        // A rejected or ignored card is still sitting where it was dropped.
        if (!card.placed) _returnHome(card);
        return;
      }
    }

    // Released over open canvas. Not an error and not scored — a child who
    // thinks better of a card mid-drag has done nothing wrong.
    _returnHome(card);
    _resetIdle();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    final card = _dragCard;
    _dragCard = null;
    _dragOrigin = null;
    if (card == null) return;
    card.stopFingertipFollow();
    card.priority = 0;
    _returnHome(card);
  }

  /// Glides [card] back to its place in the tray. Animated rather than snapped:
  /// a card that vanishes from under the finger and reappears elsewhere is hard
  /// to follow, and the movement is what shows the child the card is still
  /// theirs to try again.
  void _returnHome(RoutineCard card) {
    card.add(MoveToEffect(
      card.homePosition.clone(),
      EffectController(duration: 0.2, curve: Curves.easeOut),
    ));
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
      // Say the step back in the child's language. Carried as the id, not the
      // visible label — see [AnswerLabel.routineStep].
      onPlayCorrectVo?.call(AnswerLabel(routineStep: card.step.id));
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

    // Whether this is the child's first complete ordering of the round. The
    // measure is of their unaided attempt, so it is banked exactly once —
    // whichever branch below resolves it. Adding it in both (the shape this had
    // first) double-counts every round a child gets wrong and then repairs,
    // reporting twice the sequence error they actually made.
    final isFirstOrdering = _firstOrdering == null;
    _firstOrdering ??= ordering;

    if (_freePlacement && !_listEquals(ordering, correct)) {
      // The child has filled every slot but the order is not right yet. Score
      // the attempt, then hand the mismatched cards back so they can fix it —
      // the fix itself is the learning, and it is recorded as a correction
      // rather than a failure.
      if (isFirstOrdering) {
        _sequenceDistanceTotal += _positionalDistance(ordering, correct);
      }

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
    } else if (isFirstOrdering) {
      _sequenceDistanceTotal += _positionalDistance(_firstOrdering!, correct);
    }

    analyticsCompleteRound(successful: true);
    _currentRound++;
    onStepChanged(_currentRound);

    if (_currentRound >= totalRounds) {
      _completionPending = true;
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
    if (!tryBeginCompletion()) return;
    _completionPending = true;
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
        'sequence_distance': _sequenceDistanceTotal,
        'difficulty_level': profile.level,
      },
      analytics: analyticsSession,
    );
  }
}
