import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_ui/shared_ui.dart';

import 'components/buddy_face.dart';
import 'components/choice_card.dart';
import 'components/scene_panel.dart';
import 'emotion_art_cache.dart';
import 'emotions.dart';
import '../shared/answer_label.dart';
import '../shared/game_layout.dart';
import '../shared/ghost_hand.dart';
import '../../analytics/enhanced_analytics_mixin.dart';
import '../../analytics/models/models.dart';
import '../../config/adaptive_difficulty.dart';
import '../../config/difficulty_profile.dart';
import '../shared/game_lifecycle_guard.dart';

/// The core Flame game for "Ano'ng Nararamdaman?" (How does he feel?).
///
/// A short picture scene shows something that happened — an ice cream fell, a
/// friend gave a present — and the buddy's face moves into the feeling it
/// caused. The child taps the matching face from a row of large cards. On the
/// hardest tier a second question follows: *what would you do?*
///
/// Four decisions worth keeping if this is ever refactored:
///
/// * **A wrong tap is never named as a wrong feeling.** It dims, settles back,
///   and the buddy's face replays the transition. Everything the child hears is
///   "look again" — the gently-retry voice line, never a correction. This game
///   is played by children who are already told frequently that they have read a
///   room wrongly, and a mini-game that says it again in a friendly voice is
///   worse than one that says nothing.
/// * **The distractor set is the measurement.** Tier 1 bans the confusable
///   pairs so a beginner is choosing between genuinely different faces; tier 2
///   requires exactly one of them, because `sad` offered against `scared` is the
///   trial that tells you something and `sad` offered against `happy` is not.
///   See [kNearMissPairs] and [_optionsFor].
/// * **`confusion_pairs` is the actual output of this game.** Score and error
///   count say a child got six of twelve; the confusion map says they read
///   every scared face as sad, which is a different child from one guessing at
///   random and points at a different intervention. It is recorded as
///   `target->chosen`, never as a boolean.
/// * **The scene card is hidden during the tier-3 response step.** With it up,
///   "what would you do?" is answerable from the picture without ever
///   consulting the feeling. See [ScenePanel].
class AnongNararamdamanGame extends FlameGame
    with GameLifecycleGuard, TapCallbacks, EnhancedGameplayAnalyticsMixin {
  AnongNararamdamanGame({
    required this.onStepChanged,
    required this.onGameComplete,
    required this.childId,
    this.character = 'bps',
    this.totalRounds = 4,
    this.itemsPerRound = 3,
    this.gameVersion,
    this.profile = DifficultyProfile.medium,
    this.strings = const AppStrings(GameLanguage.english),
    this.onCorrectAnswer,
    this.onWrongAnswer,
    this.onResponseStepChanged,
    this.onPlayCorrectSfx,
    this.onPlayWrongSfx,
    this.onPlayTapSfx,
    this.onPlayLevelCompleteSfx,
    this.onPlayGameCompleteSfx,
    this.onPlayCorrectVo,
    this.onPlayWrongVo,
    this.onPlayInstructionVo,
    this.onPlaySceneVo,
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

  final void Function()? onCorrectAnswer;
  final void Function()? onWrongAnswer;

  /// Fired when tier 3 opens or closes its "what would you do?" step, so the
  /// Flutter overlay can change the printed prompt to match the spoken one. The
  /// two questions are different questions and the bubble must not keep asking
  /// the first while the child is answering the second.
  final void Function(bool inResponseStep)? onResponseStepChanged;

  final VoidCallback? onPlayCorrectSfx;
  final VoidCallback? onPlayWrongSfx;
  final VoidCallback? onPlayTapSfx;
  final VoidCallback? onPlayLevelCompleteSfx;
  final VoidCallback? onPlayGameCompleteSfx;

  /// Names the emotion the child just found — "Malungkot" — rather than
  /// praising the tap. See [AnswerLabel]: naming turns each success into one
  /// more paired exposure to the emotion word, which is the vocabulary this
  /// game exists to build.
  final AnswerLabelCallback? onPlayCorrectVo;

  /// The gently-retry line. It must read as "look again" — see the class doc.
  final VoidCallback? onPlayWrongVo;
  final VoidCallback? onPlayInstructionVo;

  /// Narrates the situation that just came up, by `EmotionScene.id` — "His ice
  /// cream fell down." Fired once per trial, as the picture appears.
  ///
  /// The caption is printed under the picture, but a child who cannot read it
  /// is being asked about an event nobody told them about; spoken, the event is
  /// given and only the feeling is left to work out. The handler is expected to
  /// ask the question in the same breath, which is why [onPlayInstructionVo] is
  /// not fired for the opening trial when this callback is supplied.
  final void Function(String sceneId)? onPlaySceneVo;

  final VoidCallback? onPlayTransitionVo;
  final VoidCallback? onPlayCelebrationVo;

  final int totalRounds;

  /// Scenes per round. Four rounds is fixed across the app; this is the knob.
  final int itemsPerRound;

  final String childId;

  /// The child's chosen character ([MascotCharacter.name]: bps / reiz /
  /// lexianne), so the buddy whose feelings the child reads is the same figure
  /// they picked and see as the mascot — not a stranger. Falls back to the
  /// generic face art when a character's own emotion set is missing.
  final String character;

  final String? gameVersion;
  final DifficultyProfile profile;

  /// Localized strings (English / Tagalog / Cebuano) for on-screen labels.
  final AppStrings strings;

  // ── Session totals ───────────────────────────────────────────────────
  int _currentRound = 0;
  int _trialInRound = 0;
  int _score = 0;
  int _errorCount = 0;
  int _totalResponseTimeMs = 0;
  int _hintCount = 0;

  /// `'<target>-><chosen>'` → how many times. The clinical output.
  final Map<String, int> _confusionPairs = {};

  /// Tier-2 wrong taps, split by whether they landed on the near-miss card.
  int _tier2Errors = 0;
  int _tier2NearMissErrors = 0;

  /// Tier-3's second question, scored separately from recognition: knowing the
  /// feeling and knowing what to do about it are different skills, and a child
  /// can be fluent at one and blank at the other.
  int _responseStepsPresented = 0;
  int _responseStepsCorrect = 0;
  int _responseStepErrors = 0;

  /// How many trials resolved at each prompt level (0 = independent).
  final Map<int, int> _promptLevelCounts = {};

  // ── Trial state ──────────────────────────────────────────────────────
  late final ScenePanel _panel;
  late final BuddyFace _buddy;
  final List<EmotionCard> _cards = [];
  final List<ResponseCard> _responseCards = [];

  EmotionScene? _scene;
  List<Emotion> _options = const [];
  DateTime? _trialStart;
  int _wrongThisTrial = 0;
  int _promptLevelThisTrial = 0;
  int _hintsUsedThisRound = 0;
  bool _inResponseStep = false;
  bool _resolving = false;

  /// Set once [_finish] has banked the session, so tearing the screen down
  /// afterwards does not report a completed game as an early exit.
  bool _finished = false;
  GhostHand? _ghostHand;

  /// Scenes not yet used this session. Drawn from without replacement so a
  /// twelve-trial session meets ten different situations before it repeats one.
  final List<EmotionScene> _bag = [];

  Timer? _idleTimer;
  Timer? _advanceTimer;

  /// Un-dims a card after a wrong tap. Kept apart from [_advanceTimer] so a
  /// settle-back never cancels the trial advance it happens to overlap.
  Timer? _settleTimer;

  late final AdaptiveDifficulty _adaptive = AdaptiveDifficulty(profile);
  DifficultyProfile get _tier => _adaptive.effective;

  final math.Random _random = math.Random();

  /// Whether any prompting at all is allowed.
  ///
  /// Assessment suppresses the whole hierarchy, which is a deliberate departure
  /// from the other games (they run the assessment profile with unlimited
  /// hints). Here `prompt_level_used` *is* one of the reported measures, so a
  /// prompt does not merely help the child — it overwrites the number the
  /// session exists to collect.
  bool get _promptsAllowed =>
      !identical(profile, DifficultyProfile.assessment) && !_tier.noHints;

  bool get _hintBudgetLeft =>
      _tier.unlimitedHints || _hintsUsedThisRound < (_tier.hintsPerRound ?? 0);

  /// Whether this tier asks the follow-up "what would you do?" question.
  bool get _hasResponseStep => _tier.level >= 3;

  /// How many face cards this trial offers.
  ///
  /// Tier 2 ramps 3 → 4 across the session rather than picking at random: a
  /// child meeting the game for the first time gets the smaller field, and the
  /// ramp is deterministic so two sessions are comparable.
  int get _cardCount {
    switch (_tier.level) {
      case 1:
        return 2;
      case 3:
        return 4;
      default:
        return _currentRound < 2 ? 3 : 4;
    }
  }

  // ── Lifecycle ────────────────────────────────────────────────────────

  @override
  Color backgroundColor() => const Color(0x00000000); // Transparent

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Decode before the first trial is laid out. Awaited so a child never sees
    // the painted face swap to the picture mid-trial — a face changing
    // appearance under them is exactly the unpredictability this app avoids,
    // and here it would change the very thing they are being asked to read.
    await EmotionArtCache.ensureLoaded(character);

    analyticsInitialize(
      gameId: 'anong_nararamdaman',
      childId: childId,
      totalRounds: totalRounds,
      gameVersion: gameVersion,
    );
    analyticsStartSession();

    _panel = ScenePanel(
        language: strings.language,
        position: Vector2.zero(),
        size: Vector2.all(1));
    _buddy = BuddyFace(position: Vector2.zero(), size: Vector2.all(1));
    add(_panel);
    add(_buddy);

    // When scenes are narrated, the opening question rides along with the first
    // scene's narration instead of being asked here — asking twice in the same
    // breath would drop one of the two lines to the last-claim-wins floor.
    if (onPlaySceneVo == null) onPlayInstructionVo?.call();
    _startRound();
  }

  @override
  void onGameResize(Vector2 newSize) {
    super.onGameResize(newSize);
    if (isLoaded) _layout();
  }

  @override
  void onRemove() {
    invalidateLifecycle();
    _cancelTimers();
    super.onRemove();
  }

  /// Called by `GameWidget` when the screen goes away.
  ///
  /// Both this and [onRemove] are needed, and only this one actually fires in
  /// the common case: the root game is never *removed* from a parent, so
  /// `onRemove` runs only if something removes the game deliberately. Without
  /// this override the idle prompt keeps re-arming itself after the screen is
  /// gone — a timer holding a dead game alive for the rest of the session.
  @override
  void onDispose() {
    invalidateLifecycle();
    _cancelTimers();
    // A child who leaves mid-game has abandoned the session, and saying so is
    // both the honest record and what stops the analytics mixin's own
    // second-by-second idle timer running on forever behind a screen nobody is
    // looking at.
    if (!_finished) analyticsRecordExit();
    super.onDispose();
  }

  void _cancelTimers() {
    _idleTimer?.cancel();
    _advanceTimer?.cancel();
    _settleTimer?.cancel();
  }

  // ── Round / trial setup ──────────────────────────────────────────────

  void _startRound() {
    _trialInRound = 0;
    _hintsUsedThisRound = 0;
    _adaptive.startRound();
    analyticsStartRound(roundNumber: _currentRound + 1);
    _startTrial();
  }

  void _startTrial() {
    _clearCards();
    _clearResponseCards();
    _hideGhostHand();

    _inResponseStep = false;
    _resolving = false;
    _wrongThisTrial = 0;
    _promptLevelThisTrial = 0;
    onResponseStepChanged?.call(false);

    final scene = _nextScene();
    _scene = scene;
    _options = _optionsFor(scene.emotion);

    _panel
      ..scene = scene
      ..visible = true;
    _buddy.emotion = scene.emotion;

    for (final emotion in _options) {
      final card = EmotionCard(
        emotion: emotion,
        language: strings.language,
        position: Vector2.zero(),
        size: Vector2.all(1),
      );
      _cards.add(card);
      add(card);
    }

    _layout();
    // The transition starts after the cards exist, so the change on the face is
    // the last thing to move and therefore the thing attention lands on.
    _buddy.playTransition();

    // Narrate what happened, now that there is something on screen to narrate.
    onPlaySceneVo?.call(scene.id);

    _trialStart = DateTime.now();
    analyticsShowStimulus();
    analyticsAddRoundData('scene_$_trialInRound', scene.id);
    _armIdle();
  }

  /// Draws the next situation, refilling and reshuffling the bag when empty.
  EmotionScene _nextScene() {
    if (_bag.isEmpty) {
      _bag.addAll(kEmotionScenes);
      _bag.shuffle(_random);
    }
    return _bag.removeLast();
  }

  /// The face cards offered against [target], shuffled.
  ///
  /// The rule differs per tier and the difference is the point:
  ///
  /// * **Tier 1** draws every distractor from [farFrom] — no card on screen is
  ///   confusable with the answer. A beginner is discriminating happy from sad,
  ///   not sad from scared.
  /// * **Tiers 2 and 3** include **exactly one** card that is a near-miss of
  ///   the target, and fill the rest from [farFrom]. Exactly one, not "at least
  ///   one": two near-misses makes the trial a coin-flip between three
  ///   plausible readings, and a wrong tap then no longer identifies *which*
  ///   confusion the child has. The whole value of `near_miss_rate` rests on
  ///   there being one such card to land on.
  @visibleForTesting
  List<Emotion> optionsFor(Emotion target, {int? cardCount}) =>
      _optionsFor(target, cardCount: cardCount);

  List<Emotion> _optionsFor(Emotion target, {int? cardCount}) {
    final count = cardCount ?? _cardCount;
    final far = farFrom(target)..shuffle(_random);
    final options = <Emotion>[target];

    if (_tier.level >= 2) {
      final near = nearTo(target)..shuffle(_random);
      // Every emotion has at least one near-miss partner by construction, but
      // fall through gracefully rather than trusting that forever.
      if (near.isNotEmpty) options.add(near.first);
    }

    for (final e in far) {
      if (options.length >= count) break;
      options.add(e);
    }

    // Only reachable if `far` ran dry, which needs a much larger card count
    // than any tier asks for. Top up from anything unused so the row is never
    // short.
    if (options.length < count) {
      for (final e in Emotion.values) {
        if (options.length >= count) break;
        if (!options.contains(e)) options.add(e);
      }
    }

    return options..shuffle(_random);
  }

  /// The caring-response cards, shuffled.
  ///
  /// All four are offered every time, and all four are kind things to do —
  /// none of the distractors is unkind, because a card showing the wrong way to
  /// treat a friend is a card the child has now been shown. The distinction the
  /// step asks for is *which kindness fits this situation*, not kind versus
  /// cruel.
  List<CaringResponse> _responseOptions() =>
      CaringResponse.values.toList()..shuffle(_random);

  // ── Layout ───────────────────────────────────────────────────────────
  //
  // Landscape, top to bottom:
  //
  //   ├─ kTopOverlayBand ─────────────────────────────────────────────┤
  //     ┌───────────────┐            (  ◕ ‿ ◕  )   the buddy's face
  //     │  what         │             the answer lives here
  //     │  happened     │
  //     └───────────────┘
  //     ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐   the face cards
  //     │ 😀   │ │ 😢   │ │ 😨   │ │ 😮   │
  //     └──────┘ └──────┘ └──────┘ └──────┘
  //
  // Everything sits below [kTopOverlayBand] so the Flutter overlay never eats a
  // touch meant for a card.

  void _layout() {
    if (size.x <= 0 || size.y <= 0) return;

    final usableTop = kTopOverlayBand + 8;
    final usableHeight = size.y - usableTop - 12;
    if (usableHeight <= 0) return;

    // The cards get the larger share: they are what the child has to hit.
    final cardBand = usableHeight * 0.54;
    final upperBand = usableHeight - cardBand - 10;

    final panelH = upperBand;
    final panelW = math.min(panelH * 0.92, size.x * 0.34);
    _panel
      ..position = Vector2(size.x * 0.28, usableTop + upperBand / 2)
      ..size = Vector2(panelW, panelH);

    final faceSize = math.min(upperBand * 0.94, size.x * 0.28);
    _buddy
      ..position = Vector2(size.x * 0.70, usableTop + upperBand / 2)
      ..size = Vector2.all(faceSize);

    final row = _inResponseStep
        ? _responseCards.cast<ChoiceCard>()
        : _cards.cast<ChoiceCard>();
    if (row.isEmpty) return;

    final cardH = cardBand;
    // The gap has to clear twice the touch slack (see [ChoiceCard]) so two
    // inflated hit boxes never overlap; 0.24 of a card width does at every
    // count this game uses.
    var cardW = math.min(cardH * 0.86, (size.x - 48) / row.length * 0.78);
    var gap = cardW * 0.24;
    final rowW = row.length * cardW + (row.length - 1) * gap;
    if (rowW > size.x - 32) {
      final shrink = (size.x - 32) / rowW;
      cardW *= shrink;
      gap *= shrink;
    }
    final width = row.length * cardW + (row.length - 1) * gap;
    final startX = (size.x - width) / 2 + cardW / 2;
    final y = usableTop + upperBand + 10 + cardH / 2;

    for (var i = 0; i < row.length; i++) {
      row[i]
        ..position = Vector2(startX + i * (cardW + gap), y)
        ..size = Vector2(cardW, cardH);
    }
  }

  // ── Input ────────────────────────────────────────────────────────────

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    if (_resolving) return;

    final point = event.localPosition;

    if (_inResponseStep) {
      for (final card in _responseCards) {
        if (card.containsLocal(point)) {
          _answerResponse(card);
          return;
        }
      }
    } else {
      for (final card in _cards) {
        if (card.containsLocal(point)) {
          _answerEmotion(card);
          return;
        }
      }
    }

    // Empty canvas. Recorded so overall_invalid_touch_count reflects genuinely
    // undirected taps rather than mis-hits on real targets — which the inflated
    // card bounds already absorb.
    analyticsRecordTouch(Offset(point.x, point.y), isValid: false);
    analyticsRecordOffTaskAction(actionType: 'tap_empty_canvas');
    _resetIdle();
  }

  // ── Answering: which feeling? ────────────────────────────────────────

  void _answerEmotion(EmotionCard card) {
    final scene = _scene;
    if (scene == null) return;

    onPlayTapSfx?.call();
    final elapsed = _trialStart == null
        ? 0
        : DateTime.now().difference(_trialStart!).inMilliseconds;

    if (card.emotion == scene.emotion) {
      _resolving = true;
      _idleTimer?.cancel();
      card.chosen = true;
      card.pulsing = false;
      _hideGhostHand();

      _score++;
      _totalResponseTimeMs += elapsed;
      _promptLevelCounts.update(
          _promptLevelThisTrial, (n) => n + 1, ifAbsent: () => 1);
      _adaptive.recordCorrect();

      analyticsRecordValidAction();
      analyticsRecordCorrect(extraData: {
        'scene': scene.id,
        'emotion': scene.emotion.slug,
        'options': _options.map((e) => e.slug).join('|'),
        'prompt_level': _promptLevelThisTrial,
        'response_time_ms': elapsed,
      });

      onPlayCorrectSfx?.call();
      // Say the emotion back in the child's language. Carried as the slug, not
      // the printed label — the audio layer holds the translations.
      onPlayCorrectVo?.call(AnswerLabel(emotion: scene.emotion.slug));
      onCorrectAnswer?.call();

      if (_hasResponseStep) {
        _advanceTimer =
            Timer(const Duration(milliseconds: 700), _startResponseStep);
      } else {
        _advanceTimer = Timer(const Duration(milliseconds: 900), _nextTrial);
      }
      return;
    }

    _rejectEmotion(card, scene);
  }

  /// A wrong face. Dims, settles back, the buddy replays the feeling — and
  /// nothing anywhere says the child read the feeling wrongly.
  void _rejectEmotion(EmotionCard card, EmotionScene scene) {
    _wrongThisTrial++;
    _errorCount++;

    final key = '${scene.emotion.slug}->${card.emotion.slug}';
    _confusionPairs.update(key, (n) => n + 1, ifAbsent: () => 1);

    if (_tier.level == 2) {
      _tier2Errors++;
      if (isNearMiss(card.emotion, scene.emotion)) _tier2NearMissErrors++;
    }

    analyticsRecordRetry();
    analyticsRecordWrong(extraData: {
      'scene': scene.id,
      'expected': scene.emotion.slug,
      'chosen': card.emotion.slug,
      'near_miss': isNearMiss(card.emotion, scene.emotion),
    });
    if (_adaptive.recordError()) {
      analyticsAddRoundData('difficulty_step_down', _tier.level);
    }

    card.dimmed = true;
    onPlayWrongSfx?.call();
    onPlayWrongVo?.call();
    onWrongAnswer?.call();

    // Settles back rather than staying dimmed: the card the child chose is
    // still a card they may choose again, and leaving it greyed out is a
    // running record of a mistake sitting on screen.
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: 700), () {
      card.dimmed = false;
    });

    _escalatePrompt();
    _resetIdle();
  }

  // ── Answering: what would you do? ────────────────────────────────────

  void _startResponseStep() {
    final scene = _scene;
    if (scene == null) return;

    _clearCards();
    _inResponseStep = true;
    _resolving = false;
    _wrongThisTrial = 0;
    _responseStepsPresented++;

    // The picture goes away; the face stays. See [ScenePanel].
    _panel.visible = false;
    onResponseStepChanged?.call(true);

    for (final response in _responseOptions()) {
      final card = ResponseCard(
        response: response,
        language: strings.language,
        position: Vector2.zero(),
        size: Vector2.all(1),
      );
      _responseCards.add(card);
      add(card);
    }

    _layout();
    _buddy.playTransition();
    _trialStart = DateTime.now();
    analyticsShowStimulus();
    _armIdle();
  }

  void _answerResponse(ResponseCard card) {
    final scene = _scene;
    if (scene == null) return;

    onPlayTapSfx?.call();

    if (card.response == scene.response) {
      _resolving = true;
      _idleTimer?.cancel();
      card.chosen = true;
      _hideGhostHand();

      // First-try only. A response found after two wrong taps is a response the
      // game narrowed down for them, and scoring it as known would inflate the
      // one metric that is meant to separate "feels it" from "knows what to do".
      if (_wrongThisTrial == 0) _responseStepsCorrect++;

      analyticsRecordCorrect(extraData: {
        'step': 'response',
        'scene': scene.id,
        'response': scene.response.slug,
        'first_try': _wrongThisTrial == 0,
      });

      onPlayCorrectSfx?.call();
      onCorrectAnswer?.call();
      _advanceTimer = Timer(const Duration(milliseconds: 900), _nextTrial);
      return;
    }

    _wrongThisTrial++;
    _responseStepErrors++;
    analyticsRecordWrong(extraData: {
      'step': 'response',
      'scene': scene.id,
      'expected': scene.response.slug,
      'chosen': card.response.slug,
    });

    card.dimmed = true;
    onPlayWrongSfx?.call();
    onPlayWrongVo?.call();
    onWrongAnswer?.call();
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: 700), () {
      card.dimmed = false;
    });

    // The response step gets a shorter hierarchy — pulse, then the ghost hand.
    // Re-animating the face would be answering the previous question, and
    // narrowing the field is meaningless when every card is a kind thing to do.
    if (_promptsAllowed && _hintBudgetLeft) {
      if (_wrongThisTrial == 2) {
        _spendHint('pulse_correct_response');
        _pulseCorrectResponse();
      } else if (_wrongThisTrial >= 3) {
        _spendHint('ghost_hand_response');
        _ghostTapCorrectResponse();
      }
    }
    _resetIdle();
  }

  // ── Prompt hierarchy ─────────────────────────────────────────────────
  //
  // ABA least-to-most, escalating one rung per wrong tap:
  //
  //   1. the buddy's face replays neutral → the emotion
  //   2. the incorrect cards fade back, leaving two
  //   3. the correct card pulses
  //   4. the ghost hand taps it
  //
  // Rung 1 first because it is the only one that teaches: it hands the child
  // more of the *stimulus* rather than less of the *field*. Everything below it
  // makes the answer easier to guess; only the replay makes the feeling easier
  // to read.

  void _escalatePrompt() {
    if (!_promptsAllowed || !_hintBudgetLeft) return;

    switch (_wrongThisTrial) {
      case 1:
        _promptLevelThisTrial = 1;
        _spendHint('replay_expression');
        _buddy.playTransition();
        break;
      case 2:
        _promptLevelThisTrial = 2;
        _spendHint('narrow_to_two');
        _narrowToTwo();
        break;
      case 3:
        _promptLevelThisTrial = 3;
        _spendHint('pulse_correct');
        _pulseCorrect();
        break;
      default:
        _promptLevelThisTrial = 4;
        _spendHint('ghost_hand');
        _pulseCorrect();
        _ghostTapCorrect();
        break;
    }
  }

  void _spendHint(String type) {
    _hintCount++;
    _hintsUsedThisRound++;
    analyticsRecordHint(hintType: type);
  }

  /// Fades every card but the answer and one distractor, leaving a two-choice
  /// field. The distractor kept is the *hardest* remaining one, so the trial
  /// stays a real discrimination rather than becoming a free point.
  void _narrowToTwo() {
    final scene = _scene;
    if (scene == null) return;
    final wrong = _cards.where((c) => c.emotion != scene.emotion).toList();
    if (wrong.length <= 1) return;

    wrong.sort((a, b) {
      final an = isNearMiss(a.emotion, scene.emotion) ? 0 : 1;
      final bn = isNearMiss(b.emotion, scene.emotion) ? 0 : 1;
      return an.compareTo(bn);
    });
    for (var i = 1; i < wrong.length; i++) {
      wrong[i].dimmed = true;
    }
  }

  void _pulseCorrect() {
    final scene = _scene;
    if (scene == null) return;
    for (final card in _cards) {
      card.pulsing = card.emotion == scene.emotion;
    }
  }

  void _pulseCorrectResponse() {
    final scene = _scene;
    if (scene == null) return;
    for (final card in _responseCards) {
      card.pulsing = card.response == scene.response;
    }
  }

  void _ghostTapCorrect() {
    final scene = _scene;
    if (scene == null) return;
    for (final card in _cards) {
      if (card.emotion == scene.emotion) {
        _showGhostHand(card);
        return;
      }
    }
  }

  void _ghostTapCorrectResponse() {
    final scene = _scene;
    if (scene == null) return;
    for (final card in _responseCards) {
      if (card.response == scene.response) {
        _showGhostHand(card);
        return;
      }
    }
  }

  void _showGhostHand(ChoiceCard card) {
    _hideGhostHand(); // never more than one demo at a time
    final hand = GhostHand.tap(
      at: card.position.clone(),
      handSize: card.size.x * 0.55,
    );
    _ghostHand = hand;
    add(hand);
  }

  void _hideGhostHand() {
    if (_ghostHand?.isMounted ?? false) _ghostHand?.removeFromParent();
    _ghostHand = null;
  }

  // ── Idle prompting ───────────────────────────────────────────────────

  void _armIdle() {
    _idleTimer?.cancel();
    // With no answer hints available, the wait is longer and what comes back is
    // the question, not the answer — the child is re-oriented, never abandoned.
    final delay = _promptsAllowed && _hintBudgetLeft
        ? _tier.idleHintDelay
        : _tier.reorientDelay;
    _idleTimer = Timer(delay, () {
      if (isRemoved || _resolving) return;
      if (!_promptsAllowed || !_hintBudgetLeft) {
        onPlayInstructionVo?.call();
        analyticsRecordHint(hintType: 'reorient_instruction');
      } else {
        analyticsRecordIdleTime(delay.inSeconds);
        _spendHint('idle_replay_expression');
        // An idle child is one who has not found the face yet, so the idle
        // prompt is rung one — never a shortcut to the answer.
        _buddy.playTransition();
      }
      _armIdle();
    });
  }

  void _resetIdle() {
    _idleTimer?.cancel();
    _armIdle();
  }

  // ── Advancing ────────────────────────────────────────────────────────

  void _nextTrial() {
    _idleTimer?.cancel();
    _trialInRound++;

    if (_trialInRound < itemsPerRound) {
      _startTrial();
      return;
    }

    analyticsCompleteRound(successful: true);
    _currentRound++;
    onStepChanged(_currentRound);

    if (_currentRound >= totalRounds) {
      _clearCards();
      _clearResponseCards();
      _advanceTimer = Timer(const Duration(milliseconds: 700), _finish);
      return;
    }

    onPlayLevelCompleteSfx?.call();
    onPlayTransitionVo?.call();
    _advanceTimer = Timer(const Duration(milliseconds: 1200), _startRound);
  }

  void _clearCards() {
    for (final c in _cards) {
      c.removeFromParent();
    }
    _cards.clear();
  }

  void _clearResponseCards() {
    for (final c in _responseCards) {
      c.removeFromParent();
    }
    _responseCards.clear();
  }

  // ── Completion ───────────────────────────────────────────────────────

  void _finish() {
    if (!tryBeginCompletion()) return;
    _idleTimer?.cancel();
    _advanceTimer?.cancel();
    _settleTimer?.cancel();
    _hideGhostHand();

    _finished = true;
    analyticsMarkCompleted();
    analyticsAddGameSpecificMetric('near_miss_rate', nearMissRate);
    analyticsAddGameSpecificMetric(
        'response_step_accuracy', responseStepAccuracy);
    analyticsAddGameSpecificMetric('hint_count', _hintCount);
    analyticsCompleteSession();

    onPlayGameCompleteSfx?.call();
    onPlayCelebrationVo?.call();

    onGameComplete(
      score: _score,
      totalItems: totalRounds * itemsPerRound,
      errorCount: _errorCount,
      totalResponseTimeMs: _totalResponseTimeMs,
      extras: {
        // The clinical output: which emotion was chosen for which target.
        'confusion_pairs': Map<String, int>.from(_confusionPairs),
        'near_miss_rate': nearMissRate,
        'response_step_accuracy': responseStepAccuracy,
        'response_steps_presented': _responseStepsPresented,
        'response_step_errors': _responseStepErrors,
        // Histogram, not a mean: "eight trials independent, four at rung one"
        // is the shape a therapist reads, and averaging it away loses it.
        'prompt_level_used': {
          for (final e in _promptLevelCounts.entries) '${e.key}': e.value
        },
        'hint_count': _hintCount,
        'difficulty_level': profile.level,
      },
      analytics: analyticsSession,
    );
  }

  /// Of the tier-2 wrong taps, the share that landed on the paired emotion
  /// rather than somewhere unrelated.
  ///
  /// A high rate is the *better* result of the two: the child is reading the
  /// face and losing a fine distinction. A low rate over the same error count
  /// means the taps were not tracking the face at all.
  ///
  /// −1 when the tier produced no errors to classify, so a session with nothing
  /// to say is distinguishable from one that says "never near-missed".
  double get nearMissRate =>
      _tier2Errors == 0 ? -1 : _tier2NearMissErrors / _tier2Errors;

  /// Tier 3's second question, first-try. −1 when it was never asked.
  double get responseStepAccuracy => _responseStepsPresented == 0
      ? -1
      : _responseStepsCorrect / _responseStepsPresented;

  /// The confusion map so far, for tests and for the screen's debug overlay.
  @visibleForTesting
  Map<String, int> get confusionPairs => Map.unmodifiable(_confusionPairs);

  /// The cards currently on offer, for tests.
  @visibleForTesting
  List<Emotion> get currentOptions => List.unmodifiable(_options);

  /// The feeling the current trial is asking about, for tests.
  @visibleForTesting
  Emotion? get currentTarget => _scene?.emotion;
}
