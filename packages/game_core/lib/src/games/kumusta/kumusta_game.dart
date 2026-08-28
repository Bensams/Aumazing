import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';

import '../../analytics/enhanced_analytics_mixin.dart';
import '../../analytics/models/models.dart';
import '../../config/adaptive_difficulty.dart';
import '../../config/difficulty_profile.dart';
import '../../config/round_policy.dart';
import '../shared/game_layout.dart';
import '../shared/ghost_hand.dart';
import 'buddy_art_cache.dart';
import 'components/buddy.dart';
import 'components/greeting_button.dart';
import 'greetings.dart';
import '../shared/game_lifecycle_guard.dart';

/// "Kumusta!" — a buddy offers a greeting; the child answers it.
///
/// The skill is **responding to a social bid**: noticing that someone has
/// reached out, reading which gesture they used, and answering in kind. It is
/// the one item on the assessment's socialInteraction axis that a solo tablet
/// game can honestly measure, because the child's answer is a discrete,
/// timestamped choice rather than an adult's rating of "engagement".
///
/// Three rules shape everything below, and each one costs the game something:
///
/// * **No time pressure.** There is no response window and nothing expires.
///   A child who takes forty seconds to answer has still answered. This costs
///   the "missed trial" signal the attention games rely on; latency carries
///   that information instead, and slowness is reported, never punished.
/// * **The buddy never gives up.** The offer holds until it is answered. A bid
///   that withdraws would teach that hesitating makes people leave.
/// * **Nothing is ever removed.** A wrong tap bounces the card back and the
///   buddy re-offers the same greeting. No card is disabled, dimmed, or taken
///   away, so a child who taps to explore never shrinks the board.
class KumustaGame extends FlameGame
    with GameLifecycleGuard, TapCallbacks, EnhancedGameplayAnalyticsMixin {
  KumustaGame({
    required this.onStepChanged,
    required this.onGameComplete,
    required this.childId,
    this.character = 'bps',
    this.totalRounds = GameRoundPolicy.standardRoundCount,
    this.gameVersion,
    this.profile = DifficultyProfile.medium,
    this.onCorrectGreeting,
    this.onWrongAnswer,
    // Audio event callbacks (optional, wired by screen wrappers)
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
    this.onBuddyGreets,
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

  /// Fired when the child returns a greeting correctly. The Flutter layer uses
  /// it for haptics and the mascot's nod.
  final void Function()? onCorrectGreeting;

  /// Fired on a wrong card. Pairs with the gentle SFX and the reassuring line.
  final void Function()? onWrongAnswer;

  // ── Audio event callbacks ────────────────────────────────────────────
  final VoidCallback? onPlayCorrectSfx;
  final VoidCallback? onPlayWrongSfx;
  final VoidCallback? onPlayTapSfx;
  final VoidCallback? onPlayLevelCompleteSfx;
  final VoidCallback? onPlayGameCompleteSfx;

  final VoidCallback? onPlayCorrectVo;
  final VoidCallback? onPlayWrongVo;
  final VoidCallback? onPlayInstructionVo;

  /// Spoken with the pointing hand once the bid has gone unanswered — the
  /// verbal rung of the prompt hierarchy, above the gestural one.
  final VoidCallback? onPlayHintVo;
  final VoidCallback? onPlayTransitionVo;
  final VoidCallback? onPlayCelebrationVo;

  /// Fired when the buddy offers a greeting, carrying which one, so the screen
  /// can speak the matching line ("Kumusta!", "Apir!"). The greeting is the
  /// *stimulus*; the wrapper owns the voice pack, so it has to be told.
  final void Function(Greeting greeting)? onBuddyGreets;

  final int totalRounds;
  final String childId;
  final String? gameVersion;

  /// `bps` or `reiz`. Chosen once by the screen and held for the whole session:
  /// the child is building a relationship with one buddy, not auditioning a
  /// cast, and swapping mid-session would change the stimulus underneath a
  /// latency comparison.
  final String character;

  /// Prompt policy, choice count, and whether rounds ask for a second turn.
  final DifficultyProfile profile;

  // ── Game state ───────────────────────────────────────────────────────
  int _currentRound = 0;
  int _score = 0;
  int _errorCount = 0;
  int _totalResponseTimeMs = 0;

  /// Taps on the wrong greeting. The discrimination signal: the child noticed
  /// the bid but read the wrong gesture.
  int _wrongGreetings = 0;

  /// Rounds answered with no prompt at all — the headline social measure.
  /// A child who returns greetings unprompted is doing the target skill.
  int _unpromptedRounds = 0;

  /// Greetings the child *started* (tier 3's second turn). Initiation is the
  /// harder half of the skill, so it is reported separately from the score.
  int _initiatedGreetings = 0;

  /// Latencies, in ms, from the buddy finishing its offer to the correct tap.
  /// Reported, never scored: see the "no time pressure" rule above.
  ///
  /// This is the *greeting latency* — the social-responsiveness measure. It
  /// coincides with the shared response time in this game only because a
  /// greeting has nothing to attend to before the bid arrives: [_offeredAt] is
  /// set when the buddy's gesture finishes, so the clock starts at the moment
  /// the child is actually being greeted, not when the round opened.
  final List<int> _responseTimes = [];

  /// The prompt rung each scored round was answered from. 0 means the child
  /// greeted back with no help at all — the number a therapist reads first.
  final List<int> _promptLevels = [];

  /// Tier-3 second turns offered, and how many the child opened without
  /// needing a prompt.
  ///
  /// Correctness is deliberately not the measure: on the child's own turn
  /// whatever they pick is right by design, so scoring it would report a
  /// perfect run for every child. What separates a child who is *conversing*
  /// from one who is *mimicking* is whether they start the second exchange
  /// unaided, so that is what is counted.
  int _returnTurnsOffered = 0;
  int _returnTurnsUnprompted = 0;

  int _hintCount = 0;
  int _hintsUsedThisRound = 0;
  bool _promptedThisRound = false;

  /// Which greeting the buddy is offering, and the cards on screen for it.
  Greeting? _target;
  final List<GreetingButton> _buttons = [];

  Buddy? _buddy;
  KumustaBuddyArt? _art;

  /// When the offer finished playing and the child's turn began.
  DateTime? _offeredAt;
  bool _awaitingAnswer = false;

  /// Tier 3 asks the child to *start* a greeting after returning one — the
  /// second half of a real exchange. True while that second turn is pending.
  bool _inReturnTurn = false;

  Timer? _offerTimer;
  Timer? _hintTimer;
  Timer? _feedbackTimer;

  late final AdaptiveDifficulty _adaptive = AdaptiveDifficulty(profile);
  DifficultyProfile get _tier => _adaptive.effective;

  bool get _hintBudgetLeft =>
      _tier.unlimitedHints || _hintsUsedThisRound < (_tier.hintsPerRound ?? 0);

  final math.Random _random = math.Random();

  // ── Tier tuning ──────────────────────────────────────────────────────

  /// How many cards are on screen.
  ///
  /// Two on Easy is a genuine choice — not a single button the child cannot
  /// get wrong — while keeping the discrimination load near the floor. Four is
  /// the ceiling because every greeting in the set must stay large enough to
  /// hit comfortably on a phone.
  int get _choiceCount => switch (_tier.level) {
        1 => 2,
        2 => 3,
        _ => 4,
      };

  /// Whether the buddy relaxes back to a resting pose before the child answers.
  ///
  /// This is the real difficulty knob, and it is a *memory* one. On Easy the
  /// gesture is held, so the child can match what they see. From tier 2 the
  /// buddy lowers its hand after [_holdSeconds] and the child must answer from
  /// what they remember — which is what returning a greeting in a corridor
  /// actually demands.
  bool get _relaxesAfterOffer => _tier.level >= 2;

  /// How long the gesture is held before relaxing, when it relaxes at all.
  /// Long enough to be seen and named, short enough to still be a memory task.
  static const Duration _holdBeforeRelaxing = Duration(milliseconds: 2500);

  /// Tier 3 adds the second turn: the child greets first, unprompted.
  bool get _wantsReturnTurn => _tier.level >= 3;

  /// One colour per greeting, fixed for the whole session.
  ///
  /// Fixed, not shuffled, because a child who learns "the blue one is the
  /// wave" is using a legitimate strategy and pulling the rug would punish it.
  /// Colour is never the *only* difference — the glyphs differ by silhouette —
  /// so this stays an aid rather than a requirement.
  static const Map<Greeting, Color> _cardColors = {
    Greeting.wave: Color(0xFF7EC8E3), // sky
    Greeting.highFive: Color(0xFFF6B26B), // mango
    Greeting.fistBump: Color(0xFFA9DFBF), // leaf
    Greeting.thumbsUp: Color(0xFFC7B4EC), // taro
  };

  // ── Layout ───────────────────────────────────────────────────────────

  /// The card row sits along the bottom, under the buddy, so a hand reaching
  /// for it never covers the character it is answering.
  double get _rowHeight => math.min(size.y * 0.26, 190);

  double get _rowTop => size.y - _rowHeight - size.y * 0.05;

  Vector2 get _buddyRestPosition =>
      Vector2(size.x * 0.5, _rowTop - size.y * 0.04);

  Vector2 get _buddySize {
    final h = math.min((_rowTop - kTopOverlayBand) * 0.92, size.y * 0.46);
    return Vector2(h * 0.62, h);
  }

  @override
  Color backgroundColor() => const Color(0x00000000); // Transparent

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    analyticsInitialize(
      gameId: 'kumusta',
      childId: childId,
      totalRounds: totalRounds,
      gameVersion: gameVersion,
    );
    analyticsStartSession();

    // Best-effort: a buddy with no sheets still plays, painted.
    _art = await KumustaBuddyArt.load(character);

    _buddy = Buddy(art: _art, position: _buddyRestPosition, size: _buddySize);
    add(_buddy!);

    onPlayInstructionVo?.call();
    _startRound();
  }

  @override
  void onGameResize(Vector2 newSize) {
    super.onGameResize(newSize);
    _buddy
      ?..size = _buddySize
      ..moveRestTo(_buddyRestPosition);
    _layoutButtons();
  }

  @override
  void onRemove() {
    invalidateLifecycle();
    _cancelTimers();
    super.onRemove();
  }

  void _cancelTimers() {
    _offerTimer?.cancel();
    _hintTimer?.cancel();
    _feedbackTimer?.cancel();
    _offerTimer = _hintTimer = _feedbackTimer = null;
  }

  // ── Round flow ───────────────────────────────────────────────────────

  /// One greeting exchange per round: buddy arrives, offers, child answers,
  /// (tier 3) child starts one back. Four rounds — short enough that a 2–6
  /// year old finishes while still willing, long enough to see whether the
  /// unprompted rate is improving within the session.
  void _startRound() {
    if (isRemoved) return;

    _hintsUsedThisRound = 0;
    _promptedThisRound = false;
    _inReturnTurn = false;
    _adaptive.startRound();
    analyticsStartRound(roundNumber: _currentRound + 1);

    _target = _pickGreeting();
    _buildButtons();

    // The buddy walks in each round, so every round opens with the moment a
    // person *approaches* — the actual social cue the child must notice.
    _buddy?.arrive();

    // Offer once the walk-in has settled. On the first round the extra beat
    // also lets the instruction line finish before the gesture plays.
    _offerTimer = Timer(
      Duration(milliseconds: _currentRound == 0 ? 1900 : 1500),
      _offerGreeting,
    );
  }

  /// Picks the round's greeting, avoiding an immediate repeat so the child
  /// cannot clear the session by tapping the same card four times.
  Greeting _pickGreeting() {
    final pool = _availableGreetings();
    final previous = _target;
    final choices = pool.length > 1 && previous != null
        ? (pool.where((g) => g != previous).toList())
        : pool;
    return choices[_random.nextInt(choices.length)];
  }

  /// The greetings in play at this tier, always starting from [Greeting.wave]
  /// — the most familiar one — and widening as the tier rises.
  List<Greeting> _availableGreetings() =>
      Greeting.values.take(_choiceCount).toList();

  void _offerGreeting() {
    final target = _target;
    if (isRemoved || target == null) return;

    _buddy?.offer(target);
    analyticsShowStimulus();
    onBuddyGreets?.call(target);
    onPlayTapSfx?.call();

    _offeredAt = DateTime.now();
    _awaitingAnswer = true;

    if (_relaxesAfterOffer) {
      // The hand comes down; the offer stands. Answering now is a memory task.
      _offerTimer = Timer(_holdBeforeRelaxing, () {
        if (!_awaitingAnswer || isRemoved) return;
        _buddy?.setResting();
      });
    }

    _scheduleHint();
  }

  // ── The card row ─────────────────────────────────────────────────────

  void _buildButtons() {
    for (final b in _buttons) {
      b.removeFromParent();
    }
    _buttons.clear();

    final target = _target;
    if (target == null) return;

    // The target is always present; the rest are distractors drawn from the
    // tier's pool. Order is shuffled per round so position never becomes the
    // answer — the one thing that would let a child pass without looking.
    final options = <Greeting>{target};
    final pool = _availableGreetings().where((g) => g != target).toList()
      ..shuffle(_random);
    for (final g in pool) {
      if (options.length >= _choiceCount) break;
      options.add(g);
    }
    final ordered = options.toList()..shuffle(_random);

    for (final greeting in ordered) {
      final button = GreetingButton(
        greeting: greeting,
        color: _cardColors[greeting] ?? const Color(0xFF7EC8E3),
        position: Vector2.zero(),
        size: Vector2.all(1),
      );
      _buttons.add(button);
      add(button);
    }
    _layoutButtons();
  }

  void _layoutButtons() {
    if (_buttons.isEmpty || size.x == 0) return;

    final gap = size.x * 0.03;
    final available = size.x * 0.92 - gap * (_buttons.length - 1);
    // Square cards, capped by the row height so three or four still fit on a
    // phone in portrait without shrinking below a comfortable finger target.
    final side = math.min(available / _buttons.length, _rowHeight);
    final totalWidth = side * _buttons.length + gap * (_buttons.length - 1);
    final left = (size.x - totalWidth) / 2;
    final top = _rowTop + (_rowHeight - side) / 2;

    for (var i = 0; i < _buttons.length; i++) {
      _buttons[i]
        ..size = Vector2.all(side)
        ..position = Vector2(left + i * (side + gap), top);
    }
  }

  // ── Prompting ────────────────────────────────────────────────────────

  /// Least-to-most prompting on a timer, never on a deadline.
  ///
  /// Nothing here ends the round or scores against the child; each rung only
  /// makes the bid easier to answer. The escalation is the ABA hierarchy:
  /// repeat the gesture larger → highlight the card → point at it and say the
  /// word.
  void _scheduleHint() {
    if (_hintBudgetLeft) {
      _hintTimer = Timer(_tier.idleHintDelay, _promptOnce);
      return;
    }

    // No answer hints available — Hard, where the budget is zero from the
    // first frame, or a spent Medium budget. The child is still not left
    // alone: after the longer reorientDelay the bid is simply made again.
    //
    // This branch used to be a bare `return`, so on Hard no timer was ever
    // created and a child who looked away got nothing at all, indefinitely —
    // in the one game whose stated premise is that the buddy always waits and
    // never gives up. Every other game already falls through to reorientDelay
    // here; see sari_sari_sort's _startNoResponseTimer.
    _hintTimer = Timer(_tier.reorientDelay, _reorientOnce);
  }

  /// Re-play the bid without helping to answer it.
  ///
  /// Deliberately NOT counted as a prompt. It escalates nothing and reveals
  /// nothing — the child sees the same greeting they were already shown — so
  /// incrementing the hint counters would report a child who answered
  /// independently as having been helped, and promptLevelUsed is the number a
  /// therapist reads first. It is recorded under its own name instead.
  void _reorientOnce() {
    if (!_awaitingAnswer || isRemoved) return;

    final target = _target;
    if (target == null) return;

    // Re-offer at normal emphasis: enlarging it is rung 1 of the hierarchy,
    // and this rung is explicitly below that. Note this does not reset
    // _offeredAt — greeting latency is measured from the FIRST bid, because
    // that is when the child was greeted.
    _buddy?.offer(target);
    onPlayInstructionVo?.call();
    analyticsRecordHint(hintType: 'reoriented');

    _scheduleHint();
  }

  void _promptOnce() {
    if (!_awaitingAnswer || isRemoved) return;

    _hintCount++;
    _hintsUsedThisRound++;
    _promptedThisRound = true;

    final rung = _hintsUsedThisRound;
    final target = _target;
    if (target == null) return;

    if (rung == 1 && !_inReturnTurn) {
      // Rung 1 — repeat the bid, bigger and slower. Often all that is needed:
      // the child was looking away when it first played.
      _buddy?.offer(target, emphasis: 1.18);
      analyticsRecordHint(hintType: 'greeting_repeated');
    } else if (rung <= 2) {
      // Rung 2 — visual: highlight the matching card. On the child's own turn
      // this highlights a *suggestion*, not the answer; any card still counts.
      _buttonFor(target)?.startPulse();
      analyticsRecordHint(hintType: 'answer_highlighted');
    } else {
      // Rung 3 — gestural + verbal: point at it and say it.
      final button = _buttonFor(target);
      if (button != null) {
        button.startPulse();
        add(GhostHand.tap(at: button.centre));
      }
      analyticsRecordHint(hintType: 'answer_pointed');
      onPlayHintVo?.call();
    }

    analyticsRecordPrompt(promptType: 'level_$rung');
    // The buddy waits as long as it takes; keep escalating, then keep
    // repeating the top rung. It never stops offering.
    _scheduleHint();
  }

  GreetingButton? _buttonFor(Greeting greeting) {
    for (final b in _buttons) {
      if (b.greeting == greeting) return b;
    }
    return null;
  }

  void _clearPrompts() {
    _hintTimer?.cancel();
    _hintTimer = null;
    for (final b in _buttons) {
      b.stopPulse();
    }
    children.whereType<GhostHand>().forEach((h) => h.removeFromParent());
  }

  // ── Answering ────────────────────────────────────────────────────────

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    if (!_awaitingAnswer) return;

    final point = event.localPosition;
    final hit = _buttons
        .where((b) => b.containsPointGenerous(point))
        .fold<GreetingButton?>(null, (best, b) {
      if (best == null) return b;
      // Overlapping generous bounds: keep whichever centre is nearer, so the
      // inflated hit boxes never hand a tap to the wrong neighbour.
      return b.centre.distanceTo(point) < best.centre.distanceTo(point)
          ? b
          : best;
    });

    if (hit == null) {
      // A tap on empty canvas. Logged for the touch-pattern features, but it
      // is not an error: exploring the screen is not a wrong greeting.
      analyticsRecordTouch(Offset(point.x, point.y), isValid: false);
      analyticsRecordOffTaskAction(actionType: 'tap_off_target');
      return;
    }

    analyticsRecordTouch(Offset(point.x, point.y), isValid: true);

    // On the child's own turn there is no wrong answer: they are choosing
    // which greeting to offer, and the buddy will return whichever it is.
    if (_inReturnTurn) {
      _target = hit.greeting;
      _resolveCorrect(hit);
      return;
    }

    if (hit.greeting == _target) {
      _resolveCorrect(hit);
    } else {
      _resolveWrong(hit);
    }
  }

  /// A wrong card: acknowledge it, re-offer, and let the child try again.
  ///
  /// Nothing is removed and the round does not end. The buddy re-offers the
  /// same greeting, which is both the kindest response and the most useful
  /// one — the child gets another look at the gesture they misread.
  void _resolveWrong(GreetingButton button) {
    _wrongGreetings++;
    _errorCount++;

    analyticsRecordWrong(extraData: {
      'chose': button.greeting.slug,
      'expected': _target?.slug,
    });
    analyticsRecordRetry();
    _adaptive.recordError();

    button.rejectGently();
    onPlayWrongSfx?.call();
    onPlayWrongVo?.call();
    onWrongAnswer?.call();

    final target = _target;
    if (target != null) {
      // Show it again straight away — a wrong answer earns another model, not
      // a pause. Counts as a prompt for reporting, since the child saw the
      // gesture again before answering.
      _buddy?.offer(target, emphasis: 1.10);
      _promptedThisRound = true;
    }
  }

  void _resolveCorrect(GreetingButton button) {
    _awaitingAnswer = false;
    _clearPrompts();

    final rt = _offeredAt == null
        ? 0
        : DateTime.now().difference(_offeredAt!).inMilliseconds;
    // Only the *response* turn is scored. The child's own turn is a bonus
    // exchange counted in `initiated_greetings`; folding it into the score
    // would make a harder tier look like a higher one.
    if (_inReturnTurn) {
      _initiatedGreetings++;
      if (!_promptedThisRound) _returnTurnsUnprompted++;
    } else {
      _responseTimes.add(rt);
      _totalResponseTimeMs += rt;
      _score++;
      _promptLevels.add(_hintsUsedThisRound);
      if (!_promptedThisRound) _unpromptedRounds++;
    }

    analyticsRecordValidAction();
    analyticsRecordCorrect(extraData: {
      'greeting': button.greeting.slug,
      'response_time_ms': rt,
      'prompted': _promptedThisRound,
      'turn': _inReturnTurn ? 'child_initiated' : 'child_response',
    });
    _adaptive.recordCorrect();

    button.confirm();
    _buddy?.connect();
    onPlayCorrectSfx?.call();
    onPlayCorrectVo?.call();
    onCorrectGreeting?.call();

    // Tier 3: the exchange has a second half. The child, having answered, now
    // starts a greeting of their own and the buddy answers *them* — which is
    // the initiation half of the skill, and the harder half.
    if (_wantsReturnTurn && !_inReturnTurn) {
      _feedbackTimer =
          Timer(const Duration(milliseconds: 1200), _startReturnTurn);
      return;
    }

    _feedbackTimer = Timer(const Duration(milliseconds: 1300), _advanceRound);
  }

  /// The child's turn to greet first. Any card is correct here — the skill is
  /// *initiating*, and choosing which greeting to offer is the child's to make.
  void _startReturnTurn() {
    if (isRemoved) return;

    _inReturnTurn = true;
    _returnTurnsOffered++;
    _promptedThisRound = false;
    _hintsUsedThisRound = 0;
    _buddy?.setResting();

    // Whatever they pick is right, so the "target" is only there to keep the
    // prompt machinery and the analytics shape consistent.
    _target = _availableGreetings()[_random.nextInt(_choiceCount)];
    _buildButtons();

    onBuddyGreets?.call(_target!);
    _offeredAt = DateTime.now();
    _awaitingAnswer = true;
    _scheduleHint();
  }

  // ── Advancing ────────────────────────────────────────────────────────

  void _advanceRound() {
    if (isRemoved) return;

    // Always successful: there is no way to fail a round, only to take longer
    // or need more prompts. Both are recorded; neither ends the exchange.
    analyticsCompleteRound(successful: true);
    _currentRound++;
    onStepChanged(_currentRound);

    _buddy?.setResting();

    if (_currentRound >= totalRounds) {
      _feedbackTimer = Timer(const Duration(milliseconds: 700), _finish);
      return;
    }

    onPlayLevelCompleteSfx?.call();
    onPlayTransitionVo?.call();
    _feedbackTimer = Timer(const Duration(milliseconds: 1200), _startRound);
  }

  void _finish() {
    if (!tryBeginCompletion()) return;
    _cancelTimers();
    _clearPrompts();
    analyticsMarkCompleted();
    analyticsAddGameSpecificMetric('hint_count', _hintCount);
    analyticsAddGameSpecificMetric(
        'mean_greeting_latency_ms', _meanGreetingLatencyMs);
    analyticsAddGameSpecificMetric('mean_prompt_level', _meanPromptLevel);
    analyticsAddGameSpecificMetric(
        'return_greeting_accuracy', _returnGreetingAccuracy);
    analyticsCompleteSession();

    onPlayGameCompleteSfx?.call();
    onPlayCelebrationVo?.call();

    onGameComplete(
      score: _score,
      // One scored answer per round. On tier 3 the child's own turn is a bonus
      // exchange, not an extra item, so a stepped-up session is never compared
      // against a larger denominator than an easier one.
      totalItems: totalRounds,
      errorCount: _errorCount,
      totalResponseTimeMs: _totalResponseTimeMs,
      extras: {
        // The social measures. `unprompted_greetings` is the one that matters:
        // greeting back without needing a prompt is the target skill.
        'unprompted_greetings': _unpromptedRounds,
        'initiated_greetings': _initiatedGreetings,
        'wrong_greetings': _wrongGreetings,
        'hint_count': _hintCount,
        // How quickly the child answered a social bid, timed from the buddy
        // finishing its gesture. Emitted under both names: the shared
        // `mean_response_time_ms` so this game lines up with every other one,
        // and the explicit greeting name so the measure is legible on its own.
        'mean_response_time_ms': _meanGreetingLatencyMs,
        'mean_greeting_latency_ms': _meanGreetingLatencyMs,
        // The prompt rung the child needed. 0 across the board means every
        // greeting was returned unaided.
        'mean_prompt_level': _meanPromptLevel,
        'independent_rounds': _promptLevels.where((l) => l == 0).length,
        // Tier 3 only; 0 offered means the child never reached the exchange.
        'return_turns_offered': _returnTurnsOffered,
        'return_greeting_accuracy': _returnGreetingAccuracy,
        'buddy': character,
        'difficulty_level': profile.level,
      },
      analytics: analyticsSession,
    );
  }

  int get _meanGreetingLatencyMs => _responseTimes.isEmpty
      ? 0
      : (_responseTimes.reduce((a, b) => a + b) / _responseTimes.length).round();

  double get _meanPromptLevel => _promptLevels.isEmpty
      ? 0
      : _promptLevels.reduce((a, b) => a + b) / _promptLevels.length;

  /// Share of tier-3 second turns the child opened unprompted. 0 when no
  /// return turn was ever offered — which is the honest answer for tiers 1 and
  /// 2, where the exchange does not exist, and must not be read as a failure.
  double get _returnGreetingAccuracy => _returnTurnsOffered == 0
      ? 0
      : _returnTurnsUnprompted / _returnTurnsOffered;
}
