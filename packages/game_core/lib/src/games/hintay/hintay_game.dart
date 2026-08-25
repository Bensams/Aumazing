import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';

import 'components/sleepy_star.dart';
import '../shared/game_layout.dart';
import '../shared/ghost_hand.dart';
import '../../analytics/enhanced_analytics_mixin.dart';
import '../../analytics/models/models.dart';
import '../../config/adaptive_difficulty.dart';
import '../../config/difficulty_profile.dart';
import '../shared/game_lifecycle_guard.dart';

/// The core Flame game for "Hintay!" (Wait For It).
///
/// A go/no-go attention task. A star sleeps in the middle of the screen; after
/// an unpredictable delay it wakes, and the child taps it. Tapping while it is
/// still asleep is the measure this game exists to take — inhibitory control,
/// the ability to hold a prepared response until the cue arrives.
///
/// Why a game for this at all: [DifficultyProfile] and the AI service both
/// carry an `attention` skill area, and the model can return an
/// `attention_support` profile, but every other mini-game measures attention
/// only as a by-product of a communication, social, or play task. Here it is
/// the dependent variable.
///
/// Two therapeutic decisions worth keeping if this is ever refactored:
///
/// * **A premature tap does not end the trial.** It is recorded, the child is
///   gently redirected, and the same trial continues to its cue. Ending the
///   trial would teach that waiting is punished by losing the turn — the
///   opposite of what the task is meant to build.
/// * **No countdown is ever shown.** The unpredictability is the task; a
///   visible timer would let the child solve it by reading the clock, and a
///   ticking clock is exactly the anxiety source the app avoids elsewhere.
class HintayGame extends FlameGame
    with GameLifecycleGuard, TapCallbacks, EnhancedGameplayAnalyticsMixin {
  HintayGame({
    required this.onStepChanged,
    required this.onGameComplete,
    required this.childId,
    this.totalRounds = 4,
    this.gameVersion,
    this.profile = DifficultyProfile.medium,
    this.onCorrectWait,
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

  /// Fired on each successfully-waited-for tap (not just round completion).
  /// The Flutter layer uses it for haptic feedback and the mascot's nod.
  final void Function()? onCorrectWait;

  /// Fired on a premature tap. Pairs with the wrong SFX and the encouraging
  /// voice line so the mascot answers the mistake the same way the audio does.
  final void Function()? onWrongAnswer;

  // ── Audio event callbacks ────────────────────────────────────────────
  final VoidCallback? onPlayCorrectSfx;
  final VoidCallback? onPlayWrongSfx;
  final VoidCallback? onPlayTapSfx;
  final VoidCallback? onPlayLevelCompleteSfx;
  final VoidCallback? onPlayGameCompleteSfx;

  /// Praise after a correct wait. Unlike the object games there is no answer
  /// to name back ("red circle"), so this takes no label.
  final VoidCallback? onPlayCorrectVo;
  final VoidCallback? onPlayWrongVo;
  final VoidCallback? onPlayInstructionVo;

  /// Spoken alongside the pointing hand when the cue has been missed — the
  /// verbal rung of the prompt hierarchy, above the gestural one.
  ///
  /// Deliberately not spoken when the star wakes: a word landing inside the
  /// response window would be measured as part of the child's reaction time.
  final VoidCallback? onPlayHintVo;
  final VoidCallback? onPlayTransitionVo;
  final VoidCallback? onPlayCelebrationVo;

  final int totalRounds;
  final String childId;
  final String? gameVersion;

  /// Hint/guidance policy for the selected difficulty tier (ABA prompt
  /// hierarchy — see [DifficultyProfile]). Also sets the wait range and the
  /// width of the response window.
  final DifficultyProfile profile;

  /// Trials per round. Four rounds of three keeps the session at twelve
  /// discrete trials — enough for a stable premature-tap rate without
  /// outrunning a 2–6 year old's tolerance for a single activity.
  static const int trialsPerRound = 3;

  // ── Game state ───────────────────────────────────────────────────────
  int _currentRound = 0;
  int _trialInRound = 0;
  int _score = 0;
  int _errorCount = 0;
  int _totalResponseTimeMs = 0;

  /// Taps landed while the star was still asleep. The headline metric.
  int _prematureTaps = 0;

  /// Trials where the response window closed with no tap at all.
  int _missedTrials = 0;

  /// Response times for correctly-waited trials, in milliseconds.
  final List<int> _responseTimes = [];

  int _hintCount = 0;
  int _hintsUsedThisRound = 0;

  DateTime? _awakeAt;
  bool _trialResolved = false;

  Timer? _waitTimer;
  Timer? _windowTimer;
  Timer? _feedbackTimer;
  Timer? _hintTimer;

  SleepyStar? _star;

  /// Within-round adaptive stepping: repeated premature taps temporarily step
  /// the tier down (shorter waits, wider window) for the rest of the round.
  late final AdaptiveDifficulty _adaptive = AdaptiveDifficulty(profile);

  DifficultyProfile get _tier => _adaptive.effective;

  bool get _hintBudgetLeft =>
      _tier.unlimitedHints || _hintsUsedThisRound < (_tier.hintsPerRound ?? 0);

  final math.Random _random = math.Random();

  // ── Tier tuning ──────────────────────────────────────────────────────

  /// Shortest wait before the star wakes, before the round ramp. Never below
  /// ~1.2s: under that the child can succeed by tapping reflexively, which
  /// measures nothing.
  Duration get _baseMinWait {
    switch (_tier.level) {
      case 1:
        return const Duration(milliseconds: 1200);
      case 3:
        return const Duration(milliseconds: 2000);
      default:
        return const Duration(milliseconds: 1500);
    }
  }

  Duration get _baseMaxWait {
    switch (_tier.level) {
      case 1:
        return const Duration(milliseconds: 2600);
      case 3:
        return const Duration(milliseconds: 4800);
      default:
        return const Duration(milliseconds: 3600);
    }
  }

  /// How long the star stays awake waiting for a tap, before the round ramp.
  /// Generous on Easy: a slow responder should not be scored as inattentive.
  Duration get _baseResponseWindow {
    switch (_tier.level) {
      case 1:
        return const Duration(milliseconds: 3800);
      case 3:
        return const Duration(milliseconds: 2500);
      default:
        return const Duration(milliseconds: 3000);
    }
  }

  // ── Within-session round ramp ────────────────────────────────────────
  //
  // The tier is the between-session axis (set by the AI's attention level or
  // the parent). This ramp is the within-session one: later rounds hold the
  // child longer and give a slightly tighter window, so round 4 asks more than
  // round 1 without the task ever changing shape.
  //
  // Deliberately bounded inside the tier — an Easy round 4 stays easier than a
  // Medium round 1 — so `difficulty_level` in the results stays honest and the
  // parent-visible label keeps meaning what it says. [AdaptiveDifficulty] still
  // steps the tier down mid-round if the child starts struggling, which is what
  // keeps the ramp from compounding on a bad day.

  /// 0.0 on the first round, 1.0 on the last.
  double get _roundProgress =>
      totalRounds <= 1 ? 0 : _currentRound / (totalRounds - 1);

  /// Proportion the wait range grows by come the final round. Gentler on Easy:
  /// a child on the Easy tier is being taught to wait at all, not stretched.
  double get _waitRamp {
    switch (_tier.level) {
      case 1:
        return 0.20;
      case 3:
        return 0.35;
      default:
        return 0.28;
    }
  }

  /// Proportion the response window shrinks by come the final round. Much
  /// smaller than [_waitRamp] on purpose: a longer wait is the skill being
  /// trained, whereas a narrow window mostly penalises slow motor planning.
  double get _windowRamp {
    switch (_tier.level) {
      case 1:
        return 0.08;
      case 3:
        return 0.16;
      default:
        return 0.12;
    }
  }

  /// Floor on the response window regardless of tier and round — below this a
  /// child with slower motor planning is scored as inattentive when they are
  /// not.
  static const int _minResponseWindowMs = 1800;

  Duration get _minWait => Duration(
        milliseconds:
            (_baseMinWait.inMilliseconds * (1 + _waitRamp * _roundProgress))
                .round(),
      );

  Duration get _maxWait => Duration(
        milliseconds:
            (_baseMaxWait.inMilliseconds * (1 + _waitRamp * _roundProgress))
                .round(),
      );

  Duration get _responseWindow => Duration(
        milliseconds: math.max(
          _minResponseWindowMs,
          (_baseResponseWindow.inMilliseconds *
                  (1 - _windowRamp * _roundProgress))
              .round(),
        ),
      );

  double get _starRadius {
    final available = math.min(size.x, size.y - kTopOverlayBand);
    return math.min(available * 0.24, 130);
  }

  Vector2 get _starCentre => Vector2(
        size.x / 2,
        kTopOverlayBand + (size.y - kTopOverlayBand) / 2,
      );

  // ── Lifecycle ────────────────────────────────────────────────────────

  @override
  Color backgroundColor() => const Color(0x00000000); // Transparent

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    if (!isLifecycleActive) return;

    analyticsInitialize(
      gameId: 'hintay',
      childId: childId,
      totalRounds: totalRounds,
      gameVersion: gameVersion,
    );
    analyticsStartSession();

    _star = SleepyStar(position: _starCentre, radius: _starRadius);
    add(_star!);

    onPlayInstructionVo?.call();
    _startRound();
  }

  @override
  void onGameResize(Vector2 newSize) {
    super.onGameResize(newSize);
    _star?.position = _starCentre;
  }

  @override
  void onRemove() {
    _cancelTimers();
    super.onRemove();
  }

  void _cancelTimers() {
    _waitTimer?.cancel();
    _windowTimer?.cancel();
    _feedbackTimer?.cancel();
    _hintTimer?.cancel();
    _waitTimer = _windowTimer = _feedbackTimer = _hintTimer = null;
  }

  // ── Round / trial flow ───────────────────────────────────────────────

  void _startRound() {
    if (!isLifecycleActive) return;
    _trialInRound = 0;
    _hintsUsedThisRound = 0;
    _adaptive.startRound();
    analyticsStartRound(roundNumber: _currentRound + 1);
    _startTrial();
  }

  void _startTrial() {
    if (isRemoved) return;

    _trialResolved = false;
    _awakeAt = null;
    _star?.setState(StarState.asleep);

    final min = _minWait.inMilliseconds;
    final max = _maxWait.inMilliseconds;
    final wait = min + _random.nextInt(math.max(max - min, 1));

    _waitTimer = Timer(Duration(milliseconds: wait), _wake);
  }

  void _wake() {
    if (isRemoved || _trialResolved) return;

    _awakeAt = DateTime.now();
    _star?.setState(StarState.awake);
    analyticsShowStimulus();
    onPlayTapSfx?.call();

    // Guided demo on the Easy tier's first trial only: show *where* to tap
    // once the cue has already arrived, so the demo never models tapping a
    // sleeping star.
    if (_tier.guidedDemo && _currentRound == 0 && _trialInRound == 0) {
      _showGhostHand();
    }

    // Prompt if the cue is missed — an ABA-style least-to-most escalation
    // rather than simply timing out in silence.
    if (_hintBudgetLeft) {
      _hintTimer = Timer(_tier.idleHintDelay, () {
        if (_trialResolved || isRemoved) return;
        _hintCount++;
        _hintsUsedThisRound++;
        analyticsRecordHint(hintType: 'cue_missed_pointer');
        _showGhostHand();
        onPlayHintVo?.call();
      });
    }

    _windowTimer = Timer(_responseWindow, _missTrial);
  }

  void _showGhostHand() {
    final star = _star;
    if (star == null) return;
    add(GhostHand.tap(at: star.position.clone()));
  }

  /// The window closed with no tap. Scored as an error, but treated softly:
  /// the star simply goes back to sleep and the next trial begins.
  void _missTrial() {
    if (_trialResolved || isRemoved) return;
    _trialResolved = true;

    _missedTrials++;
    _errorCount++;
    analyticsRecordWrong(extraData: {'reason': 'no_response'});
    analyticsRecordIdleTime(_responseWindow.inSeconds);
    _star?.setState(StarState.asleep);
    onPlayWrongSfx?.call();

    _advanceTrial();
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (!isLifecycleActive || isCompletionStarted) return;
    super.onTapDown(event);
    final star = _star;
    if (star == null || _trialResolved) return;
    final point = event.localPosition;
    final onStar = star.distanceFrom(point) <= star.radius * 1.25;

    if (star.state == StarState.awake) {
      if (!onStar) {
        // Tapped the empty canvas while the cue was up. Recorded, but not
        // scored against the trial — the child is still responding to the cue.
        analyticsRecordTouch(Offset(point.x, point.y), isValid: false);
        analyticsRecordOffTaskAction(actionType: 'tap_off_target');
        return;
      }
      _resolveCorrect();
      return;
    }

    // The star is still asleep: a premature response. This is the signal.
    _recordPremature(point);
  }

  void _recordPremature(Vector2 point) {
    _prematureTaps++;
    _errorCount++;

    // isValid: false routes this into randomTouchCount, which the feature
    // aggregator reads as overall_invalid_touch_count.
    analyticsRecordTouch(Offset(point.x, point.y), isValid: false);
    analyticsRecordWrong(extraData: {'reason': 'premature_tap'});
    _adaptive.recordError();

    onPlayWrongSfx?.call();
    onPlayWrongVo?.call();
    onWrongAnswer?.call();

    // Deliberately no state change and no trial end: the star stays asleep and
    // this trial still runs to its cue.
  }

  void _resolveCorrect() {
    if (!isLifecycleActive || isCompletionStarted || _trialResolved) return;
    _trialResolved = true;
    _windowTimer?.cancel();
    _hintTimer?.cancel();

    final rt = _awakeAt == null
        ? 0
        : DateTime.now().difference(_awakeAt!).inMilliseconds;
    _responseTimes.add(rt);
    _totalResponseTimeMs += rt;
    _score++;

    analyticsRecordValidAction();
    analyticsRecordCorrect(extraData: {'response_time_ms': rt});
    _adaptive.recordCorrect();

    _star?.setState(StarState.happy);
    onPlayCorrectSfx?.call();
    onPlayCorrectVo?.call();
    onCorrectWait?.call();

    _advanceTrial();
  }

  void _advanceTrial() {
    _trialInRound++;

    if (_trialInRound < trialsPerRound) {
      _feedbackTimer = Timer(const Duration(milliseconds: 1100), _startTrial);
      return;
    }

    // Round finished.
    analyticsCompleteRound(successful: true);
    _currentRound++;
    onStepChanged(_currentRound);

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
    analyticsMarkCompleted();
    analyticsCompleteSession();

    onPlayGameCompleteSfx?.call();
    onPlayCelebrationVo?.call();

    onGameComplete(
      score: _score,
      totalItems: totalRounds * trialsPerRound,
      errorCount: _errorCount,
      totalResponseTimeMs: _totalResponseTimeMs,
      extras: {
        'premature_taps': _prematureTaps,
        'missed_trials': _missedTrials,
        'hint_count': _hintCount,
        'mean_response_time_ms': _responseTimes.isEmpty
            ? 0
            : (_responseTimes.reduce((a, b) => a + b) / _responseTimes.length)
                .round(),
        'difficulty_level': profile.level,
      },
      analytics: analyticsSession,
    );
  }
}
