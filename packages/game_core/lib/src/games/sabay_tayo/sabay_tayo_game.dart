import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_ui/shared_ui.dart';

import 'components/attention_object.dart';
import 'components/buddy_art_cache.dart';
import 'components/buddy_character.dart';
import 'components/scene_backdrop.dart';
import '../shared/answer_label.dart';
import '../shared/game_layout.dart';
import '../shared/ghost_hand.dart';
import '../../analytics/enhanced_analytics_mixin.dart';
import '../../analytics/models/models.dart';
import '../../config/adaptive_difficulty.dart';
import '../../config/difficulty_profile.dart';
import '../../config/round_policy.dart';
import '../../config/game_motion.dart';
import '../shared/game_lifecycle_guard.dart';

/// Where an object may stand, as fractions of the playfield.
///
/// These are not arbitrary positions — they are the *centres of gaze cells*.
/// The buddy's gaze is nine discrete poses on a 3x3 grid (see
/// [CharacterSprites.layout]), so two objects sharing a cell would be
/// indistinguishable no matter how well the child follows the gaze. Every slot
/// therefore sits in its own cell, and the game never uses more slots than
/// there are cells in the upper region of the field.
///
/// The bottom row has no slots: that is where the buddy stands.
enum AttentionSlot {
  upLeft(0.17, 0.17),
  up(0.50, 0.17),
  upRight(0.83, 0.17),
  left(0.15, 0.52),
  right(0.85, 0.52);

  const AttentionSlot(this.fx, this.fy);

  /// Fraction of the way across the playfield.
  final double fx;

  /// Fraction of the way down the playfield.
  final double fy;

  /// True when this slot sits in the gaze grid's middle column, where the
  /// pointing arm cannot disambiguate anything — see [SabayTayoGame] on why
  /// the point is suppressed rather than shown misleadingly.
  bool get isCentreColumn => fx > 1 / 3 && fx < 2 / 3;
}

/// "Sabay Tayo!" — a joint-attention game.
///
/// A buddy character looks at one of the objects on screen; the child taps the
/// object the buddy is attending to. Following another person's gaze to a
/// shared referent is the earliest social-interaction skill on the
/// developmental ladder and a primary early-intervention target in ASD — every
/// other social skill in this app (turn-taking, greeting, sharing) assumes the
/// child can already do it, and until now nothing here trained it.
///
/// Three decisions worth keeping if this is ever refactored:
///
/// * **The correct object is never the loudest one.** On tier 2 and above it is
///   the *distractors* that carry idle motion, not the target. A child who taps
///   whatever is moving is not sharing attention, and a design that rewards
///   that would report a skill the child does not have.
/// * **The pointing arm is suppressed for a middle-column target.** The `point`
///   sheet aims one way and is mirrored for the other; straight up it means
///   nothing. Showing it anyway would be an actively misleading prompt, which
///   is worse than no prompt, so those targets are cued by gaze alone.
/// * **A trial ends only when the child finds the object.** A wrong tap
///   escalates the prompt and the same trial continues. Ending it would teach
///   that following someone's attention is a thing you can lose at.
class SabayTayoGame extends FlameGame
    with GameLifecycleGuard, TapCallbacks, EnhancedGameplayAnalyticsMixin {
  SabayTayoGame({
    required this.onStepChanged,
    required this.onGameComplete,
    required this.childId,
    this.totalRounds = GameRoundPolicy.standardRoundCount,
    this.itemsPerRound = 3,
    this.gameVersion,
    this.strings = const AppStrings(GameLanguage.english),
    this.profile = DifficultyProfile.medium,
    this.character = 'bps',
    this.onCorrectFind,
    this.onWrongAnswer,
    // Audio event callbacks (optional, wired by screen wrappers).
    this.onPlayCorrectSfx,
    this.onPlayWrongSfx,
    this.onPlayTapSfx,
    this.onPlayLevelCompleteSfx,
    this.onPlayGameCompleteSfx,
    this.onPlayCorrectVo,
    this.onPlayWrongVo,
    this.onPlayInstructionVo,
    this.onPlayHintVo,
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

  /// Fired on each correctly-followed gaze. The Flutter layer uses it for
  /// haptics and the mascot's nod.
  final void Function()? onCorrectFind;

  /// Fired on a wrong tap, alongside the wrong SFX and the encouraging voice
  /// line, so the mascot answers a mistake the same way the audio does.
  final void Function()? onWrongAnswer;

  // ── Audio event callbacks ────────────────────────────────────────────
  final VoidCallback? onPlayCorrectSfx;
  final VoidCallback? onPlayWrongSfx;

  /// The soft chime that opens a trial — "look at me" before "look at that".
  final VoidCallback? onPlayTapSfx;
  final VoidCallback? onPlayLevelCompleteSfx;
  final VoidCallback? onPlayGameCompleteSfx;

  /// Immediate feedback on a correct find: the object the child located, so the
  /// app can name it back ("Bola"). Praise waits for the end of the game.
  final AnswerLabelCallback? onPlayCorrectVo;
  final VoidCallback? onPlayWrongVo;
  final VoidCallback? onPlayInstructionVo;

  /// Spoken alongside the pointing hand once the gaze alone has not been
  /// followed — the verbal rung of the prompt hierarchy, above the gestural
  /// one. Deliberately never spoken as the gaze settles: a word landing inside
  /// the response window would be measured as part of [_gazeFollowLatencies].
  final VoidCallback? onPlayHintVo;
  final VoidCallback? onPlayTransitionVo;
  final VoidCallback? onPlayCelebrationVo;

  final int totalRounds;

  /// Trials per round. Four rounds of three keeps the session at twelve
  /// discrete trials, matching Hintay! — enough for a stable gaze-following
  /// rate without outrunning a young child's tolerance for one activity.
  final int itemsPerRound;

  final String childId;
  final String? gameVersion;

  /// Localized strings (English / Tagalog / Cebuano) for on-screen labels.
  final AppStrings strings;

  /// Hint/guidance policy for the selected difficulty tier (ABA prompt
  /// hierarchy — see [DifficultyProfile]). Also sets how many objects are on
  /// screen and which cues the buddy gives.
  final DifficultyProfile profile;

  /// Which mascot plays the buddy: `'bps'` or `'reiz'`. One character for the
  /// whole session — a child asked "where is he looking?" should not first have
  /// to work out how many people are in the room.
  final String character;

  // ── Game state ───────────────────────────────────────────────────────
  int _currentRound = 0;
  int _trialInRound = 0;
  int _score = 0;
  int _errorCount = 0;
  int _totalResponseTimeMs = 0;

  int _hintCount = 0;
  int _hintsUsedThisRound = 0;

  /// Highest prompt rung reached this trial. 0 means the child followed the
  /// gaze unaided — the number a therapist actually reads.
  int _promptLevel = 0;
  final List<int> _promptLevels = [];

  /// Milliseconds from the buddy's gaze settling to the child's first tap on
  /// any object. The joint-attention measure proper, and distinct from response
  /// time, which starts when the trial opens.
  final List<int> _gazeFollowLatencies = [];

  /// Tier-3 trials where the child's first tap landed on the decoy the buddy
  /// glanced at before settling — following the first movement rather than the
  /// final gaze.
  int _decoyFirstTaps = 0;
  int _decoyTrials = 0;

  /// Angle between (buddy → tapped object) and (buddy → target), in degrees,
  /// for every wrong tap. Separates "tapped the thing beside it" from "tapped
  /// the opposite side of the screen"; only the latter means the gaze was not
  /// followed at all.
  final List<double> _angularErrors = [];

  DateTime? _trialStart;
  DateTime? _gazeSettledAt;
  bool _trialResolved = false;
  bool _firstTapThisTrial = true;

  BuddyCharacter? _buddy;
  final List<AttentionObject> _objects = [];

  /// The slot each live object stands in, parallel to [_objects].
  ///
  /// Kept so a resize can re-derive positions from the slot fractions. Without
  /// it a rotation or a split-screen change would leave the cards where they
  /// were while the gaze grid moved underneath them — the buddy would then be
  /// looking at the wrong object and be right to, which is the one bug in this
  /// game a child could not possibly work around.
  final List<AttentionSlot> _slotsInPlay = [];

  AttentionObject? _target;
  AttentionObject? _decoy;
  GhostHand? _ghostHand;

  Timer? _idleTimer;
  Timer? _sequenceTimer;

  final math.Random _random = math.Random();

  /// Objects already used, to spread the catalogue across a session.
  final Set<String> _usedObjects = {};

  /// Within-round adaptive stepping: 2 consecutive errors temporarily step the
  /// tier down (more support) for the remainder of the round.
  late final AdaptiveDifficulty _adaptive = AdaptiveDifficulty(profile);

  DifficultyProfile get _tier => _adaptive.effective;

  bool get _hintBudgetLeft =>
      _tier.unlimitedHints || _hintsUsedThisRound < (_tier.hintsPerRound ?? 0);

  /// The object catalogue.
  ///
  /// Every name here has a shipped recording in `voice_over/items/`, which is
  /// what lets a correct find be named back to the child in all three languages
  /// without generating a single new asset. Adding an object without a
  /// recording would make this the one game that succeeds in silence.
  static const List<AttentionObjectData> _catalogue = [
    AttentionObjectData(name: 'Bola', en: 'Ball', emoji: '⚽', color: Color(0xFF6C9BD2)),
    AttentionObjectData(name: 'Manika', en: 'Doll', emoji: '🪆', color: Color(0xFFE89AB8)),
    AttentionObjectData(name: 'Kotse', en: 'Toy car', emoji: '🚗', color: Color(0xFFE07B54)),
    AttentionObjectData(name: 'Teddy', en: 'Teddy', emoji: '🧸', color: Color(0xFFC49A6C)),
    AttentionObjectData(name: 'Tinapay', en: 'Bread', emoji: '🍞', color: Color(0xFFD9A05B)),
    AttentionObjectData(name: 'Saging', en: 'Banana', emoji: '🍌', color: Color(0xFFF5D547)),
    AttentionObjectData(name: 'Mansanas', en: 'Apple', emoji: '🍎', color: Color(0xFFE0413E)),
    AttentionObjectData(name: 'Gatas', en: 'Milk', emoji: '🥛', color: Color(0xFFF1EEE2)),
    AttentionObjectData(name: 'Tubig', en: 'Water', emoji: '💧', color: Color(0xFF8FD2EF)),
    AttentionObjectData(name: 'Sabon', en: 'Soap', emoji: '🧼', color: Color(0xFF8BC36A)),
    AttentionObjectData(name: 'Sipilyo', en: 'Toothbrush', emoji: '🪥', color: Color(0xFF45C4C0)),
    AttentionObjectData(name: 'Syampu', en: 'Shampoo', emoji: '🧴', color: Color(0xFFB088D9)),
  ];

  /// The catalogue, exposed for tests: every entry needing a shipped voice
  /// recording is an invariant that breaks silently.
  @visibleForTesting
  static List<AttentionObjectData> get catalogue => _catalogue;

  // ── Tier tuning ──────────────────────────────────────────────────────

  /// How many objects are on screen. More objects is the main axis of
  /// difficulty: it is what turns "left or right?" into a real search.
  int get objectCount {
    switch (_tier.level) {
      case 1:
        return 2;
      case 3:
        return 4;
      default:
        return 3;
    }
  }

  /// The slots in play at the current tier.
  ///
  /// Tier 1 uses the two upper corners and nothing else: opposite sides, both
  /// outside the middle column, so the pointing arm is always meaningful and
  /// the two candidates are as far apart as the field allows.
  List<AttentionSlot> get _slotsForTier {
    switch (_tier.level) {
      case 1:
        return const [AttentionSlot.upLeft, AttentionSlot.upRight];
      case 3:
        return const [
          AttentionSlot.upLeft,
          AttentionSlot.up,
          AttentionSlot.upRight,
          AttentionSlot.left,
          AttentionSlot.right,
        ];
      default:
        return const [
          AttentionSlot.upLeft,
          AttentionSlot.up,
          AttentionSlot.upRight,
        ];
    }
  }

  /// Whether the buddy points as part of the *initial* cue (as opposed to as an
  /// escalated prompt). Tiers 1 and 2 do; tier 3 asks the child to work from
  /// the gaze alone.
  bool get _pointsByDefault => _tier.level <= 2;

  /// Whether the target pulses as part of the initial cue. Tier 1 only — it is
  /// errorless learning's "show them the answer" rung, not a hint.
  bool get _pulsesByDefault => _tier.level == 1;

  /// Whether the buddy feints at a decoy before settling on the target.
  ///
  /// Tier 3 only, and skipped under reduced motion: a 600 ms glance away and
  /// back is exactly the kind of movement that setting exists to remove.
  /// Clinically this is the most interesting thing the game measures — it
  /// separates children who follow a gaze from those who react to the first
  /// movement they see.
  bool get _usesDecoyGlance => _tier.level == 3 && !GameMotion.reduced;

  static const Duration _decoyGlanceHold = Duration(milliseconds: 600);

  // ── Layout ───────────────────────────────────────────────────────────
  //
  //   ├─ kTopOverlayBand ──────────────────────────────────────────────┤
  //     ┌────┐          ┌────┐          ┌────┐    upper row: gaze row -1
  //     │ ⚽ │          │ 🍌 │          │ 🧸 │
  //     └────┘          └────┘          └────┘
  //   ┌────┐                              ┌────┐  middle row: gaze row 0
  //   │ 🥛 │                              │ 🧼 │
  //   └────┘                              └────┘
  //                    ╭───╮
  //                    │o o│  ← the buddy, bottom-centre
  //   ═══════════════ ╰───╯ ═══════════════════
  //
  // Every measurement hangs off [_playfieldTop]: an object under the app's
  // overlay strip has its touch eaten, so the child sees a target they cannot
  // hit — and in this game that reads as "I followed the gaze and nothing
  // happened", which is the worst possible feedback.

  double get _playfieldTop => kTopOverlayBand;

  double get _playfieldHeight => size.y - _playfieldTop;

  /// Side of an object card. Bounded by the gap between slot rows so the two
  /// rows never touch, and by the field width so four cards never crowd.
  double get _objectSize => math.min(
        math.min(size.x * 0.155, _playfieldHeight * 0.30),
        140,
      );

  /// The buddy's height. Tall enough that the eyes are legible from a metre
  /// away — the child has to read a pupil offset, which is the smallest detail
  /// this app ever asks anyone to see.
  double get _buddyHeight => math.min(_playfieldHeight * 0.46, 260);

  Vector2 get _buddyFeet => Vector2(size.x / 2, size.y - _playfieldHeight * 0.02);

  Vector2 _slotPosition(AttentionSlot slot) => Vector2(
        slot.fx * size.x,
        _playfieldTop + slot.fy * _playfieldHeight,
      );

  // ── Lifecycle ────────────────────────────────────────────────────────

  @override
  Color backgroundColor() => const Color(0x00000000); // transparent

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    analyticsInitialize(
      gameId: 'sabay_tayo',
      childId: childId,
      totalRounds: totalRounds,
      gameVersion: gameVersion ?? '1.0.0',
    );
    analyticsStartSession();

    // Best-effort: a failed load leaves BuddyPainter to draw the buddy, and the
    // game plays on. The one thing that must not happen is the session ending
    // because a PNG was missing.
    await BuddyArtCache.ensureLoaded(character);

    add(SceneBackdrop(
      position: Vector2(0, _playfieldTop),
      size: Vector2(size.x, _playfieldHeight),
      groundTop: _playfieldHeight * 0.72,
      buddyFootX: size.x / 2,
    ));

    _buddy = BuddyCharacter(
      position: _buddyFeet,
      size: Vector2(_buddyHeight * 0.72, _buddyHeight),
    );
    add(_buddy!);

    onPlayInstructionVo?.call();
    _startRound();
  }

  @override
  void onGameResize(Vector2 newSize) {
    super.onGameResize(newSize);
    _buddy?.position = _buddyFeet;
    for (var i = 0; i < _objects.length && i < _slotsInPlay.length; i++) {
      _objects[i].position = _slotPosition(_slotsInPlay[i]);
      _objects[i].size = Vector2.all(_objectSize);
    }
    // The buddy is now aiming at where the target used to be.
    final target = _target;
    if (target != null && !_trialResolved && _gazeSettledAt != null) {
      _lookAt(target, withPoint: _pointsByDefault);
    }
  }

  @override
  void onRemove() {
    invalidateLifecycle();
    _cancelTimers();
    super.onRemove();
  }

  void _cancelTimers() {
    _idleTimer?.cancel();
    _sequenceTimer?.cancel();
    _idleTimer = _sequenceTimer = null;
  }

  // ── Round / trial flow ───────────────────────────────────────────────

  void _startRound() {
    _trialInRound = 0;
    _hintsUsedThisRound = 0;
    _adaptive.startRound(); // any step-down only lasts one round
    analyticsStartRound(roundNumber: _currentRound + 1);
    analyticsAddRoundData('objects_on_screen', objectCount);
    _startTrial();
  }

  void _startTrial() {
    if (isRemoved) return;

    _cancelTimers();
    _clearObjects();
    _trialResolved = false;
    _firstTapThisTrial = true;
    _promptLevel = 0;
    _gazeSettledAt = null;
    _buddy?.faceChild();

    _buildObjects();

    _trialStart = DateTime.now();
    analyticsShowStimulus();

    // A beat facing the child before the cue: joint attention starts with the
    // partner having the child's attention in the first place. Cueing into an
    // empty room is not the skill.
    onPlayTapSfx?.call();
    _sequenceTimer = Timer(const Duration(milliseconds: 700), _giveCue);
  }

  /// Places this trial's objects and picks the target.
  void _buildObjects() {
    final slots = _slotsForTier.toList()..shuffle(_random);
    final chosenSlots = slots.take(objectCount).toList();
    final data = _pickObjects(objectCount);

    final side = _objectSize;
    for (var i = 0; i < chosenSlots.length; i++) {
      final object = AttentionObject(
        data: data[i],
        language: strings.language,
        slot: chosenSlots[i].name,
        position: _slotPosition(chosenSlots[i]),
        size: Vector2.all(side),
        // Distractors idle, the target does not — see the class comment.
        idles: _tier.level >= 2 && i != 0,
      );
      _objects.add(object);
      add(object);
    }
    _slotsInPlay
      ..clear()
      ..addAll(chosenSlots);

    // Index 0 is the target: `data` was shuffled and `chosenSlots` was
    // shuffled, so this is an unbiased pick without a second draw.
    _target = _objects.first;

    _decoy = null;
    if (_usesDecoyGlance && _objects.length > 1) {
      _decoy = _objects[1 + _random.nextInt(_objects.length - 1)];
    }
  }

  /// Picks [count] distinct objects, spreading the catalogue across a session
  /// so a child meets all twelve rather than the same three.
  List<AttentionObjectData> _pickObjects(int count) {
    if (_usedObjects.length > _catalogue.length - count) _usedObjects.clear();

    final pool = _catalogue.where((d) => !_usedObjects.contains(d.name)).toList()
      ..shuffle(_random);
    final picked = pool.take(count).toList();

    // Fallback (shouldn't trigger) — top up from the full catalogue.
    if (picked.length < count) {
      final all = _catalogue.toList()..shuffle(_random);
      for (final d in all) {
        if (picked.length >= count) break;
        if (!picked.contains(d)) picked.add(d);
      }
    }

    for (final d in picked) {
      _usedObjects.add(d.name);
    }
    return picked;
  }

  /// The buddy turns to the target — the moment the trial is really asking its
  /// question, and the moment [_gazeFollowLatencies] starts counting from.
  void _giveCue() {
    if (isRemoved || _trialResolved) return;

    final decoy = _decoy;
    if (decoy != null) {
      _decoyTrials++;
      _lookAt(decoy);
      analyticsAddRoundData('decoy_glance', decoy.data.name);
      _sequenceTimer = Timer(_decoyGlanceHold, _settleOnTarget);
      return;
    }
    _settleOnTarget();
  }

  void _settleOnTarget() {
    if (isRemoved || _trialResolved) return;

    final target = _target;
    if (target == null) return;

    _lookAt(target, withPoint: _pointsByDefault);
    if (_pulsesByDefault) target.showHint();

    _gazeSettledAt = DateTime.now();
    _startIdleTimer();
  }

  /// Aims the buddy at [object], optionally with the pointing arm.
  ///
  /// The arm is dropped for a middle-column target rather than shown pointing
  /// somewhere else — see the class comment. When that happens the gaze is
  /// still unambiguous, because the middle column holds exactly one slot.
  void _lookAt(AttentionObject object, {bool withPoint = false}) {
    final buddy = _buddy;
    if (buddy == null) return;

    final f = object.fractionOf(size, playfieldTop: _playfieldTop);
    final centreColumn = f.x > 1 / 3 && f.x < 2 / 3;

    if (withPoint && !centreColumn) {
      buddy.pointAt(f.x, f.y);
    } else {
      buddy.gazeAt(f.x, f.y);
    }
  }

  // ── Input ────────────────────────────────────────────────────────────

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    if (_trialResolved || _objects.isEmpty) return;

    final point = event.localPosition;

    AttentionObject? hit;
    for (final object in _objects) {
      if (object.containsGenerously(point)) {
        hit = object;
        break;
      }
    }

    if (hit == null) {
      // Tapped the empty field. Recorded, but not scored against the trial —
      // an exploratory touch is not a failure to follow a gaze.
      analyticsRecordTouch(Offset(point.x, point.y), isValid: false);
      analyticsRecordOffTaskAction(actionType: 'tap_off_target');
      return;
    }

    if (_firstTapThisTrial) {
      _firstTapThisTrial = false;
      analyticsRecordValidAction();
      if (_gazeSettledAt != null) {
        _gazeFollowLatencies
            .add(DateTime.now().difference(_gazeSettledAt!).inMilliseconds);
      }
      if (_decoy != null && hit == _decoy) {
        _decoyFirstTaps++;
        analyticsAddRoundData('first_tap_was_decoy', true);
      }
    }

    if (hit == _target) {
      _resolveCorrect(hit);
    } else {
      _resolveWrong(hit);
    }
  }

  void _resolveCorrect(AttentionObject object) {
    _trialResolved = true;
    _cancelTimers();
    _hideGhostHand();

    final responseTime = _trialStart == null
        ? 0
        : DateTime.now().difference(_trialStart!).inMilliseconds;
    _totalResponseTimeMs += responseTime;
    _score++;
    _promptLevels.add(_promptLevel);
    _adaptive.recordCorrect();

    analyticsRecordCorrect(extraData: {
      'object': object.data.name,
      'slot': object.slot,
      'objects_on_screen': _objects.length,
      'prompt_level': _promptLevel,
      'response_time_ms': responseTime,
    });

    for (final o in _objects) {
      o.hideHint();
    }
    object.showFound();
    _buddy?.celebrate();

    onCorrectFind?.call();
    onPlayCorrectSfx?.call();
    onPlayCorrectVo?.call(AnswerLabel(item: object.data.name));

    _sequenceTimer = Timer(const Duration(milliseconds: 1200), _advanceTrial);
  }

  void _resolveWrong(AttentionObject object) {
    _errorCount++;
    _cancelTimers();

    final target = _target;
    if (target != null) _angularErrors.add(_angleBetween(object, target));

    if (_adaptive.recordError()) {
      analyticsAddRoundData('difficulty_step_down', _tier.level);
    }

    analyticsRecordWrong(extraData: {
      'tapped': object.data.name,
      'tapped_slot': object.slot,
      'expected': target?.data.name,
      'expected_slot': target?.slot,
      'angular_error_deg': _angularErrors.isEmpty ? 0 : _angularErrors.last,
      'prompt_level': _promptLevel,
    });
    analyticsRecordRetry();

    object.showWrong();
    _buddy?.reassure();

    onPlayWrongSfx?.call();
    onPlayWrongVo?.call();
    onWrongAnswer?.call();

    // The trial does not end. After the reassurance lands, the buddy asks
    // again — one rung further up the prompt hierarchy.
    _sequenceTimer = Timer(const Duration(milliseconds: 1100), () {
      if (isRemoved || _trialResolved) return;
      _escalatePrompt();
    });
  }

  /// Angle between (buddy → [tapped]) and (buddy → [target]), in degrees.
  double _angleBetween(AttentionObject tapped, AttentionObject target) {
    final origin = _buddy?.position ?? Vector2(size.x / 2, size.y);
    final a = tapped.position - origin;
    final b = target.position - origin;
    if (a.length == 0 || b.length == 0) return 0;
    final cos = (a.dot(b) / (a.length * b.length)).clamp(-1.0, 1.0);
    return math.acos(cos) * 180 / math.pi;
  }

  // ── Prompt hierarchy ─────────────────────────────────────────────────
  //
  // Rung 1 is a restatement of the stimulus, not a hint: it tells the child
  // nothing they were not already shown, so every tier gets it, including Hard.
  // Rungs 2–4 progressively give the answer away and are gated on the tier's
  // budget. Rung 4 (the ghost hand) is errorless learning's floor — on Easy the
  // child can never be left stuck.

  /// Highest rung this game has.
  static const int maxPromptLevel = 4;

  void _escalatePrompt() {
    if (isRemoved || _trialResolved) return;
    final target = _target;
    if (target == null) return;

    final next = _promptLevel + 1;

    // Rung 1: say it again. Always available.
    if (next == 1) {
      _promptLevel = 1;
      _lookAt(target, withPoint: _pointsByDefault);
      _gazeSettledAt = DateTime.now();
      analyticsRecordPrompt(promptType: 'gaze_repeat');
      _startIdleTimer();
      return;
    }

    // Everything above rung 1 is an answer hint.
    if (_tier.noHints || !_hintBudgetLeft) {
      // Hard tier, or a spent Medium budget: re-orient without revealing.
      // Never abandoned, never handed the answer.
      _lookAt(target, withPoint: false);
      _gazeSettledAt = DateTime.now();
      onPlayInstructionVo?.call();
      analyticsRecordHint(hintType: 'reorient_instruction');
      _startIdleTimer();
      return;
    }

    _promptLevel = math.min(next, maxPromptLevel);
    _hintCount++;
    _hintsUsedThisRound++;

    final f = target.fractionOf(size, playfieldTop: _playfieldTop);
    final centreColumn = f.x > 1 / 3 && f.x < 2 / 3;

    if (_promptLevel == 2) {
      // Rung 2: add the arm. If the target sits in the middle column there is
      // no meaningful arm to add, so this rung is skipped rather than faked —
      // a prompt that points somewhere else is worse than no prompt.
      if (centreColumn) {
        _promptLevel = 3;
        target.showHint();
        analyticsRecordHint(hintType: 'target_pulse');
      } else {
        _buddy?.pointAt(f.x, f.y);
        onPlayHintVo?.call();
        analyticsRecordHint(hintType: 'gaze_and_point');
      }
    } else if (_promptLevel == 3) {
      _lookAt(target, withPoint: true);
      target.showHint();
      analyticsRecordHint(hintType: 'target_pulse');
    } else {
      // Rung 4: the ghost hand, errorless learning's floor. Tiers without the
      // guided demo simply hold at the pulse rather than being handed the tap.
      _lookAt(target, withPoint: true);
      target.showHint();
      if (_tier.guidedDemo) {
        _showGhostHand(target);
        analyticsRecordHint(hintType: 'gesture_demo');
      } else {
        analyticsRecordHint(hintType: 'target_pulse');
      }
    }

    _gazeSettledAt = DateTime.now();
    _startIdleTimer();
  }

  void _startIdleTimer() {
    _idleTimer?.cancel();
    final delay = (_tier.noHints || !_hintBudgetLeft)
        ? _tier.reorientDelay
        : _tier.idleHintDelay;
    _idleTimer = Timer(delay, () {
      if (isRemoved || _trialResolved) return;
      analyticsRecordIdleTime(delay.inSeconds);
      _escalatePrompt();
    });
  }

  void _showGhostHand(AttentionObject target) {
    _hideGhostHand();
    final hand = GhostHand.tap(
      at: target.position.clone(),
      handSize: target.size.x * 0.7,
    );
    _ghostHand = hand;
    add(hand);
  }

  /// A demo the child has started answering is a demo that is over — the same
  /// reason `sari_sari_sort` tears its ghost hand down on pick-up.
  void _hideGhostHand() {
    if (_ghostHand?.isMounted ?? false) _ghostHand?.removeFromParent();
    _ghostHand = null;
  }

  void _clearObjects() {
    _hideGhostHand();
    for (final object in _objects) {
      object.removeFromParent();
    }
    _objects.clear();
    _slotsInPlay.clear();
    _target = null;
    _decoy = null;
  }

  // ── Advancing ────────────────────────────────────────────────────────

  void _advanceTrial() {
    if (isRemoved) return;
    _trialInRound++;

    if (_trialInRound < itemsPerRound) {
      _startTrial();
      return;
    }

    analyticsCompleteRound(successful: true);
    _currentRound++;
    onStepChanged(_currentRound);

    if (_currentRound >= totalRounds) {
      _sequenceTimer = Timer(const Duration(milliseconds: 600), _finish);
      return;
    }

    onPlayLevelCompleteSfx?.call();
    onPlayTransitionVo?.call();
    _sequenceTimer = Timer(const Duration(milliseconds: 1200), _startRound);
  }

  void _finish() {
    if (!tryBeginCompletion()) return;
    _cancelTimers();
    _clearObjects();
    _buddy?.faceChild();

    analyticsMarkCompleted();
    analyticsAddGameSpecificMetric('hint_count', _hintCount);
    analyticsAddGameSpecificMetric('mean_prompt_level', _meanPromptLevel);
    analyticsAddGameSpecificMetric(
      'mean_gaze_follow_latency_ms',
      _meanGazeFollowLatencyMs,
    );
    analyticsCompleteSession();

    onPlayGameCompleteSfx?.call();
    onPlayCelebrationVo?.call();

    onGameComplete(
      score: _score,
      totalItems: totalRounds * itemsPerRound,
      errorCount: _errorCount,
      totalResponseTimeMs: _totalResponseTimeMs,
      extras: {
        // Beyond the shared four: the joint-attention measures. These are what
        // make this session useful to the assessment model.
        'mean_gaze_follow_latency_ms': _meanGazeFollowLatencyMs,
        'mean_prompt_level': _meanPromptLevel,
        'independent_trials': _promptLevels.where((l) => l == 0).length,
        'decoy_first_taps': _decoyFirstTaps,
        'decoy_trials': _decoyTrials,
        'mean_angular_error_deg': _meanAngularErrorDeg,
        'hint_count': _hintCount,
        'difficulty_level': profile.level,
      },
      analytics: analyticsSession,
    );
  }

  int get _meanGazeFollowLatencyMs => _gazeFollowLatencies.isEmpty
      ? 0
      : (_gazeFollowLatencies.reduce((a, b) => a + b) /
              _gazeFollowLatencies.length)
          .round();

  double get _meanPromptLevel => _promptLevels.isEmpty
      ? 0
      : _promptLevels.reduce((a, b) => a + b) / _promptLevels.length;

  double get _meanAngularErrorDeg => _angularErrors.isEmpty
      ? 0
      : _angularErrors.reduce((a, b) => a + b) / _angularErrors.length;
}
